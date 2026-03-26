import 'dart:math' show asin, cos, sqrt;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:uuid/uuid.dart';

import '../models/driver_transfer_model.dart';
import '../models/order_model.dart';
import '../utils/phone_utils.dart';
import 'chat_service.dart';
import 'order_service.dart';

/// Service untuk Oper Driver: transfer penumpang dari driver pertama ke driver kedua.
class DriverTransferService {
  static const String _collectionTransfers = 'driver_transfers';

  /// Prefix barcode payload untuk oper driver: TRAKA:T:transferId:uuid
  static String createTransferBarcodePayload(String transferId) {
    return 'TRAKA:T:$transferId:${const Uuid().v4()}';
  }

  /// Parse barcode oper: TRAKA:T:transferId:*
  static (String?, String?) parseTransferBarcodePayload(String raw) {
    final parts = raw.trim().split(':');
    if (parts.length < 4) return (null, 'Format barcode tidak valid.');
    if (parts[0] != 'TRAKA' || parts[2] != 'T') {
      return (null, 'Barcode bukan barcode Oper Driver Traka.');
    }
    return (parts[1], null);
  }

  /// Buat transfer oper driver. Return (transferId, barcodePayload) atau (null, error).
  /// Phone only (Phone Auth). toDriverEmail opsional untuk legacy.
  static Future<(String?, String?, String?)> createTransfer({
    required String orderId,
    required String toDriverUid,
    String toDriverEmail = '',
    required String toDriverPhone,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return (null, null, 'Anda belum login.');

    final firestore = FirebaseFirestore.instance;
    final orderRef = firestore.collection('orders').doc(orderId);
    final orderDoc = await orderRef.get();
    if (!orderDoc.exists || orderDoc.data() == null) {
      return (null, null, 'Pesanan tidak ditemukan.');
    }
    final orderData = orderDoc.data()!;
    if ((orderData['driverUid'] as String?) != user.uid) {
      return (null, null, 'Anda bukan driver pesanan ini.');
    }
    if ((orderData['status'] as String?) != OrderService.statusPickedUp) {
      return (null, null, 'Hanya penumpang yang sudah dijemput yang bisa dioper.');
    }
    if ((orderData['orderType'] as String?) != OrderModel.typeTravel) {
      return (null, null, 'Oper hanya untuk pesanan travel.');
    }
    if (toDriverUid == user.uid) {
      return (null, null, 'Tidak bisa mengoper ke diri sendiri.');
    }

    // Validasi driver kedua: role = driver
    final toDriverDoc = await firestore.collection('users').doc(toDriverUid).get();
    if (!toDriverDoc.exists) return (null, null, 'Driver kedua tidak ditemukan.');
    final toDriverData = toDriverDoc.data() ?? {};
    if ((toDriverData['role'] as String?) != 'driver') {
      return (null, null, 'User yang dipilih bukan driver.');
    }
    final phone = (toDriverData['phoneNumber'] as String?) ?? '';
    final phoneMatch = toE164OrNull(toDriverPhone) == toE164OrNull(phone);
    if (!phoneMatch) {
      return (null, null, 'Nomor HP tidak cocok dengan driver.');
    }

    // Validasi kapasitas mobil driver kedua
    final orderModel = OrderModel.fromFirestore(orderDoc);
    final totalPenumpang = orderModel.totalPenumpang;
    final capacity = (toDriverData['vehicleJumlahPenumpang'] as num?)?.toInt() ?? 0;
    if (capacity <= 0) {
      return (null, null, 'Driver kedua belum mengisi kapasitas mobil.');
    }
    if (totalPenumpang > capacity) {
      return (null, null, 'Kapasitas mobil driver kedua ($capacity orang) tidak cukup untuk $totalPenumpang penumpang.');
    }

    return _createTransferDoc(orderId, user.uid, toDriverUid, firestore);
  }

  static Future<(String?, String?, String?)> _createTransferDoc(
    String orderId,
    String fromDriverUid,
    String toDriverUid,
    FirebaseFirestore firestore,
  ) async {
    final transferRef = firestore.collection(_collectionTransfers).doc();
    final transferId = transferRef.id;
    final barcodePayload = createTransferBarcodePayload(transferId);

    await transferRef.set({
      'orderId': orderId,
      'fromDriverUid': fromDriverUid,
      'toDriverUid': toDriverUid,
      'status': DriverTransferModel.statusPending,
      'createdAt': FieldValue.serverTimestamp(),
    });

    return (transferId, barcodePayload, null);
  }

  /// Driver kedua scan barcode untuk menerima oper. Return (success, error).
  /// Cukup scan barcode ke driver yang dioper; tidak perlu email+password (Phone Auth compatible).
  static Future<(bool, String?)> applyDriverScanTransfer(
    String rawPayload, {
    double? toDriverLat,
    double? toDriverLng,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return (false, 'Anda belum login.');

    final (transferId, parseError) = parseTransferBarcodePayload(rawPayload);
    if (transferId == null) return (false, parseError ?? 'Payload tidak valid.');

    final firestore = FirebaseFirestore.instance;
    final transferRef = firestore.collection(_collectionTransfers).doc(transferId);
    final transferDoc = await transferRef.get();
    if (!transferDoc.exists || transferDoc.data() == null) {
      return (false, 'Transfer tidak ditemukan.');
    }
    final transferData = transferDoc.data()!;
    if ((transferData['toDriverUid'] as String?) != user.uid) {
      return (false, 'Barcode ini bukan untuk Anda.');
    }
    if ((transferData['status'] as String?) != DriverTransferModel.statusPending) {
      return (false, 'Transfer sudah diproses.');
    }

    return _completeTransfer(
      transferDoc.reference,
      transferData,
      user.uid,
      toDriverLat,
      toDriverLng,
      firestore,
    );
  }

  static Future<(bool, String?)> _completeTransfer(
    DocumentReference transferRef,
    Map<String, dynamic> transferData,
    String toDriverUid,
    double? toDriverLat,
    double? toDriverLng,
    FirebaseFirestore firestore,
  ) async {
    final orderId = transferData['orderId'] as String?;
    if (orderId == null || orderId.isEmpty) return (false, 'Data transfer tidak valid.');

    final orderRef = firestore.collection('orders').doc(orderId);
    final orderDoc = await orderRef.get();
    if (!orderDoc.exists || orderDoc.data() == null) {
      return (false, 'Pesanan tidak ditemukan.');
    }
    final orderData = orderDoc.data()!;
    final fromDriverUid = transferData['fromDriverUid'] as String? ?? '';
    final pickupLat = (orderData['pickupLat'] as num?)?.toDouble();
    final pickupLng = (orderData['pickupLng'] as num?)?.toDouble();
    final destLat = (orderData['destLat'] as num?)?.toDouble();
    final destLng = (orderData['destLng'] as num?)?.toDouble();

    final transferLat = toDriverLat;
    final transferLng = toDriverLng;

    final tarifPerKm = await _getTarifPerKm();
    final distance1 = (pickupLat != null && pickupLng != null && transferLat != null && transferLng != null)
        ? _haversineKm(pickupLat, pickupLng, transferLat, transferLng)
        : null;
    final distance2 = (transferLat != null && transferLng != null && destLat != null && destLng != null)
        ? _haversineKm(transferLat, transferLng, destLat, destLng)
        : null;

    double? fare1;
    double? fare2;
    if (distance1 != null && distance2 != null && distance1 + distance2 > 0) {
      fare1 = distance1 * tarifPerKm;
      fare2 = distance2 * tarifPerKm;
    }

    final driverSegments = List<Map<String, dynamic>>.from(
      (orderData['driverSegments'] as List<dynamic>?) ?? [],
    );
    driverSegments.add({
      'driverUid': fromDriverUid,
      'distanceKm': distance1,
      'fareRupiah': fare1?.round(),
      'segmentType': 'pickup_to_transfer',
    });
    driverSegments.add({
      'driverUid': toDriverUid,
      'distanceKm': distance2,
      'fareRupiah': fare2?.round(),
      'segmentType': 'transfer_to_dest',
    });

    // Kontribusi driver 1: di-handle Cloud Function onDriverTransferScanned (client tidak bisa update users driver lain)
    final batch = firestore.batch();
    batch.update(transferRef, {
      'status': DriverTransferModel.statusScanned,
      'scannedAt': FieldValue.serverTimestamp(),
      'transferLat': transferLat,
      'transferLng': transferLng,
      'toDriverStartLat': toDriverLat,
      'toDriverStartLng': toDriverLng,
    });
    batch.update(orderRef, {
      'driverUid': toDriverUid,
      'pickupLat': transferLat,
      'pickupLng': transferLng,
      'driverSegments': driverSegments,
      'updatedAt': FieldValue.serverTimestamp(),
    });

    await batch.commit();

    // Notifikasi ke penumpang: driver baru akan melanjutkan perjalanan
    if (orderId.isNotEmpty) {
      await ChatService.sendMessage(
        orderId,
        'Saya akan melanjutkan perjalanan Anda. Silakan siap untuk dijemput.',
      );
    }

    return (true, null);
  }

  static double _haversineKm(double lat1, double lng1, double lat2, double lng2) {
    const p = 0.017453292519943295;
    final a = 0.5 -
        cos((lat2 - lat1) * p) / 2 +
        cos(lat1 * p) * cos(lat2 * p) * (1 - cos((lng2 - lng1) * p)) / 2;
    return 12742 * asin(sqrt(a));
  }

  static Future<int> _getTarifPerKm() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('app_config')
          .doc('settings')
          .get();
      final v = doc.data()?['tarifPerKm'];
      if (v != null) {
        final n = (v is num) ? v.toInt() : int.tryParse(v.toString());
        if (n != null && n > 0) return n.clamp(70, 85);
      }
    } catch (_) {}
    return 70;
  }

  /// Stream transfer yang menunggu driver kedua (untuk tab Oper ke Saya).
  static Stream<List<DriverTransferModel>> streamTransfersForDriver(String driverUid) {
    return FirebaseFirestore.instance
        .collection(_collectionTransfers)
        .where('toDriverUid', isEqualTo: driverUid)
        .where('status', isEqualTo: DriverTransferModel.statusPending)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snap) => snap.docs.map((d) => DriverTransferModel.fromFirestore(d)).toList());
  }

  /// Ambil info driver + order untuk tampilan Oper ke Saya. Return {fromName, passengerName, destText, totalPenumpang}.
  static Future<Map<String, dynamic>> getTransferDisplayInfo(DriverTransferModel transfer) async {
    final driverFuture = getDriverInfo(transfer.fromDriverUid);
    final orderFuture = getOrderInfoForTransfer(transfer.orderId);
    final driverInfo = await driverFuture;
    final orderInfo = await orderFuture;
    return {
      'fromName': driverInfo['displayName'] ?? 'Driver',
      'passengerName': orderInfo['passengerName'] ?? '-',
      'destText': orderInfo['destText'] ?? '-',
      'totalPenumpang': orderInfo['totalPenumpang'] ?? 1,
    };
  }

  /// Ambil info order untuk tampilan di Oper ke Saya (nama penumpang, tujuan, jumlah).
  static Future<Map<String, dynamic>> getOrderInfoForTransfer(String orderId) async {
    final doc = await FirebaseFirestore.instance.collection('orders').doc(orderId).get();
    final d = doc.data();
    if (d == null) return {'passengerName': null, 'destText': null, 'totalPenumpang': 0};
    final jumlahKerabat = (d['jumlahKerabat'] as num?)?.toInt() ?? 0;
    final totalPenumpang = 1 + (jumlahKerabat > 0 ? jumlahKerabat : 0);
    return {
      'passengerName': d['passengerName'] as String? ?? '-',
      'destText': (d['destText'] as String?)?.trim().isNotEmpty == true ? (d['destText'] as String) : '-',
      'totalPenumpang': totalPenumpang,
    };
  }

  /// Ambil info driver dari users (termasuk kapasitas mobil).
  static Future<Map<String, dynamic>> getDriverInfo(String uid) async {
    final doc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
    final d = doc.data();
    if (d == null) return {'displayName': null, 'photoUrl': null, 'email': null, 'phoneNumber': null, 'vehicleJumlahPenumpang': null};
    return {
      'displayName': d['displayName'] as String?,
      'photoUrl': d['photoUrl'] as String?,
      'email': d['email'] as String?,
      'phoneNumber': d['phoneNumber'] as String?,
      'vehicleJumlahPenumpang': (d['vehicleJumlahPenumpang'] as num?)?.toInt(),
    };
  }
}
