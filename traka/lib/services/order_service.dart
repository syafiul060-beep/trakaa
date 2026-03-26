import 'dart:async';
import 'dart:math' show asin, cos, sqrt;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'geocoding_service.dart';
import 'package:uuid/uuid.dart';

import 'app_config_service.dart';
import 'schedule_id_util.dart';
import 'ferry_distance_service.dart';
import 'lacak_barang_service.dart';
import 'order_number_service.dart';
import 'chat_service.dart';
import 'traka_api_service.dart';
import 'verification_service.dart';

import '../config/traka_api_config.dart';

import '../models/jarak_kontribusi_preview.dart';
import '../models/order_model.dart';
import '../utils/app_logger.dart' show log, logError;
import '../utils/phone_utils.dart';

/// Service untuk pesanan penumpang (nomor pesanan, kesepakatan driver-penumpang).
/// Nomor pesanan unik; dibuat otomatis saat driver dan penumpang sama-sama klik kesepakatan.
class OrderService {
  static const String _collectionOrders = 'orders';
  static const String _fieldRouteJourneyNumber = 'routeJourneyNumber';
  static const String _fieldDriverUid = 'driverUid';
  static const String _fieldPassengerUid = 'passengerUid';
  static const String _fieldStatus = 'status';

  static const String statusAgreed = 'agreed';
  static const String statusPickedUp = 'picked_up';
  static const String statusCompleted = 'completed';
  static const String statusPendingAgreement = 'pending_agreement';
  /// Kirim barang: menunggu penerima setuju jadi penerima.
  static const String statusPendingReceiver = 'pending_receiver';
  static const String statusCancelled = 'cancelled';

  /// Cache singkat hasil [activeScheduleIdsForDriverOrders] per driver (kurangi query berulang saat cleanup jadwal, dll.).
  static final Map<String, (DateTime, Set<String>)> _activeScheduleIdsCache = {};
  static const Duration _activeScheduleIdsCacheTtl = Duration(seconds: 12);

  /// Nilai routeJourneyNumber untuk pesanan terjadwal (dari Pesan nanti).
  static const String routeJourneyNumberScheduled = 'scheduled';

  /// **Satu definisi** untuk blokir beranda penumpang (cari driver baru).
  /// Hanya [OrderModel.typeTravel]. Blokir **setelah** kesepakatan harga: [statusAgreed] / [statusPickedUp].
  /// [statusPendingAgreement] (chat / pesan otomatis pertama, belum sepakat harga) **tidak** memblokir.
  /// Selesai ([statusCompleted]) / batal ([statusCancelled]) → tidak blokir.
  static bool isTravelOrderBlockingPassengerHomeMap(OrderModel order) {
    if (order.orderType != OrderModel.typeTravel) return false;
    final s = order.status;
    if (s == statusCompleted || s == statusCancelled) return false;
    return s == statusAgreed || s == statusPickedUp;
  }

  /// True jika ada minimal satu travel yang memblokir peta beranda penumpang.
  static bool passengerOrdersContainBlockingTravel(Iterable<OrderModel> orders) {
    for (final o in orders) {
      if (isTravelOrderBlockingPassengerHomeMap(o)) return true;
    }
    return false;
  }

  /// Status travel yang dianggap "berjalan" untuk notifikasi jarak / UX (bukan blokir beranda).
  static bool isTravelOrderInProgressForNotifications(OrderModel order) {
    if (order.orderType != OrderModel.typeTravel) return false;
    return order.status == statusAgreed || order.status == statusPickedUp;
  }

  /// `agreed` atau `picked_up` — **semua** [OrderModel.orderType] (travel + kirim barang).
  /// Dipakai notifikasi jarak driver, filter stream lokasi, dll.
  static bool isOrderAgreedOrPickedUp(OrderModel order) {
    final s = order.status;
    return s == statusAgreed || s == statusPickedUp;
  }

  /// UID driver yang punya travel `agreed`/`picked_up` (untuk kunci hapus chat travel pending dengan driver lain).
  static Set<String> travelAgreedDriverUidsFromOrders(Iterable<OrderModel> orders) {
    final s = <String>{};
    for (final o in orders) {
      if (o.orderType == OrderModel.typeTravel &&
          (o.status == statusAgreed || o.status == statusPickedUp)) {
        s.add(o.driverUid);
      }
    }
    return s;
  }

  /// Travel `pending_agreement` dengan driver **bukan** yang sudah ada kesepakatan — tidak boleh dihapus dari list Pesan.
  /// [Kirim barang] tidak pernah terkunci oleh aturan ini.
  static bool isPassengerTravelPendingLockedOtherDriver(
    OrderModel order,
    Set<String> travelAgreedDriverUids,
  ) {
    if (order.isKirimBarang) return false;
    if (order.orderType != OrderModel.typeTravel) return false;
    if (order.status == statusAgreed || order.status == statusPickedUp) return false;
    if (order.status == statusCompleted || order.status == statusCancelled) return false;
    if (travelAgreedDriverUids.isEmpty) return false;
    return !travelAgreedDriverUids.contains(order.driverUid);
  }

  /// Untuk validasi server: UID driver travel yang sudah `agreed`/`picked_up` milik penumpang.
  static Future<Set<String>> getTravelAgreedDriverUidsForPassenger(String passengerUid) async {
    try {
      final q = await FirebaseFirestore.instance
          .collection(_collectionOrders)
          .where(_fieldPassengerUid, isEqualTo: passengerUid)
          .where(_fieldStatus, whereIn: [statusAgreed, statusPickedUp])
          .get();
      final set = <String>{};
      for (final doc in q.docs) {
        final d = doc.data();
        if ((d['orderType'] as String?) == OrderModel.typeTravel) {
          final du = d[_fieldDriverUid] as String?;
          if (du != null) set.add(du);
        }
      }
      return set;
    } catch (e, st) {
      logError('OrderService.getTravelAgreedDriverUidsForPassenger', e, st);
      return {};
    }
  }

  /// Cari user (penerima) by email atau no. telepon. Return {uid, displayName, photoUrl} atau null.
  /// Phone Auth: phoneNumber primary. Email opsional.
  static Future<Map<String, dynamic>?> findUserByEmailOrPhone(String input) async {
    final trim = input.trim();
    if (trim.isEmpty) return null;
    try {
      if (trim.contains('@')) {
        final q = await FirebaseFirestore.instance
            .collection('users')
            .where('email', isEqualTo: trim.toLowerCase())
            .limit(1)
            .get();
        if (q.docs.isNotEmpty) {
          final d = q.docs.first.data();
          return {
            'uid': q.docs.first.id,
            'displayName': d['displayName'] as String?,
            'photoUrl': d['photoUrl'] as String?,
          };
        }
      } else {
        // Coba format asli, lalu E.164 (0812.., 812.., 62812..)
        final variants = <String>[trim];
        final e164 = toE164OrNull(trim);
        if (e164 != null && !variants.contains(e164)) variants.add(e164);
        for (final v in variants) {
          final q = await FirebaseFirestore.instance
              .collection('users')
              .where('phoneNumber', isEqualTo: v)
              .limit(1)
              .get();
          if (q.docs.isNotEmpty) {
            final d = q.docs.first.data();
            return {
              'uid': q.docs.first.id,
              'displayName': d['displayName'] as String?,
              'photoUrl': d['photoUrl'] as String?,
            };
          }
        }
      }
    } catch (e, st) {
      logError('OrderService.findUserByEmailOrPhone', e, st);
    }
    return null;
  }

  /// Riwayat penerima untuk pengirim (dari order kirim_barang sebelumnya).
  /// Return List<{uid, displayName, photoUrl}> unik, terurut terbaru dulu, max 10.
  static Future<List<Map<String, dynamic>>> getRecentReceivers(String passengerUid) async {
    if (passengerUid.isEmpty) return [];
    try {
      final snap = await FirebaseFirestore.instance
          .collection(_collectionOrders)
          .where(_fieldPassengerUid, isEqualTo: passengerUid)
          .where('orderType', isEqualTo: OrderModel.typeKirimBarang)
          .orderBy('createdAt', descending: true)
          .limit(50)
          .get();

      final seen = <String>{};
      final list = <Map<String, dynamic>>[];
      for (final doc in snap.docs) {
        final d = doc.data();
        final uid = d['receiverUid'] as String?;
        if (uid == null || uid.isEmpty || seen.contains(uid)) continue;
        if (uid == passengerUid) continue; // jangan tampilkan diri sendiri
        seen.add(uid);
        list.add({
          'uid': uid,
          'displayName': d['receiverName'] as String? ?? 'Penerima',
          'photoUrl': d['receiverPhotoUrl'] as String?,
        });
        if (list.length >= 10) break;
      }
      return list;
    } catch (e, st) {
      logError('OrderService.getRecentReceivers', e, st);
      return [];
    }
  }

  /// Radius "dekat" untuk tombol Batal dinonaktifkan (meter).
  static const int radiusDekatMeter = 300;

  /// Radius maksimal agar icon panggilan suara aktif: driver ≤ 5 km dari penumpang.
  static const int radiusVoiceCallKm = 5;

  /// Radius "berdekatan" untuk scan/konfirmasi (meter). Driver dan penumpang dalam 30 m boleh scan penjemputan/selesai tanpa harus di titik awal/tujuan.
  static const int radiusBerdekatanMeter = 30;

  /// Radius "menjauh" untuk auto-complete (meter). Jika driver dan penumpang berjarak > ini setelah dijemput → pesanan selesai otomatis.
  static const int radiusMenjauhMeter = 500;

  /// Jarak antara dua titik (haversine) dalam km.
  static double _haversineKm(
    double lat1,
    double lng1,
    double lat2,
    double lng2,
  ) {
    const p = 0.017453292519943295; // pi/180
    final a =
        0.5 -
        cos((lat2 - lat1) * p) / 2 +
        cos(lat1 * p) * cos(lat2 * p) * (1 - cos((lng2 - lng1) * p)) / 2;
    return 12742 * asin(sqrt(a)); // 2*R*asin (R=6371 km)
  }

  /// Jarak antara dua titik dalam meter (untuk validasi radius).
  static double _distanceMeters(
    double lat1,
    double lng1,
    double lat2,
    double lng2,
  ) {
    return _haversineKm(lat1, lng1, lat2, lng2) * 1000;
  }

  /// Jarak lurus (km), estimasi ferry (km), dan jarak yang dipakai untuk tarif/kontribusi (setelah kurangi ferry).
  static Future<({double km, double ferryKm, double effectiveKm})> _travelKmFerryEffective(
    double pickLat,
    double pickLng,
    double dropLat,
    double dropLng,
  ) async {
    final km = _haversineKm(pickLat, pickLng, dropLat, dropLng);
    double ferry = 0;
    final est = await FerryDistanceService.getEstimatedFerryKm(
      originLat: pickLat,
      originLng: pickLng,
      destLat: dropLat,
      destLng: dropLng,
    );
    if (est != null && est > 0) {
      ferry = est.toDouble();
      if (ferry > km) ferry = km;
    }
    final effectiveKm = (km - ferry).clamp(0.0, double.infinity);
    return (km: km, ferryKm: ferry, effectiveKm: effectiveKm);
  }

  /// Cek apakah lokasi scan (scanLat, scanLng) berada di area tujuan (destLat, destLng) sesuai level.
  /// Level: desa (subLocality), kecamatan (locality), kabupaten (subAdministrativeArea), provinsi (administrativeArea).
  /// Penumpang tidak harus di titik tepat tujuan—cukup sama wilayah admin (desa/kecamatan/kabupaten/provinsi).
  /// Return (true, null) jika cocok; (false, errorMsg) jika tidak cocok atau geocoding gagal.
  static Future<(bool, String?)> _isAtDestinationLevel(
    double scanLat,
    double scanLng,
    double destLat,
    double destLng,
    String level,
  ) async {
    try {
      final scanPms = await GeocodingService.placemarkFromCoordinates(scanLat, scanLng);
      final destPms = await GeocodingService.placemarkFromCoordinates(destLat, destLng);
      if (scanPms.isEmpty || destPms.isEmpty) {
        return (false, 'Tidak dapat memverifikasi lokasi. Pastikan GPS aktif dan coba lagi.');
      }
      final scan = scanPms.first;
      final dest = destPms.first;
      String norm(String? s) => (s ?? '').trim().toLowerCase();
      bool atDest;
      switch (level) {
        case 'desa':
          final s = norm(scan.subLocality);
          final d = norm(dest.subLocality);
          if (s.isEmpty || d.isEmpty) {
            atDest = true;
          } else {
            atDest = s == d;
          }
          break;
        case 'kecamatan':
          final s = norm(scan.locality);
          final d = norm(dest.locality);
          if (s.isEmpty || d.isEmpty) {
            atDest = true;
          } else {
            atDest = s == d;
          }
          break;
        case 'kabupaten':
          final s = norm(scan.subAdministrativeArea);
          final d = norm(dest.subAdministrativeArea);
          if (s.isEmpty || d.isEmpty) {
            atDest = true;
          } else {
            atDest = s == d;
          }
          break;
        case 'provinsi':
          final s = norm(scan.administrativeArea);
          final d = norm(dest.administrativeArea);
          if (s.isEmpty || d.isEmpty) {
            atDest = true;
          } else {
            atDest = s == d;
          }
          break;
        default:
          atDest = true;
      }
      if (atDest) return (true, null);
      return (false, 'Scan barcode hanya bisa dilakukan saat Anda sudah tiba di $level tujuan.');
    } catch (e, st) {
      logError('OrderService._canScanBarcode', e, st);
      return (false, 'Tidak dapat memverifikasi lokasi. Pastikan GPS aktif dan coba lagi.');
    }
  }

  /// Ambil posisi driver dari driver_status (untuk validasi scan penumpang).
  static Future<(double?, double?)> _getDriverPosition(String driverUid) async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('driver_status')
          .doc(driverUid)
          .get();
      final d = doc.data();
      if (d == null) return (null, null);
      final lat = (d['latitude'] as num?)?.toDouble();
      final lng = (d['longitude'] as num?)?.toDouble();
      return (lat, lng);
    } catch (_) {
      return (null, null);
    }
  }

  /// Jumlah pesanan aktif (status agreed atau picked_up) untuk suatu nomor rute.
  static Future<int> countActiveOrdersForRoute(
    String routeJourneyNumber,
  ) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return 0;

    final snapshot = await FirebaseFirestore.instance
        .collection(_collectionOrders)
        .where(_fieldRouteJourneyNumber, isEqualTo: routeJourneyNumber)
        .where(_fieldDriverUid, isEqualTo: user.uid)
        .where(_fieldStatus, whereIn: [statusAgreed, statusPickedUp])
        .get();

    return snapshot.docs.length;
  }

  /// Slot terpakai (penumpang + kargo) untuk rute. Untuk currentPassengerCount di driver_status.
  /// Kargo mengurangi kapasitas; dokumen tidak.
  static Future<int> countUsedSlotsForRoute(String routeJourneyNumber) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return 0;

    final kargoSlot = await AppConfigService.getKargoSlotPerOrder();
    final snapshot = await FirebaseFirestore.instance
        .collection(_collectionOrders)
        .where(_fieldRouteJourneyNumber, isEqualTo: routeJourneyNumber)
        .where(_fieldDriverUid, isEqualTo: user.uid)
        .where(_fieldStatus, whereIn: [statusAgreed, statusPickedUp])
        .get();

    int used = 0;
    for (final doc in snapshot.docs) {
      final d = doc.data();
      final orderType = (d['orderType'] as String?) ?? 'travel';
      if (orderType == OrderModel.typeKirimBarang) {
        final cat = (d['barangCategory'] as String?) ?? '';
        if (cat == OrderModel.barangCategoryKargo || cat.isEmpty) {
          used += (kargoSlot.ceil()).clamp(1, 10);
        }
      } else {
        final jk = (d['jumlahKerabat'] as num?)?.toInt();
        used += (jk == null || jk <= 0) ? 1 : (1 + jk);
      }
    }
    return used;
  }

  /// Jumlah pesanan yang sudah dijemput (status picked_up) untuk suatu nomor rute.
  /// Termasuk: penumpang yang sudah dijemput (driver scan barcode penumpang) dan kirim barang yang sudah dijemput.
  /// Dipakai untuk validasi "Selesai Bekerja": tombol tidak bisa diklik jika count > 0; jika masih kosong boleh diklik.
  static Future<int> countPickedUpOrdersForRoute(
    String routeJourneyNumber,
  ) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return 0;

    final snapshot = await FirebaseFirestore.instance
        .collection(_collectionOrders)
        .where(_fieldRouteJourneyNumber, isEqualTo: routeJourneyNumber)
        .where(_fieldDriverUid, isEqualTo: user.uid)
        .where(_fieldStatus, isEqualTo: statusPickedUp)
        .get();

    return snapshot.docs.length;
  }

  /// Buat pesanan (permintaan penumpang ke driver).
  /// Untuk kirim_barang + receiverUid: status = pending_receiver (tunggu penerima setuju).
  /// [receiverName], [receiverPhotoUrl]: untuk kirim_barang saat link penerima.
  /// [scheduleId] + [scheduledDate]: untuk pesanan terjadwal (Pesan nanti); routeJourneyNumber dipakai 'scheduled'.
  static Future<String?> createOrder({
    required String passengerUid,
    required String driverUid,
    required String routeJourneyNumber,
    required String passengerName,
    String? passengerPhotoUrl,
    String? passengerAppLocale,
    required String originText,
    required String destText,
    double? originLat,
    double? originLng,
    double? destLat,
    double? destLng,
    String orderType = 'travel',
    String? receiverUid,
    String? receiverName,
    String? receiverPhotoUrl,
    int? jumlahKerabat,
    String? scheduleId,
    String? scheduledDate,
    String? barangCategory,
    String? barangNama,
    double? barangBeratKg,
    double? barangPanjangCm,
    double? barangLebarCm,
    double? barangTinggiCm,
    String? barangFotoUrl,
    /// Kirim barang: [OrderModel.travelFarePaidBySender] atau [OrderModel.travelFarePaidByReceiver].
    String? travelFarePaidBy,
    bool bypassDuplicatePendingKirimBarang = false,
    bool bypassDuplicatePendingTravel = false,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return null;
    if (user.uid != passengerUid) return null;

    try {
      final uDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(passengerUid)
          .get();
      final ud = uDoc.data();
      if (ud != null &&
          VerificationService.isAdminVerificationBlockingFeatures(ud)) {
        return null;
      }
    } catch (_) {}

    final isScheduled =
        (scheduleId?.isNotEmpty ?? false) &&
        (scheduledDate?.isNotEmpty ?? false);
    final effectiveRoute = isScheduled
        ? routeJourneyNumberScheduled
        : routeJourneyNumber;

    final now = FieldValue.serverTimestamp();
    final data = <String, dynamic>{
      'orderNumber': null,
      'passengerUid': passengerUid,
      'driverUid': driverUid,
      'routeJourneyNumber': effectiveRoute,
      'passengerName': passengerName,
      'passengerPhotoUrl': passengerPhotoUrl ?? '',
      if (passengerAppLocale != null && passengerAppLocale.isNotEmpty) 'passengerAppLocale': passengerAppLocale,
      'originText': originText,
      'destText': destText,
      'originLat': originLat,
      'originLng': originLng,
      'destLat': destLat,
      'destLng': destLng,
      'passengerLat': null,
      'passengerLng': null,
      'passengerLocationText': null,
      'driverAgreed': false,
      'passengerAgreed': false,
      'orderType': orderType,
      'createdAt': now,
      'updatedAt': now,
    };
    final isKirimBarangWithReceiver = orderType == OrderModel.typeKirimBarang &&
        receiverUid != null &&
        receiverUid.isNotEmpty;
    if (isKirimBarangWithReceiver) {
      data['status'] = statusPendingReceiver;
      data['receiverUid'] = receiverUid;
      if (receiverName != null) data['receiverName'] = receiverName;
      if (receiverPhotoUrl != null) data['receiverPhotoUrl'] = receiverPhotoUrl;
    } else {
      data['status'] = statusPendingAgreement;
      if (receiverUid != null) data['receiverUid'] = receiverUid;
    }
    if (jumlahKerabat != null) data['jumlahKerabat'] = jumlahKerabat;
    if (scheduleId != null) data['scheduleId'] = scheduleId;
    if (scheduledDate != null) data['scheduledDate'] = scheduledDate;
    if (barangCategory != null && barangCategory.isNotEmpty) data['barangCategory'] = barangCategory;
    if (barangNama != null && barangNama.trim().isNotEmpty) data['barangNama'] = barangNama.trim();
    if (barangBeratKg != null && barangBeratKg > 0) data['barangBeratKg'] = barangBeratKg;
    if (barangPanjangCm != null && barangPanjangCm > 0) data['barangPanjangCm'] = barangPanjangCm;
    if (barangLebarCm != null && barangLebarCm > 0) data['barangLebarCm'] = barangLebarCm;
    if (barangTinggiCm != null && barangTinggiCm > 0) data['barangTinggiCm'] = barangTinggiCm;
    if (barangFotoUrl != null && barangFotoUrl.trim().isNotEmpty) {
      data['barangFotoUrl'] = barangFotoUrl.trim();
    }
    if (orderType == OrderModel.typeKirimBarang) {
      final tf = travelFarePaidBy == OrderModel.travelFarePaidByReceiver
          ? OrderModel.travelFarePaidByReceiver
          : OrderModel.travelFarePaidBySender;
      data['travelFarePaidBy'] = tf;
    }
    if (orderType == OrderModel.typeKirimBarang &&
        originLat != null &&
        originLng != null &&
        destLat != null &&
        destLng != null) {
      try {
        final (_, fee) = await LacakBarangService.getTierAndFee(
          originLat: originLat,
          originLng: originLng,
          destLat: destLat,
          destLng: destLng,
        );
        data['lacakBarangIapFeeRupiah'] = fee;
      } catch (e, st) {
        logError('createOrder lacakBarangIapFeeRupiah', e, st);
      }
    }
    if (TrakaApiConfig.shouldCreateOrderViaApi) {
      final apiBody = Map<String, dynamic>.from(data)
        ..remove('createdAt')
        ..remove('updatedAt')
        ..['bypassDuplicatePendingKirimBarang'] =
            bypassDuplicatePendingKirimBarang
        ..['bypassDuplicatePendingTravel'] = bypassDuplicatePendingTravel;
      final r = await TrakaApiService.createPassengerOrderViaApi(apiBody);
      if (r.orderId != null) {
        return r.orderId;
      }
      if (!r.fallBackToFirestore) {
        return null;
      }
    }
    if (orderType == OrderModel.typeKirimBarang && !bypassDuplicatePendingKirimBarang) {
      final dup =
          await getPassengerPendingKirimBarangWithDriver(passengerUid, driverUid);
      if (dup != null) {
        log(
          'OrderService.createOrder: blocked duplicate pending kirim_barang (existing ${dup.id})',
        );
        return null;
      }
    }
    if (orderType == OrderModel.typeTravel && !bypassDuplicatePendingTravel) {
      final dupT =
          await getPassengerPendingTravelWithDriver(passengerUid, driverUid);
      if (dupT != null) {
        log(
          'OrderService.createOrder: blocked duplicate pending travel (existing ${dupT.id})',
        );
        return null;
      }
    }
    final ref = await FirebaseFirestore.instance
        .collection(_collectionOrders)
        .add(data);
    return ref.id;
  }

  /// Alur bayar ke driver sebelum scan barcode (Traka bukan pemegang uang).
  static Future<void> updatePassengerPayFlow({
    required String orderId,
    String? passengerPayMethod,
    String? passengerPayMethodId,
    bool setDisclaimer = false,
    bool setMarkedPaid = false,
  }) async {
    final ref =
        FirebaseFirestore.instance.collection(_collectionOrders).doc(orderId);
    final u = <String, dynamic>{
      'updatedAt': FieldValue.serverTimestamp(),
    };
    if (passengerPayMethod != null) {
      u['passengerPayMethod'] = passengerPayMethod;
    }
    if (passengerPayMethodId != null) {
      u['passengerPayMethodId'] = passengerPayMethodId;
    }
    if (setDisclaimer) {
      u['passengerPayDisclaimerAt'] = FieldValue.serverTimestamp();
    }
    if (setMarkedPaid) {
      u['passengerPayMarkedAt'] = FieldValue.serverTimestamp();
    }
    await ref.update(u);
  }

  /// Alur hybrid untuk **penerima** (ongkos ditanggung penerima, kirim barang).
  static Future<void> updateReceiverPayFlow({
    required String orderId,
    String? receiverPayMethod,
    String? receiverPayMethodId,
    bool setDisclaimer = false,
    bool setMarkedPaid = false,
  }) async {
    final ref =
        FirebaseFirestore.instance.collection(_collectionOrders).doc(orderId);
    final u = <String, dynamic>{
      'updatedAt': FieldValue.serverTimestamp(),
    };
    if (receiverPayMethod != null) {
      u['receiverPayMethod'] = receiverPayMethod;
    }
    if (receiverPayMethodId != null) {
      u['receiverPayMethodId'] = receiverPayMethodId;
    }
    if (setDisclaimer) {
      u['receiverPayDisclaimerAt'] = FieldValue.serverTimestamp();
    }
    if (setMarkedPaid) {
      u['receiverPayMarkedAt'] = FieldValue.serverTimestamp();
    }
    await ref.update(u);
  }

  /// Semua `scheduleId` pada order driver ini yang **belum** selesai/dibatalkan.
  /// Satu query (bukan N per jadwal) agar `cleanupPastSchedules` tidak menggantung/timeout.
  /// Pakai [whereIn] status aktif (bukan `whereNotIn`) agar cocok dengan indeks `driverUid`+`status`.
  ///
  /// Hasil di-cache ±[_activeScheduleIdsCacheTtl] per [driverUid] agar panggilan berdekatan tidak memicu query ganda.
  static Future<Set<String>> activeScheduleIdsForDriverOrders(String driverUid) async {
    final now = DateTime.now();
    final cached = _activeScheduleIdsCache[driverUid];
    if (cached != null) {
      final (fetchedAt, ids) = cached;
      if (now.difference(fetchedAt) < _activeScheduleIdsCacheTtl) {
        return Set<String>.from(ids);
      }
    }
    try {
      final snap = await FirebaseFirestore.instance
          .collection(_collectionOrders)
          .where(_fieldDriverUid, isEqualTo: driverUid)
          .where(_fieldStatus, whereIn: [
            statusPendingAgreement,
            statusAgreed,
            statusPickedUp,
            statusPendingReceiver,
          ])
          .get()
          .timeout(const Duration(seconds: 25));
      final out = <String>{};
      for (final doc in snap.docs) {
        final sid = doc.data()['scheduleId'] as String?;
        if (sid != null && sid.isNotEmpty) {
          out.add(sid);
        }
      }
      _activeScheduleIdsCache[driverUid] = (now, Set<String>.from(out));
      return out;
    } catch (e, st) {
      logError('OrderService.activeScheduleIdsForDriverOrders', e, st);
      rethrow;
    }
  }

  /// True jika [scheduleId]/legacy masih dipakai order aktif pada salah satu id di [activeIds].
  static bool scheduledOrderMatchesActiveIds(
    Set<String> activeIds,
    String scheduleId,
    String legacyScheduleId,
  ) {
    if (activeIds.isEmpty) return false;
    if (activeIds.contains(scheduleId) || activeIds.contains(legacyScheduleId)) {
      return true;
    }
    final legNew = ScheduleIdUtil.toLegacy(scheduleId);
    final legLeg = ScheduleIdUtil.toLegacy(legacyScheduleId);
    if (activeIds.contains(legNew)) return true;
    for (final a in activeIds) {
      final legA = ScheduleIdUtil.toLegacy(a);
      if (legA == legNew || legA == legLeg) return true;
    }
    return false;
  }

  /// True jika masih ada order (travel atau kirim barang) dengan [scheduleId] ini yang **belum**
  /// [statusCompleted] / [statusCancelled] — dipakai agar jadwal lewat tidak dihapus otomatis
  /// selama masih ada pesanan aktif.
  static Future<bool> scheduleHasActiveScheduledOrders(
    String scheduleId, {
    String? legacyScheduleId,
  }) async {
    try {
      if (await _scheduleIdHasNonTerminalOrders(scheduleId)) return true;
      if (legacyScheduleId != null &&
          legacyScheduleId.isNotEmpty &&
          legacyScheduleId != scheduleId) {
        if (await _scheduleIdHasNonTerminalOrders(legacyScheduleId)) return true;
      }
      return false;
    } catch (e, st) {
      logError('OrderService.scheduleHasActiveScheduledOrders', e, st);
      return true;
    }
  }

  static Future<bool> _scheduleIdHasNonTerminalOrders(String scheduleId) async {
    final snap = await FirebaseFirestore.instance
        .collection(_collectionOrders)
        .where('scheduleId', isEqualTo: scheduleId)
        .get()
        .timeout(const Duration(seconds: 20));
    for (final doc in snap.docs) {
      final s = doc.data()[_fieldStatus] as String?;
      if (s != statusCompleted && s != statusCancelled) {
        return true;
      }
    }
    return false;
  }

  /// Jumlah penumpang dan jumlah kirim barang yang sudah dipesan untuk jadwal ini (status agreed/picked_up).
  /// [kargoCount]: hanya barangCategory == 'kargo' (barang besar, mengurangi kapasitas). Dokumen tidak.
  /// [legacyScheduleId]: format lama (tanpa hash) untuk backward compat dengan order yang sudah ada.
  static Future<({int totalPenumpang, int kirimBarangCount, int kargoCount})>
  getScheduledBookingCounts(String scheduleId, {String? legacyScheduleId}) async {
    try {
      final ids = [
        scheduleId,
        if (legacyScheduleId != null &&
            legacyScheduleId != scheduleId &&
            legacyScheduleId.isNotEmpty)
          legacyScheduleId,
      ];
      final snapshot = ids.length == 1
          ? await FirebaseFirestore.instance
              .collection(_collectionOrders)
              .where('scheduleId', isEqualTo: scheduleId)
              .where(_fieldStatus, whereIn: [statusAgreed, statusPickedUp])
              .get()
          : await FirebaseFirestore.instance
              .collection(_collectionOrders)
              .where('scheduleId', whereIn: ids)
              .where(_fieldStatus, whereIn: [statusAgreed, statusPickedUp])
              .get();

      int totalPenumpang = 0;
      int kirimBarangCount = 0;
      int kargoCount = 0;
      for (final doc in snapshot.docs) {
        final d = doc.data();
        final orderType = (d['orderType'] as String?) ?? 'travel';
        if (orderType == OrderModel.typeKirimBarang) {
          kirimBarangCount++;
          final cat = (d['barangCategory'] as String?) ?? '';
          if (cat == OrderModel.barangCategoryKargo || cat.isEmpty) {
            kargoCount++;
          }
        } else {
          final jk = (d['jumlahKerabat'] as num?)?.toInt();
          totalPenumpang += (jk == null || jk <= 0) ? 1 : (1 + jk);
        }
      }
      return (
        totalPenumpang: totalPenumpang,
        kirimBarangCount: kirimBarangCount,
        kargoCount: kargoCount,
      );
    } catch (e, st) {
      logError('OrderService.getPassengerAndBarangCountsForRoute', e, st);
      return (totalPenumpang: 0, kirimBarangCount: 0, kargoCount: 0);
    }
  }

  /// Pindah pesanan terjadwal ke jadwal lain. Hanya driver pemilik order yang bisa.
  /// Return (success, errorMessage).
  static Future<(bool, String?)> updateOrderSchedule(
    String orderId,
    String newScheduleId,
    String newScheduledDate,
  ) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return (false, 'Anda belum login.');
    try {
      final ref = FirebaseFirestore.instance
          .collection(_collectionOrders)
          .doc(orderId);
      final doc = await ref.get();
      if (!doc.exists || doc.data() == null) {
        return (false, 'Pesanan tidak ditemukan.');
      }
      final data = doc.data()!;
      if ((data[_fieldDriverUid] as String?) != user.uid) {
        return (false, 'Anda bukan driver pesanan ini.');
      }
      if ((data['scheduleId'] as String?) == null ||
          (data['scheduleId'] as String).isEmpty) {
        return (false, 'Pesanan ini bukan pesanan terjadwal.');
      }
      if ((data[_fieldStatus] as String?) != statusAgreed &&
          (data[_fieldStatus] as String?) != statusPickedUp) {
        return (false, 'Hanya pesanan yang sudah disepakati yang bisa dipindah.');
      }
      await ref.update({
        'scheduleId': newScheduleId,
        'scheduledDate': newScheduledDate,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      return (true, null);
    } catch (e, st) {
      logError('OrderService.updateOrderSchedule', e, st);
      return (false, 'Gagal memindah: ${e.toString()}');
    }
  }

  /// Daftar OrderModel terjadwal untuk satu jadwal (agreed/picked_up).
  /// [travelOnly] true = hanya travel; [kirimBarangOnly] true = hanya kirim barang.
  /// [pickedUpOnly] true = hanya status picked_up (untuk Oper Driver).
  /// [legacyScheduleId]: sama seperti penghitungan badge — order lama bisa pakai id format lain.
  static Future<List<OrderModel>> getScheduledOrdersForSchedule(
    String scheduleId, {
    String? legacyScheduleId,
    bool? travelOnly,
    bool? kirimBarangOnly,
    bool pickedUpOnly = false,
  }) async {
    try {
      final ids = <String>[
        scheduleId,
        if (legacyScheduleId != null &&
            legacyScheduleId.isNotEmpty &&
            legacyScheduleId != scheduleId)
          legacyScheduleId,
      ];

      Query<Map<String, dynamic>> q =
          FirebaseFirestore.instance.collection(_collectionOrders);
      if (ids.length == 1) {
        q = q.where('scheduleId', isEqualTo: scheduleId);
      } else {
        q = q.where('scheduleId', whereIn: ids);
      }
      q = q.where(
        _fieldStatus,
        whereIn: pickedUpOnly
            ? [statusPickedUp]
            : [statusAgreed, statusPickedUp],
      );

      // Cache dulu: setelah tulis jadwal besar, get default mengantre lama → sheet Pemesan/Barang spinner terus.
      // Jika cache ada isi → tampilkan segera; jika kosong / miss → serverAndCache + plafon ketat.
      QuerySnapshot<Map<String, dynamic>> snap;
      try {
        snap = await q
            .get(const GetOptions(source: Source.cache))
            .timeout(const Duration(seconds: 4));
        if (snap.docs.isEmpty) {
          snap = await q
              .get(const GetOptions(source: Source.serverAndCache))
              .timeout(
                const Duration(seconds: 12),
                onTimeout: () =>
                    throw TimeoutException('getScheduledOrdersForSchedule'),
              );
        }
      } on TimeoutException {
        snap = await q
            .get(const GetOptions(source: Source.serverAndCache))
            .timeout(
              const Duration(seconds: 12),
              onTimeout: () =>
                  throw TimeoutException('getScheduledOrdersForSchedule'),
            );
      } catch (_) {
        snap = await q
            .get(const GetOptions(source: Source.serverAndCache))
            .timeout(
              const Duration(seconds: 12),
              onTimeout: () =>
                  throw TimeoutException('getScheduledOrdersForSchedule'),
            );
      }

      final list = <OrderModel>[];
      for (final doc in snap.docs) {
        final o = OrderModel.fromFirestore(doc);
        final orderType = o.orderType;
        if (travelOnly == true && orderType != OrderModel.typeTravel) continue;
        if (kirimBarangOnly == true && orderType != OrderModel.typeKirimBarang) {
          continue;
        }
        list.add(o);
      }
      return list;
    } on TimeoutException {
      return [];
    } catch (e, st) {
      logError('OrderService.getScheduledOrdersForSchedule', e, st);
      return [];
    }
  }

  /// Daftar order terjadwal dengan info penumpang (nama, foto) untuk satu jadwal.
  /// [travelOnly] true = hanya order travel; [kirimBarangOnly] true = hanya kirim barang.
  static Future<List<Map<String, dynamic>>> getScheduledOrdersWithPassengerInfo(
    String scheduleId, {
    bool? travelOnly,
    bool? kirimBarangOnly,
  }) async {
    try {
      var query = FirebaseFirestore.instance
          .collection(_collectionOrders)
          .where('scheduleId', isEqualTo: scheduleId)
          .where(_fieldStatus, whereIn: [statusAgreed, statusPickedUp]);

      final snap = await query.get();
      final list = <Map<String, dynamic>>[];
      for (final doc in snap.docs) {
        final d = doc.data();
        final orderType = (d['orderType'] as String?) ?? 'travel';
        if (travelOnly == true && orderType != OrderModel.typeTravel) continue;
        if (kirimBarangOnly == true && orderType != OrderModel.typeKirimBarang) {
          continue;
        }
        list.add({
          'orderId': doc.id,
          'passengerName': (d['passengerName'] as String?) ?? 'Penumpang',
          'passengerPhotoUrl': d['passengerPhotoUrl'] as String?,
          'passengerAppLocale': d['passengerAppLocale'] as String?,
          'orderType': orderType,
          'jumlahKerabat': (d['jumlahKerabat'] as num?)?.toInt(),
        });
      }
      return list;
    } catch (e, st) {
      logError('OrderService.getScheduledOrdersWithPassengerInfo', e, st);
      return [];
    }
  }

  /// Saring dari snapshot order driver (stream beranda) — logika sama dengan [getDriverScheduledOrdersWithAgreed]
  /// tanpa query Firestore baru (hindari antrean setelah simpan jadwal).
  static List<OrderModel> scheduledOrdersWithAgreedFromList(
    List<OrderModel> orders,
  ) {
    final list = orders
        .where(
          (o) =>
              (o.status == statusAgreed || o.status == statusPickedUp) &&
              (o.scheduleId != null && o.scheduleId!.isNotEmpty),
        )
        .toList();
    list.sort((a, b) {
      final ad = a.scheduledDate ?? '';
      final bd = b.scheduledDate ?? '';
      return ad.compareTo(bd);
    });
    return list;
  }

  /// Daftar pesanan terjadwal driver yang sudah ada kesepakatan (agreed/picked_up). Untuk pengingat "punya pesanan terjadwal".
  static Future<List<OrderModel>> getDriverScheduledOrdersWithAgreed() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return [];
    final query = FirebaseFirestore.instance
        .collection(_collectionOrders)
        .where(_fieldDriverUid, isEqualTo: user.uid)
        .where(_fieldStatus, whereIn: [statusAgreed, statusPickedUp])
        .limit(50);

    List<OrderModel> parseScheduled(QuerySnapshot<Map<String, dynamic>> snap) {
      final orders = snap.docs
          .map((d) => OrderModel.fromFirestore(d))
          .where((o) => o.scheduleId != null && o.scheduleId!.isNotEmpty)
          .toList();
      orders.sort((a, b) {
        final ad = a.scheduledDate ?? '';
        final bd = b.scheduledDate ?? '';
        return ad.compareTo(bd);
      });
      return orders;
    }

    try {
      // 1) Cache dulu — **sadar hasil apa pun** (termasuk []): tap Siap Kerja tidak perlu antre
      // serverAndCache hanya karena "kosong". Kasus tanpa pesanan agreed adalah yang paling sering;
      // setelah simpan jadwal, baca server sering mengantre lama dan snack "Memeriksa…" menggantung.
      // Window salah (order baru agreed, belum masuk cache): tap Siap Kerja lagi setelah sinkron.
      try {
        final cacheSnap = await query
            .get(const GetOptions(source: Source.cache))
            .timeout(const Duration(seconds: 2));
        return parseScheduled(cacheSnap);
      } on TimeoutException {
        // lanjut ke serverAndCache
      } catch (_) {
        // query belum pernah di-cache / miss — lanjut ke jaringan
      }

      // 2) Cache tidak tersedia: serverAndCache + plafon singkat → fail-open ke [] (buka sheet rute).
      final snap = await query
          .get(const GetOptions(source: Source.serverAndCache))
          .timeout(const Duration(seconds: 5));
      return parseScheduled(snap);
    } on TimeoutException {
      return [];
    } catch (e, st) {
      logError('OrderService.getDriverScheduledOrdersWithAgreed', e, st);
      return [];
    }
  }

  /// Stream pesanan terjadwal untuk driver (satu scheduleId). Dipakai saat driver aktif dari jadwal.
  /// [legacyScheduleId]: format lama untuk backward compat.
  static Stream<List<OrderModel>> streamOrdersForDriverBySchedule(
    String scheduleId, {
    String? legacyScheduleId,
  }) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return Stream.value([]);

    final ids = [
      scheduleId,
      if (legacyScheduleId != null &&
          legacyScheduleId != scheduleId &&
          legacyScheduleId.isNotEmpty)
        legacyScheduleId,
    ];
    final query = ids.length == 1
        ? FirebaseFirestore.instance
            .collection(_collectionOrders)
            .where('scheduleId', isEqualTo: scheduleId)
        : FirebaseFirestore.instance
            .collection(_collectionOrders)
            .where('scheduleId', whereIn: ids);

    return query
        .where(_fieldDriverUid, isEqualTo: user.uid)
        .where(
          _fieldStatus,
          whereIn: [
            statusPendingAgreement,
            statusAgreed,
            statusPickedUp,
            statusCompleted,
          ],
        )
        .snapshots()
        .map((snap) {
          final list = snap.docs
              .map((d) => OrderModel.fromFirestore(d))
              .toList();
          list.sort((a, b) {
            final at = a.createdAt ?? a.updatedAt;
            final bt = b.createdAt ?? b.updatedAt;
            if (at == null && bt == null) return 0;
            if (at == null) return 1;
            if (bt == null) return -1;
            return bt.compareTo(at);
          });
          return list;
        });
  }

  /// Driver klik kesepakatan → masukkan harga → set driverAgreed = true, agreedPrice, agreedPriceAt.
  static Future<bool> setDriverAgreedPrice(
    String orderId,
    double priceRp,
  ) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return false;
    if (priceRp < 0) return false;

    final ref = FirebaseFirestore.instance
        .collection(_collectionOrders)
        .doc(orderId);
    final doc = await ref.get();
    if (!doc.exists) return false;
    final data = doc.data();
    if (data == null || (data[_fieldDriverUid] as String?) != user.uid) {
      return false;
    }

    await ref.update({
      'driverAgreed': true,
      'agreedPrice': priceRp,
      'agreedPriceAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    return true;
  }

  /// Driver klik kesepakatan (tanpa harga, backward compat). Set driverAgreed = true.
  static Future<bool> setDriverAgreed(String orderId) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return false;

    final ref = FirebaseFirestore.instance
        .collection(_collectionOrders)
        .doc(orderId);
    final doc = await ref.get();
    if (!doc.exists) return false;
    final data = doc.data();
    if (data == null || (data[_fieldDriverUid] as String?) != user.uid) {
      return false;
    }

    await ref.update({
      'driverAgreed': true,
      'updatedAt': FieldValue.serverTimestamp(),
    });
    return true;
  }

  /// Penumpang klik kesepakatan → set passengerAgreed = true.
  /// Mengembalikan (success, driverBarcodePickupPayload?, kirimPesanChat) — payload untuk driver tunjukkan ke penumpang (scan penjemputan).
  /// [kirimPesanChat] false jika pesanan sudah dalam status agreed (idempoten / duplikat tap); jangan kirim pesan «sudah setuju» lagi.
  static Future<(bool, String?, bool)> setPassengerAgreed(
    String orderId, {
    required double passengerLat,
    required double passengerLng,
    required String passengerLocationText,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return (false, null, false);

    final ref = FirebaseFirestore.instance
        .collection(_collectionOrders)
        .doc(orderId);
    final doc = await ref.get();
    if (!doc.exists) return (false, null, false);
    final data = doc.data();
    if (data == null || (data[_fieldPassengerUid] as String?) != user.uid) {
      return (false, null, false);
    }

    final driverAgreed = (data['driverAgreed'] as bool?) ?? false;
    final passengerAgreedAlready = (data['passengerAgreed'] as bool?) ?? false;
    final currentStatus = (data[_fieldStatus] as String?) ?? '';

    if (driverAgreed &&
        passengerAgreedAlready &&
        currentStatus == statusAgreed) {
      final existingPayload =
          data['driverBarcodePickupPayload'] as String?;
      return (true, existingPayload, false);
    }
    final orderType = (data['orderType'] as String?) ?? OrderModel.typeTravel;
    final now = FieldValue.serverTimestamp();
    bool willBecomeAgreed = false;
    String? barcodePayload;

    if (driverAgreed) {
      final orderNumber = await OrderNumberService.generateOrderNumber();
      // Barcode PICKUP: penumpang scan saat penjemputan (driver tunjukkan ke penumpang)
      barcodePayload = 'TRAKA:$orderId:D:PICKUP:${const Uuid().v4()}';
      await ref.update({
        'passengerAgreed': true,
        'orderNumber': orderNumber,
        'passengerLat': passengerLat,
        'passengerLng': passengerLng,
        'passengerLocationText': passengerLocationText,
        'status': statusAgreed,
        'driverBarcodePickupPayload': barcodePayload,
        'updatedAt': now,
      });
      willBecomeAgreed = true;
    } else {
      await ref.update({'passengerAgreed': true, 'updatedAt': now});
    }

    // Jika status menjadi agreed, hapus semua order lain dari jenis yang sama yang belum agreed
    if (willBecomeAgreed) {
      _deleteOtherOrders(user.uid, orderId, orderType)
          .then((deletedCount) {
            log(
              'OrderService.setPassengerAgreed: Menghapus $deletedCount order $orderType lain untuk penumpang ${user.uid}',
            );
          })
          .catchError((e) {
            log('OrderService.setPassengerAgreed: Error menghapus order lain', e);
          });
    }

    return (true, willBecomeAgreed ? barcodePayload : null, true);
  }

  /// Penumpang membatalkan kesepakatan → reset ke pending_agreement agar driver bisa kirim kesepakatan baru.
  /// Dipanggil saat penumpang tap Batal di dialog kesepakatan dan konfirmasi "Ya".
  static Future<bool> resetAgreementByPassenger(String orderId) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return false;

    final ref = FirebaseFirestore.instance
        .collection(_collectionOrders)
        .doc(orderId);
    final doc = await ref.get();
    if (!doc.exists || doc.data() == null) return false;
    final data = doc.data()!;
    if ((data[_fieldPassengerUid] as String?) != user.uid) return false;

    await ref.update({
      'driverAgreed': false,
      'passengerAgreed': false,
      'agreedPrice': FieldValue.delete(),
      'agreedPriceAt': FieldValue.delete(),
      'orderNumber': FieldValue.delete(),
      'driverBarcodePickupPayload': FieldValue.delete(),
      'status': statusPendingAgreement,
      'updatedAt': FieldValue.serverTimestamp(),
    });
    return true;
  }

  /// Update lokasi penumpang di order (cadangan jika live tidak ada: chat ~30 dtk, ≥50 m).
  /// Travel: saat **agreed** (belum dijemput) **atau** **picked_up** (perjalanan) — bukan setelah selesai.
  static Future<bool> updatePassengerLocation(
    String orderId, {
    required double passengerLat,
    required double passengerLng,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return false;

    try {
      final ref = FirebaseFirestore.instance
          .collection(_collectionOrders)
          .doc(orderId);
      final doc = await ref.get();
      if (!doc.exists) return false;
      final data = doc.data();
      if (data == null || (data[_fieldPassengerUid] as String?) != user.uid) {
        return false;
      }
      final status = data[_fieldStatus] as String?;
      final pickedUp = data['driverScannedAt'] != null || data['passengerScannedPickupAt'] != null;
      final orderType = (data['orderType'] as String?) ?? OrderModel.typeTravel;
      final allowPrePickup = status == statusAgreed && !pickedUp;
      final allowInTrip =
          status == statusPickedUp && orderType == OrderModel.typeTravel;
      if (!allowPrePickup && !allowInTrip) return false;

      await ref.update({
        'passengerLat': passengerLat,
        'passengerLng': passengerLng,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      return true;
    } catch (e, st) {
      logError('OrderService.updatePassengerLocation', e, st);
      return false;
    }
  }

  /// Set driver sedang navigasi ke penumpang (klik "Ya, arahkan"). Penumpang akan stream lokasi live.
  static Future<bool> setDriverNavigatingToPickup(String orderId) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return false;
    try {
      final ref = FirebaseFirestore.instance
          .collection(_collectionOrders)
          .doc(orderId);
      final doc = await ref.get();
      if (!doc.exists) return false;
      final data = doc.data();
      if (data == null || (data[_fieldDriverUid] as String?) != user.uid) {
        return false;
      }
      await ref.update({
        'driverNavigatingToPickupAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      return true;
    } catch (e, st) {
      logError('OrderService.setDriverNavigatingToPickup', e, st);
      return false;
    }
  }

  /// Clear driver navigasi ke penumpang (driver klik Kembali atau penumpang sudah dijemput).
  static Future<bool> clearDriverNavigatingToPickup(String orderId) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return false;
    try {
      final ref = FirebaseFirestore.instance
          .collection(_collectionOrders)
          .doc(orderId);
      final doc = await ref.get();
      if (!doc.exists) return false;
      final data = doc.data();
      if (data == null || (data[_fieldDriverUid] as String?) != user.uid) {
        return false;
      }
      await ref.update({
        'driverNavigatingToPickupAt': FieldValue.delete(),
        'passengerLiveLat': FieldValue.delete(),
        'passengerLiveLng': FieldValue.delete(),
        'passengerLiveUpdatedAt': FieldValue.delete(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      return true;
    } catch (e, st) {
      logError('OrderService.clearDriverNavigatingToPickup', e, st);
      return false;
    }
  }

  /// Update lokasi penumpang live (saat driver navigate). Hanya jika driverNavigatingToPickupAt set.
  static Future<bool> updatePassengerLiveLocation(
    String orderId, {
    required double lat,
    required double lng,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return false;
    try {
      final ref = FirebaseFirestore.instance
          .collection(_collectionOrders)
          .doc(orderId);
      final doc = await ref.get();
      if (!doc.exists) return false;
      final data = doc.data();
      if (data == null || (data[_fieldPassengerUid] as String?) != user.uid) {
        return false;
      }
      if (data['driverNavigatingToPickupAt'] == null) return false;
      final pickedUp = data['driverScannedAt'] != null ||
          data['passengerScannedPickupAt'] != null;
      if (pickedUp) return false;

      await ref.update({
        'passengerLiveLat': lat,
        'passengerLiveLng': lng,
        'passengerLiveUpdatedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      return true;
    } catch (e, st) {
      logError('OrderService.updatePassengerLiveLocation', e, st);
      return false;
    }
  }

  /// Hapus semua order lain dari jenis yang sama yang belum agreed untuk penumpang yang sama.
  /// Dipanggil ketika penumpang setuju kesepakatan dengan satu driver.
  /// Juga menghapus semua chat messages dan file media dari Storage.
  static Future<int> _deleteOtherOrders(
    String passengerUid,
    String excludeOrderId,
    String orderType,
  ) async {
    try {
      // Ambil semua order dari jenis yang sama yang belum agreed
      final snapshot = await FirebaseFirestore.instance
          .collection(_collectionOrders)
          .where(_fieldPassengerUid, isEqualTo: passengerUid)
          .where('orderType', isEqualTo: orderType)
          .where(_fieldStatus, isEqualTo: statusPendingAgreement)
          .get();

      int deletedCount = 0;
      final batch = FirebaseFirestore.instance.batch();
      final deleteStoragePromises = <Future<void>>[];

      for (final doc in snapshot.docs) {
        // Skip order yang sedang disetujui
        if (doc.id == excludeOrderId) continue;

        // Ambil semua chat messages untuk menghapus file media
        final messagesSnap = await doc.reference.collection('messages').get();
        for (final msgDoc in messagesSnap.docs) {
          final msgData = msgDoc.data();
          final msgType = msgData['type'] as String?;

          // Hapus file audio dari Storage
          if (msgType == 'audio') {
            final audioUrl = msgData['audioUrl'] as String?;
            if (audioUrl != null && audioUrl.isNotEmpty) {
              try {
                final uri = Uri.parse(audioUrl);
                final path = uri.path.split('/o/')[1].split('?')[0];
                final decodedPath = Uri.decodeComponent(path);
                deleteStoragePromises.add(
                  FirebaseStorage.instance.ref(decodedPath).delete().catchError((
                    e,
                  ) {
                    log('OrderService._deleteOtherOrders: Gagal hapus audio', e);
                  }),
                );
              } catch (e) {
                log('OrderService._deleteOtherOrders: Error parsing audio URL', e);
              }
            }
          }

          // Hapus file image/video dari Storage
          if (msgType == 'image' || msgType == 'video') {
            final mediaUrl = msgData['mediaUrl'] as String?;
            if (mediaUrl != null && mediaUrl.isNotEmpty) {
              try {
                final uri = Uri.parse(mediaUrl);
                final path = uri.path.split('/o/')[1].split('?')[0];
                final decodedPath = Uri.decodeComponent(path);
                deleteStoragePromises.add(
                  FirebaseStorage.instance.ref(decodedPath).delete().catchError((
                    e,
                  ) {
                    log('OrderService._deleteOtherOrders: Gagal hapus media', e);
                  }),
                );
              } catch (e) {
                log('OrderService._deleteOtherOrders: Error parsing media URL', e);
              }
            }
          }

          // Hapus message document
          batch.delete(msgDoc.reference);
        }

        // Hapus order document
        batch.delete(doc.reference);
        deletedCount++;
      }

      // Commit batch delete untuk Firestore
      if (deletedCount > 0) {
        await batch.commit();
      }

      // Tunggu semua delete Storage selesai (tidak blocking jika ada error)
      await Future.wait(deleteStoragePromises);

      return deletedCount;
    } catch (e) {
      log('OrderService._deleteOtherOrders error', e);
      return 0;
    }
  }

  /// Ambil routeJourneyNumber dari salah satu order aktif driver (agreed/picked_up).
  /// Hanya pakai filter driverUid agar tidak butuh composite index (berguna setelah ganti Firebase project).
  static Future<String?> getRouteJourneyNumberFromDriverActiveOrders() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return null;

    final snap = await FirebaseFirestore.instance
        .collection(_collectionOrders)
        .where(_fieldDriverUid, isEqualTo: user.uid)
        .limit(50)
        .get();

    for (final doc in snap.docs) {
      final data = doc.data();
      final status = data[_fieldStatus] as String?;
      if (status != statusAgreed && status != statusPickedUp) continue;
      final journey = data[_fieldRouteJourneyNumber] as String?;
      if (journey != null && journey.isNotEmpty) return journey;
    }
    return null;
  }

  /// Stream pesanan untuk driver (rute tertentu): pending_agreement + agreed.
  static Stream<List<OrderModel>> streamOrdersForDriverByRoute(
    String routeJourneyNumber,
  ) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return Stream.value([]);

    return FirebaseFirestore.instance
        .collection(_collectionOrders)
        .where(_fieldRouteJourneyNumber, isEqualTo: routeJourneyNumber)
        .where(_fieldDriverUid, isEqualTo: user.uid)
        .where(
          _fieldStatus,
          whereIn: [
            statusPendingAgreement,
            statusAgreed,
            statusPickedUp,
            statusCompleted,
          ],
        )
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map(
          (snap) => snap.docs.map((d) => OrderModel.fromFirestore(d)).toList(),
        );
  }

  /// Daftar pesanan status agreed untuk driver saat ini (untuk cek auto-konfirmasi dijemput).
  static Future<List<OrderModel>> getAgreedOrdersForDriver() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return [];

    final snap = await FirebaseFirestore.instance
        .collection(_collectionOrders)
        .where(_fieldDriverUid, isEqualTo: user.uid)
        .where(_fieldStatus, isEqualTo: statusAgreed)
        .limit(50)
        .get();

    return snap.docs.map((d) => OrderModel.fromFirestore(d)).toList();
  }

  /// Daftar pesanan status picked_up (travel) untuk driver (untuk cek auto-complete saat menjauh).
  static Future<List<OrderModel>> getPickedUpTravelOrdersForDriver() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return [];

    final snap = await FirebaseFirestore.instance
        .collection(_collectionOrders)
        .where(_fieldDriverUid, isEqualTo: user.uid)
        .where(_fieldStatus, isEqualTo: statusPickedUp)
        .where('orderType', isEqualTo: OrderModel.typeTravel)
        .limit(50)
        .get();

    return snap.docs.map((d) => OrderModel.fromFirestore(d)).toList();
  }

  /// Daftar pesanan status picked_up (travel) untuk penumpang (untuk cek auto-complete saat menjauh).
  static Future<List<OrderModel>> getPickedUpTravelOrdersForPassenger() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return [];

    final snap = await FirebaseFirestore.instance
        .collection(_collectionOrders)
        .where(_fieldPassengerUid, isEqualTo: user.uid)
        .where(_fieldStatus, isEqualTo: statusPickedUp)
        .where('orderType', isEqualTo: OrderModel.typeTravel)
        .limit(50)
        .get();

    return snap.docs.map((d) => OrderModel.fromFirestore(d)).toList();
  }

  /// Semua pesanan completed untuk driver (untuk fallback riwayat lama tanpa sesi rute).
  static Future<List<OrderModel>> getAllCompletedOrdersForDriver() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return [];

    final snap = await FirebaseFirestore.instance
        .collection(_collectionOrders)
        .where(_fieldDriverUid, isEqualTo: user.uid)
        .where(_fieldStatus, isEqualTo: statusCompleted)
        .get();

    final orders = snap.docs.map((d) => OrderModel.fromFirestore(d)).toList();
    orders.sort((a, b) {
      final at = a.completedAt ?? a.updatedAt ?? a.createdAt;
      final bt = b.completedAt ?? b.updatedAt ?? b.createdAt;
      if (at == null && bt == null) return 0;
      if (at == null) return 1;
      if (bt == null) return -1;
      return bt.compareTo(at);
    });
    return orders;
  }

  /// Daftar pesanan completed untuk satu rute (Riwayat → tap rute).
  /// Untuk rute terjadwal: [scheduleId] wajib agar penumpang per jadwal tampil.
  /// [legacyScheduleId]: format lama untuk backward compat.
  static Future<List<OrderModel>> getCompletedOrdersForRoute(
    String routeJourneyNumber, {
    String? scheduleId,
    String? legacyScheduleId,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return [];

    var query = FirebaseFirestore.instance
        .collection(_collectionOrders)
        .where(_fieldDriverUid, isEqualTo: user.uid)
        .where(_fieldStatus, isEqualTo: statusCompleted);

    if (routeJourneyNumber == routeJourneyNumberScheduled &&
        scheduleId != null &&
        scheduleId.isNotEmpty) {
      final ids = [
        scheduleId,
        if (legacyScheduleId != null &&
            legacyScheduleId != scheduleId &&
            legacyScheduleId.isNotEmpty)
          legacyScheduleId,
      ];
      query = ids.length == 1
          ? query
              .where(_fieldRouteJourneyNumber,
                  isEqualTo: routeJourneyNumberScheduled)
              .where('scheduleId', isEqualTo: scheduleId)
          : query
              .where(_fieldRouteJourneyNumber,
                  isEqualTo: routeJourneyNumberScheduled)
              .where('scheduleId', whereIn: ids);
    } else if (routeJourneyNumber.isNotEmpty) {
      query = query.where(
        _fieldRouteJourneyNumber,
        isEqualTo: routeJourneyNumber,
      );
    }

    final snap = await query.get();

    final orders = snap.docs.map((d) => OrderModel.fromFirestore(d)).toList();
    orders.sort((a, b) {
      final at = a.completedAt ?? a.updatedAt ?? a.createdAt;
      final bt = b.completedAt ?? b.updatedAt ?? b.createdAt;
      if (at == null && bt == null) return 0;
      if (at == null) return 1;
      if (bt == null) return -1;
      return bt.compareTo(at);
    });
    return orders;
  }

  /// Total kontribusi dari daftar orders (untuk tampilan Riwayat Rute).
  /// Pakai getTripTravelContributionForDisplay untuk order lama yang tripTravelContributionRupiah = 0.
  static Future<int> getTotalContributionRupiahForOrdersDisplay(
    List<OrderModel> orders,
  ) async {
    int totalTravel = 0;
    int totalBarang = 0;
    for (final o in orders) {
      if (o.orderType == OrderModel.typeTravel) {
        final c = await getTripTravelContributionForDisplay(o);
        totalTravel += (c ?? 0);
      } else if (o.orderType == OrderModel.typeKirimBarang) {
        totalBarang += (o.tripBarangFareRupiah ?? 0).round();
      }
    }
    final maxTravel = await AppConfigService.getMaxKontribusiTravelPerRuteRupiah();
    final cappedTravel = maxTravel != null && totalTravel > maxTravel
        ? maxTravel
        : totalTravel;
    return cappedTravel + totalBarang;
  }

  /// Total kontribusi (travel + barang) dari orders completed dalam satu rute.
  /// Dipakai saat simpan route_session untuk trigger bayar per rute.
  /// Travel dibatasi maxKontribusiTravelPerRuteRupiah agar tidak memberatkan driver.
  static Future<int> getTotalContributionRupiahForRoute(
    String routeJourneyNumber, {
    String? scheduleId,
  }) async {
    final orders = await getCompletedOrdersForRoute(
      routeJourneyNumber,
      scheduleId: scheduleId,
      legacyScheduleId:
          scheduleId != null ? ScheduleIdUtil.toLegacy(scheduleId) : null,
    );
    int totalTravel = 0;
    int totalBarang = 0;
    for (final o in orders) {
      if (o.orderType == OrderModel.typeTravel) {
        totalTravel += (o.tripTravelContributionRupiah ?? 0).round();
      } else if (o.orderType == OrderModel.typeKirimBarang) {
        totalBarang += (o.tripBarangFareRupiah ?? 0).round();
      }
    }
    final maxTravel = await AppConfigService.getMaxKontribusiTravelPerRuteRupiah();
    final cappedTravel = maxTravel != null && totalTravel > maxTravel
        ? maxTravel
        : totalTravel;
    return cappedTravel + totalBarang;
  }

  /// Stream pesanan completed untuk driver (Riwayat Rute).
  /// TIDAK filter chatHiddenByDriver agar riwayat tetap tampil walau chat disembunyikan/dihapus.
  static Stream<List<OrderModel>> streamCompletedOrdersForDriver() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return Stream.value([]);

    return FirebaseFirestore.instance
        .collection(_collectionOrders)
        .where(_fieldDriverUid, isEqualTo: user.uid)
        .where(_fieldStatus, isEqualTo: statusCompleted)
        .snapshots()
        .map((snap) {
          final orders =
              snap.docs.map((d) => OrderModel.fromFirestore(d)).toList();
          orders.sort((a, b) {
            final at = a.completedAt ?? a.updatedAt ?? a.createdAt;
            final bt = b.completedAt ?? b.updatedAt ?? b.createdAt;
            if (at == null && bt == null) return 0;
            if (at == null) return 1;
            if (bt == null) return -1;
            return bt.compareTo(at);
          });
          return orders;
        });
  }

  /// Batas order untuk stream (optimasi: hindari load seluruh riwayat).
  static const int streamOrdersLimit = 50;

  /// Stream pesanan untuk penumpang (milik saya).
  /// [includeHidden] true = untuk Data Order/Riwayat (tampilkan semua termasuk yang disembunyikan).
  /// false = untuk list Pesan (exclude chatHiddenByPassenger).
  /// Dibatasi 50 order terakhir.
  static Stream<List<OrderModel>> streamOrdersForPassenger(
      {bool includeHidden = false}) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return Stream.value([]);

    return FirebaseFirestore.instance
        .collection(_collectionOrders)
        .where(_fieldPassengerUid, isEqualTo: user.uid)
        .orderBy('updatedAt', descending: true)
        .limit(streamOrdersLimit)
        .snapshots()
        .map((snap) {
          try {
            var orders = snap.docs.map((d) => OrderModel.fromFirestore(d));
            if (!includeHidden) {
              orders = orders.where((o) => !o.chatHiddenByPassenger);
            }
            final list = orders.toList();
            list.sort((a, b) {
              final aTime = a.updatedAt ?? a.createdAt;
              final bTime = b.updatedAt ?? b.createdAt;
              if (aTime == null && bTime == null) return 0;
              if (aTime == null) return 1;
              if (bTime == null) return -1;
              return bTime.compareTo(aTime);
            });
            return list;
          } catch (e, st) {
            logError('OrderService.streamOrdersForPassenger', e, st);
            return <OrderModel>[];
          }
        });
  }

  /// Ambil satu pesanan by ID.
  static Future<OrderModel?> getOrderById(String orderId) async {
    final doc = await FirebaseFirestore.instance
        .collection(_collectionOrders)
        .doc(orderId)
        .get();
    if (!doc.exists || doc.data() == null) return null;
    return OrderModel.fromFirestore(doc);
  }

  /// Stream satu pesanan by ID (untuk update real-time, misal setelah penumpang batalkan kesepakatan).
  static Stream<OrderModel?> streamOrderById(String orderId) {
    return FirebaseFirestore.instance
        .collection(_collectionOrders)
        .doc(orderId)
        .snapshots()
        .map((doc) {
      if (!doc.exists || doc.data() == null) return null;
      return OrderModel.fromFirestore(doc);
    });
  }

  /// Set flag cancellation untuk driver atau penumpang.
  /// Jika kedua pihak sudah klik batalkan, maka status menjadi cancelled.
  static Future<bool> setCancellationFlag(String orderId, bool isDriver) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return false;

    final ref = FirebaseFirestore.instance
        .collection(_collectionOrders)
        .doc(orderId);
    final doc = await ref.get();
    if (!doc.exists || doc.data() == null) return false;
    final data = doc.data()!;
    final passengerUid = data[_fieldPassengerUid] as String?;
    final driverUid = data[_fieldDriverUid] as String?;

    // Verifikasi user adalah driver atau penumpang dari order ini
    if (isDriver && driverUid != user.uid) return false;
    if (!isDriver && passengerUid != user.uid) return false;

    final currentDriverCancelled = (data['driverCancelled'] as bool?) ?? false;
    final currentPassengerCancelled =
        (data['passengerCancelled'] as bool?) ?? false;

    // Set flag cancellation
    final updateData = <String, dynamic>{
      'updatedAt': FieldValue.serverTimestamp(),
    };

    if (isDriver) {
      updateData['driverCancelled'] = true;
    } else {
      updateData['passengerCancelled'] = true;
    }

    // Jika kedua pihak sudah klik batalkan, set status menjadi cancelled
    final willBeBothCancelled =
        (isDriver && currentPassengerCancelled) ||
        (!isDriver && currentDriverCancelled);

    if (willBeBothCancelled) {
      updateData['status'] = statusCancelled;

      // Hapus semua chat messages ketika order dibatalkan dan dikonfirmasi
      // Jalankan di background (tidak blocking)
      ChatService.deleteAllMessages(orderId)
          .then((success) {
            if (success) {
              log('OrderService.setCancellationFlag: Chat messages dihapus untuk order $orderId');
            } else {
              log('OrderService.setCancellationFlag: Gagal menghapus chat messages untuk order $orderId');
            }
          })
          .catchError((e) {
            log('OrderService.setCancellationFlag: Error menghapus chat', e);
          });
    }

    await ref.update(updateData);
    return true;
  }

  /// Sembunyikan chat dari list Pesan (order tetap ada untuk riwayat).
  /// Tandai pesan belum terbaca sebagai sudah terbaca.
  /// Hanya untuk order yang sudah agreed/picked_up/completed.
  static Future<String?> hideChatForPassenger(String orderId) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return 'Anda belum login.';
    final ref = FirebaseFirestore.instance
        .collection(_collectionOrders)
        .doc(orderId);
    final doc = await ref.get();
    if (!doc.exists || doc.data() == null) return 'Pesanan tidak ditemukan.';
    final data = doc.data()!;
    if ((data[_fieldPassengerUid] as String?) != user.uid) {
      return 'Anda bukan penumpang pesanan ini.';
    }
    await ref.update({
      'chatHiddenByPassenger': true,
      'passengerLastReadAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    return null;
  }

  /// Sembunyikan chat dari list Pesan oleh penerima (kirim barang).
  static Future<String?> hideChatForReceiver(String orderId) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return 'Anda belum login.';
    final ref = FirebaseFirestore.instance
        .collection(_collectionOrders)
        .doc(orderId);
    final doc = await ref.get();
    if (!doc.exists || doc.data() == null) return 'Pesanan tidak ditemukan.';
    final data = doc.data()!;
    if ((data['receiverUid'] as String?) != user.uid) {
      return 'Anda bukan penerima pesanan ini.';
    }
    await ref.update({
      'chatHiddenByReceiver': true,
      'receiverLastReadAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    return null;
  }

  /// Sembunyikan chat dari list Pesan (order tetap ada untuk riwayat).
  /// Tandai pesan belum terbaca sebagai sudah terbaca.
  static Future<String?> hideChatForDriver(String orderId) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return 'Anda belum login.';
    final ref = FirebaseFirestore.instance
        .collection(_collectionOrders)
        .doc(orderId);
    final doc = await ref.get();
    if (!doc.exists || doc.data() == null) return 'Pesanan tidak ditemukan.';
    final data = doc.data()!;
    if ((data[_fieldDriverUid] as String?) != user.uid) {
      return 'Anda bukan driver pesanan ini.';
    }
    await ref.update({
      'chatHiddenByDriver': true,
      'driverLastReadAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    return null;
  }

  /// Hapus order beserta seluruh isi chat (messages + media). Dipanggil saat user hapus manual dari list Pesan.
  /// Diperbolehkan: pending_agreement, cancelled (pembatasan pesanan).
  /// Order agreed/picked_up/completed tidak boleh dihapus; gunakan Sembunyikan.
  /// Mengembalikan null jika sukses; String pesan error jika gagal.
  static Future<String?> deleteOrderAndChat(String orderId) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return 'Anda belum login.';
    if (orderId.isEmpty) return 'ID pesanan tidak valid.';

    final ref = FirebaseFirestore.instance
        .collection(_collectionOrders)
        .doc(orderId);
    DocumentSnapshot doc;
    try {
      doc = await ref.get();
    } catch (e) {
      log('OrderService.deleteOrderAndChat get error', e);
      return 'Gagal mengakses data. Cek koneksi internet.';
    }
    if (!doc.exists || doc.data() == null) return 'Pesanan tidak ditemukan.';
    final data = doc.data()! as Map<String, dynamic>;
    final driverUid = data[_fieldDriverUid] as String?;
    final passengerUid = data[_fieldPassengerUid] as String?;
    final status = data[_fieldStatus] as String? ?? '';
    if (driverUid != user.uid && passengerUid != user.uid) {
      return 'Anda bukan driver/penumpang pesanan ini.';
    }
    // Order yang sudah kesepakatan/selesai tidak boleh dihapus
    if (status == statusAgreed ||
        status == statusPickedUp ||
        status == statusCompleted) {
      return 'Pesanan yang sudah terjadi kesepakatan tidak bisa dihapus. Gunakan Sembunyikan untuk menyembunyikan dari daftar.';
    }

    // Penumpang: travel pending dengan driver lain tidak boleh dihapus jika sudah ada travel agreed dengan driver lain
    final orderType = (data['orderType'] as String?) ?? OrderModel.typeTravel;
    if (passengerUid == user.uid &&
        orderType == OrderModel.typeTravel &&
        status == statusPendingAgreement &&
        driverUid != null) {
      final agreedDrivers = await getTravelAgreedDriverUidsForPassenger(user.uid);
      if (agreedDrivers.isNotEmpty && !agreedDrivers.contains(driverUid)) {
        return 'Ada pesanan travel dengan kesepakatan harga. Chat travel dengan driver lain tidak bisa dihapus. Selesaikan atau batalkan di tab Pesanan.';
      }
    }

    // Hapus isi chat dulu (boleh gagal; kalau kosong tidak apa-apa)
    try {
      await ChatService.deleteAllMessages(orderId);
    } catch (e) {
      log('OrderService.deleteOrderAndChat deleteAllMessages', e);
    }
    // Selalu hapus dokumen order agar item hilang dari list (driver & penumpang)
    try {
      await ref.delete();
      return null;
    } on FirebaseException catch (e) {
      log('OrderService.deleteOrderAndChat FirebaseException: ${e.code} ${e.message}');
      if (e.code == 'permission-denied') {
        return 'Izin ditolak. Pastikan Rules Firestore sudah di-publish (izin hapus untuk driver/penumpang).';
      }
      return e.message ?? 'Gagal menghapus (${e.code}).';
    } catch (e) {
      log('OrderService.deleteOrderAndChat error', e);
      return 'Gagal menghapus: $e';
    }
  }

  /// Konfirmasi pembatalan (jika lawan sudah klik batalkan, konfirmasi = benar-benar cancel).
  static Future<bool> confirmCancellation(String orderId, bool isDriver) async {
    // Sama dengan setCancellationFlag, karena jika lawan sudah klik, maka ini akan trigger cancelled
    return await setCancellationFlag(orderId, isDriver);
  }

  /// Batalkan pesanan (penumpang atau driver). Delegate ke setCancellationFlag.
  /// [Deprecated] Gunakan setCancellationFlag(orderId, isDriver) langsung.
  static Future<bool> cancelOrder(String orderId) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return false;
    final ref = FirebaseFirestore.instance
        .collection(_collectionOrders)
        .doc(orderId);
    final doc = await ref.get();
    if (!doc.exists || doc.data() == null) return false;
    final data = doc.data()!;
    final driverUid = data[_fieldDriverUid] as String?;
    final isDriver = driverUid == user.uid;
    return setCancellationFlag(orderId, isDriver);
  }

  /// Validasi payload barcode penumpang: TRAKA:orderId:P:*
  /// Return (orderId atau null, pesan error).
  static (String?, String?) parsePassengerBarcodePayload(String raw) {
    final parts = raw.trim().split(':');
    if (parts.length < 4) return (null, 'Format barcode tidak valid.');
    if (parts[0] != 'TRAKA' || parts[2] != 'P') {
      return (null, 'Barcode bukan barcode penumpang Traka.');
    }
    return (parts[1], null);
  }

  /// Driver scan barcode penumpang: validasi payload TRAKA:orderId:P:*, pastikan order milik driver,
  /// dan driver dalam radius [radiusDekatMeter] dari lokasi penumpang (titik jemput). Lalu set driverScannedAt, pickupLat/pickupLng, status picked_up.
  /// Return (success, errorMessage, driverBarcodePayload). Jika sukses, driverPayload dipakai untuk kirim ke chat.
  static Future<(bool, String?, String?)> applyDriverScanPassenger(
    String rawPayload, {
    double? pickupLat,
    double? pickupLng,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return (false, 'Anda belum login.', null);

    final (orderId, parseError) = parsePassengerBarcodePayload(rawPayload);
    if (orderId == null) {
      return (false, parseError ?? 'Payload tidak valid.', null);
    }

    final ref = FirebaseFirestore.instance
        .collection(_collectionOrders)
        .doc(orderId);
    final doc = await ref.get();
    if (!doc.exists || doc.data() == null) {
      return (false, 'Pesanan tidak ditemukan.', null);
    }
    final data = doc.data()!;
    if ((data[_fieldDriverUid] as String?) != user.uid) {
      return (false, 'Barcode ini bukan untuk pesanan Anda.', null);
    }
    if ((data[_fieldStatus] as String?) == statusPickedUp) {
      return (false, 'Penumpang sudah di-scan sebelumnya.', null);
    }
    if ((data[_fieldStatus] as String?) != statusAgreed) {
      return (false, 'Status pesanan tidak sesuai.', null);
    }

    final orderType = (data['orderType'] as String?) ?? OrderModel.typeTravel;
    final isKirimBarang = orderType == OrderModel.typeKirimBarang;

    if (!isKirimBarang) {
      // Travel: tidak ada batasan titik lokasi. Yang penting HP driver dan penumpang saling dekat (dapat scan = berdekatan).
      // Cukup pastikan lokasi driver tersedia untuk catatan perjalanan.
      if (pickupLat == null || pickupLng == null) {
        return (
          false,
          'Lokasi Anda tidak terdeteksi. Pastikan GPS aktif lalu coba lagi.',
          null,
        );
      }
    } else {
      // Kirim barang: tidak wajib pada titik lokasi; yang penting scan barcode. Cukup pastikan lokasi driver tersedia untuk catatan.
      if (pickupLat == null || pickupLng == null) {
        return (
          false,
          'Lokasi Anda tidak terdeteksi. Pastikan GPS aktif lalu coba lagi.',
          null,
        );
      }
    }

    final driverPayload = 'TRAKA:$orderId:D:COMPLETE:${const Uuid().v4()}';
    try {
      await FirebaseFirestore.instance.runTransaction((tx) async {
        final doc = await tx.get(ref);
        if (!doc.exists || doc.data() == null) throw Exception('Pesanan tidak ditemukan');
        final d = doc.data()!;
        if ((d[_fieldStatus] as String?) == statusPickedUp) throw Exception('Penumpang sudah di-scan sebelumnya');
        if ((d[_fieldStatus] as String?) != statusAgreed) throw Exception('Status pesanan tidak sesuai');
        tx.update(ref, {
          'driverScannedAt': FieldValue.serverTimestamp(),
          'driverBarcodePayload': driverPayload,
          'pickupLat': pickupLat,
          'pickupLng': pickupLng,
          'status': statusPickedUp,
          'updatedAt': FieldValue.serverTimestamp(),
        });
      });
      return (true, null, driverPayload);
    } on FirebaseException catch (e) {
      logError('OrderService.applyDriverScanPassenger', e);
      return (false, 'Gagal konfirmasi: ${e.message ?? e.code}', null);
    } catch (e, st) {
      logError('OrderService.applyDriverScanPassenger', e, st);
      return (false, 'Gagal konfirmasi. Coba lagi.', null);
    }
  }

  /// Driver berhasil scan barcode penumpang (jarak ≤ 500 m). Status → picked_up.
  static Future<bool> setPickedUp(String orderId) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return false;

    final ref = FirebaseFirestore.instance
        .collection(_collectionOrders)
        .doc(orderId);
    final doc = await ref.get();
    if (!doc.exists || doc.data() == null) return false;
    final data = doc.data()!;
    if ((data[_fieldDriverUid] as String?) != user.uid) return false;

    await ref.update({
      'status': statusPickedUp,
      'updatedAt': FieldValue.serverTimestamp(),
    });
    return true;
  }

  /// Validasi payload barcode driver: TRAKA:orderId:D:* atau TRAKA:orderId:D:FASE:uuid.
  /// Return (orderId, fase atau null, pesan error). Fase: 'PICKUP' | 'COMPLETE'. Format lama (4 bagian) = COMPLETE.
  static (String?, String?, String?) parseDriverBarcodePayloadWithPhase(String raw) {
    final parts = raw.trim().split(':');
    if (parts.length < 4) return (null, null, 'Format barcode tidak valid.');
    if (parts[0] != 'TRAKA' || parts[2] != 'D') {
      return (null, null, 'Barcode bukan barcode driver Traka.');
    }
    if (parts.length >= 5) {
      final fase = parts[3];
      if (fase != 'PICKUP' && fase != 'COMPLETE') {
        return (null, null, 'Fase barcode tidak valid.');
      }
      return (parts[1], fase, null);
    }
    // Format lama: TRAKA:orderId:D:uuid (4 bagian) = COMPLETE
    return (parts[1], 'COMPLETE', null);
  }

  /// Validasi payload barcode driver (tanpa fase). Return (orderId atau null, pesan error).
  static (String?, String?) parseDriverBarcodePayload(String raw) {
    final (orderId, _, err) = parseDriverBarcodePayloadWithPhase(raw);
    return (orderId, err);
  }

  /// Tarif per km (Rupiah). Dibaca dari Firestore app_config/settings; default 70, rentang 70–85.
  static const int _defaultTarifPerKm = 70;
  static const int _minTarifPerKm = 70;
  static const int _maxTarifPerKm = 85;

  static Future<int> _getTarifPerKm() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('app_config')
          .doc('settings')
          .get();
      final v = doc.data()?['tarifPerKm'];
      if (v != null) {
        final n = (v is num) ? v.toInt() : int.tryParse(v.toString());
        if (n != null && n > 0) {
          if (n < _minTarifPerKm) return _minTarifPerKm;
          if (n > _maxTarifPerKm) return _maxTarifPerKm;
          return n;
        }
      }
    } catch (e, st) {
      logError('OrderService._getTarifPerKm', e, st);
    }
    return _defaultTarifPerKm;
  }

  /// Biaya pelanggaran (Rp). Dibaca dari Firestore app_config/settings.
  /// Di bawah 5000 tetap 5000; di atas 5000 mengikuti Firestore.
  static const int _minViolationFeeRupiah = 5000;

  static Future<int> _getViolationFeeRupiah() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('app_config')
          .doc('settings')
          .get();
      final v = doc.data()?['violationFeeRupiah'];
      if (v != null) {
        final n = (v is num) ? v.toInt() : int.tryParse(v.toString());
        if (n != null && n > 0) {
          return n < _minViolationFeeRupiah ? _minViolationFeeRupiah : n;
        }
      }
    } catch (e, st) {
      logError('OrderService._getMinViolationFeeRupiah', e, st);
    }
    return _minViolationFeeRupiah;
  }

  /// Estimasi kontribusi driver untuk order (sebelum agreed). Dipakai di dialog driver saat masukkan harga.
  /// Travel: totalPenumpang × (jarak × tarif/km). Barang: jarak × tarif barang/km.
  static Future<int?> getEstimatedContributionForDriver(OrderModel order) async {
    final oLat = order.originLat;
    final oLng = order.originLng;
    final dLat = order.destLat ?? order.receiverLat;
    final dLng = order.destLng ?? order.receiverLng;
    if (oLat == null || oLng == null || dLat == null || dLng == null) return null;
    try {
      final parts = await _travelKmFerryEffective(oLat, oLng, dLat, dLng);
      return _getEstimatedContributionForDriverWithKmParts(order, oLat, oLng, dLat, dLng, parts);
    } catch (e, st) {
      logError('OrderService.getEstimatedContributionForDriver', e, st);
      return null;
    }
  }

  /// Sama seperti [getEstimatedContributionForDriver] tetapi memakai [parts] yang sudah dihitung (hindari panggilan ganda ferry).
  static Future<int?> _getEstimatedContributionForDriverWithKmParts(
    OrderModel order,
    double oLat,
    double oLng,
    double dLat,
    double dLng,
    ({double km, double ferryKm, double effectiveKm}) parts,
  ) async {
    try {
      if (parts.km < minTripDistanceKm) return null;
      if (order.isKirimBarang) {
        final (tier, _) = await LacakBarangService.getTierAndFee(
          originLat: oLat,
          originLng: oLng,
          destLat: dLat,
          destLng: dLng,
        );
        final tarifPerKm = await AppConfigService.getTarifBarangPerKmWithCategory(
          tier,
          order.barangCategory,
        );
        return (parts.effectiveKm * tarifPerKm).round();
      } else {
        final totalPenumpang = order.totalPenumpang;
        if (totalPenumpang <= 0) return null;
        return await _calcTripTravelContributionRupiah(
          totalPenumpang,
          oLat,
          oLng,
          dLat,
          dLng,
          parts.effectiveKm,
        );
      }
    } catch (e, st) {
      logError('OrderService._getEstimatedContributionForDriverWithKmParts', e, st);
      return null;
    }
  }

  /// Data jarak + kontribusi untuk pesan chat pertama (format teks di [PassengerFirstChatMessage.formatJarakKontribusiLines]).
  /// Null jika tidak memenuhi [minTripDistanceKm] atau estimasi gagal.
  static Future<JarakKontribusiPreview?> computeJarakKontribusiPreview({
    required double originLat,
    required double originLng,
    required double destLat,
    required double destLng,
    required String orderType,
    int? jumlahKerabat,
    String? barangCategory,
  }) async {
    final preview = OrderModel(
      id: '_preview',
      passengerUid: '',
      driverUid: '',
      routeJourneyNumber: '',
      passengerName: '',
      originText: '',
      destText: '',
      status: statusPendingAgreement,
      driverAgreed: false,
      passengerAgreed: false,
      originLat: originLat,
      originLng: originLng,
      destLat: destLat,
      destLng: destLng,
      orderType: orderType,
      jumlahKerabat: jumlahKerabat,
      barangCategory: barangCategory,
    );
    try {
      final parts =
          await _travelKmFerryEffective(originLat, originLng, destLat, destLng);
      final contrib = await _getEstimatedContributionForDriverWithKmParts(
        preview,
        originLat,
        originLng,
        destLat,
        destLng,
        parts,
      );
      if (contrib == null) return null;
      return JarakKontribusiPreview(
        kmStraight: parts.km,
        ferryKm: parts.ferryKm,
        contributionRp: contrib,
      );
    } catch (e, st) {
      logError('OrderService.computeJarakKontribusiPreview', e, st);
      return null;
    }
  }

  /// Hitung kontribusi travel untuk tampilan (order yang tripTravelContributionRupiah = 0).
  /// Formula: totalPenumpang × (jarak × tarif per km, min Rp 5.000). Jarak = tripDistanceKm − ferryDistanceKm jika ada.
  /// Fallback: jika koordinat null (order lama), pakai totalPenumpang × minRp agar tetap tampil nilai.
  static Future<int?> getTripTravelContributionForDisplay(OrderModel order) async {
    final stored = (order.tripTravelContributionRupiah ?? 0).round();
    if (stored > 0) return stored;
    final totalPenumpang = order.totalPenumpang;
    if (totalPenumpang <= 0) return null;
    final km = order.tripDistanceKm ?? 0;
    if (km <= 0) return null;
    final ferryStored = (order.ferryDistanceKm ?? 0).clamp(0.0, km);
    final chargeKm = (km - ferryStored).clamp(0.0, double.infinity);
    final pickLat = order.pickupLat ?? order.passengerLat ?? order.originLat;
    final pickLng = order.pickupLng ?? order.passengerLng ?? order.originLng;
    final dropLat = order.dropLat ?? order.destLat ?? order.receiverLat;
    final dropLng = order.dropLng ?? order.destLng ?? order.receiverLng;
    if (pickLat != null && pickLng != null && dropLat != null && dropLng != null) {
      return _calcTripTravelContributionRupiah(totalPenumpang, pickLat, pickLng, dropLat, dropLng, chargeKm);
    }
    // Fallback order lama tanpa koordinat: totalPenumpang × minRp (sinkron dengan INDEX_DOKUMEN_KONTRIBUSI)
    final minRupiah = await AppConfigService.getMinKontribusiTravelRupiah();
    return totalPenumpang * minRupiah;
  }

  /// Kontribusi travel per order (Rp): totalPenumpang × (jarak × tarif per km, min Rp 5.000).
  /// [tripDistanceKm] = jarak pembebanan (biasanya setelah kurangi [ferry], selaras dengan tripFare).
  static Future<int?> _calcTripTravelContributionRupiah(
    int totalPenumpang,
    double pickLat,
    double pickLng,
    double dropLat,
    double dropLng,
    double tripDistanceKm,
  ) async {
    try {
      final (tier, _) = await LacakBarangService.getTierAndFee(
        originLat: pickLat,
        originLng: pickLng,
        destLat: dropLat,
        destLng: dropLng,
      );
      final tarifPerKm = await AppConfigService.getTarifKontribusiTravelPerKm(tier);
      final minRupiah = await AppConfigService.getMinKontribusiTravelRupiah();
      final byDistance = (tripDistanceKm * tarifPerKm).round();
      final basePerPenumpang = byDistance > minRupiah ? byDistance : minRupiah;
      return totalPenumpang * basePerPenumpang;
    } catch (e, st) {
      logError('OrderService._calcTripTravelContributionRupiah', e, st);
      return null;
    }
  }

  /// Radius (meter): jika penumpang masih dalam jarak ini dari titik penjemputan, scan selesai diblokir.
  /// 200 m agar GPS error (±50–100 m) tidak memungkinkan scan selesai saat masih dekat titik jemput.
  static const int radiusMasihDiPenjemputanMeter = 200;

  /// Radius (meter): driver harus berada dalam jarak ini dari penumpang saat scan selesai.
  /// Mencegah scan di tengah jalan: driver dan penumpang harus bersama di lokasi turun.
  /// Jika driver > 350 m dari penumpang = kemungkinan driver minta scan sebelum sampai / penumpang scan dari rumah.
  static const int radiusDriverPenumpangSaatSelesaiMeter = 350;

  /// Jarak minimum perjalanan (km): di bawah ini dianggap mencurigakan (trip palsu).
  static const double minTripDistanceKm = 0.05;

  /// Penumpang/pengirim scan barcode driver PICKUP (penjemputan). Validasi TRAKA:orderId:D:PICKUP:*, order milik penumpang.
  /// Set passengerScannedPickupAt, pickupLat/Lng, status picked_up, driverBarcodePayload (COMPLETE).
  static Future<(bool, String?, String?)> applyPassengerScanDriverPickup(
    String rawPayload, {
    double? pickupLat,
    double? pickupLng,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return (false, 'Anda belum login.', null);

    final (orderId, fase, parseError) = parseDriverBarcodePayloadWithPhase(rawPayload);
    if (orderId == null || parseError != null) {
      return (false, parseError ?? 'Payload tidak valid.', null);
    }
    if (fase != 'PICKUP') {
      return (false, 'Barcode ini untuk selesai perjalanan. Gunakan barcode penjemputan.', null);
    }

    final ref = FirebaseFirestore.instance
        .collection(_collectionOrders)
        .doc(orderId);
    final doc = await ref.get();
    if (!doc.exists || doc.data() == null) {
      return (false, 'Pesanan tidak ditemukan.', null);
    }
    final data = doc.data()!;
    if ((data[_fieldPassengerUid] as String?) != user.uid) {
      return (false, 'Barcode ini bukan untuk pesanan Anda.', null);
    }
    if ((data[_fieldStatus] as String?) == statusPickedUp) {
      return (false, 'Penjemputan sudah dikonfirmasi sebelumnya.', null);
    }
    if ((data[_fieldStatus] as String?) != statusAgreed) {
      return (false, 'Status pesanan tidak sesuai.', null);
    }

    if (pickupLat == null || pickupLng == null) {
      return (false, 'Lokasi Anda tidak terdeteksi. Pastikan GPS aktif lalu coba lagi.', null);
    }

    // Validasi: driver harus dekat penumpang (bersama saat penjemputan).
    final driverUid = data[_fieldDriverUid] as String?;
    if (driverUid != null) {
      final (driverLat, driverLng) = await _getDriverPosition(driverUid);
      if (driverLat != null && driverLng != null) {
        final distDriverPenumpang = _distanceMeters(pickupLat, pickupLng, driverLat, driverLng);
        if (distDriverPenumpang > radiusDriverPenumpangSaatSelesaiMeter) {
          return (
            false,
            'Driver harus berada di lokasi penjemputan. Pastikan driver bersama Anda.',
            null,
          );
        }
      }
    }

    try {
      await FirebaseFirestore.instance.runTransaction((tx) async {
        final doc = await tx.get(ref);
        if (!doc.exists || doc.data() == null) throw Exception('Pesanan tidak ditemukan');
        final d = doc.data()!;
        if ((d[_fieldStatus] as String?) == statusPickedUp) throw Exception('Penjemputan sudah dikonfirmasi');
        if ((d[_fieldStatus] as String?) != statusAgreed) throw Exception('Status pesanan tidak sesuai');
        final driverPayload = 'TRAKA:$orderId:D:COMPLETE:${const Uuid().v4()}';
        tx.update(ref, {
          'passengerScannedPickupAt': FieldValue.serverTimestamp(),
          'pickupLat': pickupLat,
          'pickupLng': pickupLng,
          'driverBarcodePayload': driverPayload,
          'status': statusPickedUp,
          'updatedAt': FieldValue.serverTimestamp(),
        });
      });
      return (true, null, orderId);
    } on FirebaseException catch (e) {
      logError('OrderService.applyPassengerScanDriverPickup', e);
      return (false, 'Gagal konfirmasi: ${e.message ?? e.code}', null);
    } catch (e, st) {
      logError('OrderService.applyPassengerScanDriverPickup', e, st);
      return (false, 'Gagal konfirmasi. Coba lagi.', null);
    }
  }

  /// Penumpang scan barcode driver COMPLETE (selesai). Validasi TRAKA:orderId:D:COMPLETE:* atau format lama.
  /// Validasi: penumpang harus di area tujuan (desa/kecamatan/kabupaten) atau minimal tidak di titik penjemputan.
  /// Return (success, error, orderId).
  static Future<(bool, String?, String?)> applyPassengerScanDriver(
    String rawPayload, {
    double? dropLat,
    double? dropLng,
    double? tripDistanceKm,
    double? ferryDistanceKm,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return (false, 'Anda belum login.', null);

    final (orderId, fase, parseError) = parseDriverBarcodePayloadWithPhase(rawPayload);
    if (orderId == null || parseError != null) {
      return (false, parseError ?? 'Payload tidak valid.', null);
    }
    if (fase == 'PICKUP') {
      return (false, 'Ini barcode penjemputan. Gunakan barcode selesai saat sampai tujuan.', null);
    }

    final ref = FirebaseFirestore.instance
        .collection(_collectionOrders)
        .doc(orderId);
    final doc = await ref.get();
    if (!doc.exists || doc.data() == null) {
      return (false, 'Pesanan tidak ditemukan.', null);
    }
    final data = doc.data()!;
    if ((data[_fieldPassengerUid] as String?) != user.uid) {
      return (false, 'Barcode ini bukan untuk pesanan Anda.', null);
    }
    if ((data[_fieldStatus] as String?) == statusCompleted) {
      return (false, 'Perjalanan sudah selesai.', null);
    }
    if ((data[_fieldStatus] as String?) != statusPickedUp) {
      return (false, 'Scan penjemputan terlebih dahulu. Driver tunjukkan barcode penjemputan.', null);
    }

    if (dropLat == null || dropLng == null) {
      return (false, 'Aktifkan GPS dan izin lokasi untuk konfirmasi sampai tujuan.', null);
    }

    final pickLat =
        (data['pickupLat'] as num?)?.toDouble() ??
        (data['passengerLat'] as num?)?.toDouble();
    final pickLng =
        (data['pickupLng'] as num?)?.toDouble() ??
        (data['passengerLng'] as num?)?.toDouble();

    // Validasi 1: tidak boleh masih di titik penjemputan
    if (pickLat != null && pickLng != null) {
      final distDariPenjemputan = _distanceMeters(dropLat, dropLng, pickLat, pickLng);
      if (distDariPenjemputan <= radiusMasihDiPenjemputanMeter) {
        return (
          false,
          'Anda masih di titik penjemputan. Scan barcode hanya bisa dilakukan saat sampai tujuan.',
          null,
        );
      }
    }

    // Validasi 2: penumpang harus di area tujuan (desa/kecamatan/kabupaten)
    final destLevel = (data['destinationValidationLevel'] as String?) ?? 'kecamatan';
    final destLat = (data['destLat'] as num?)?.toDouble();
    final destLng = (data['destLng'] as num?)?.toDouble();
    final receiverLat = (data['receiverLat'] as num?)?.toDouble();
    final receiverLng = (data['receiverLng'] as num?)?.toDouble();
    final targetLat = destLat ?? receiverLat;
    final targetLng = destLng ?? receiverLng;

    if (targetLat == null || targetLng == null) {
      return (
        false,
        'Lokasi tujuan pesanan tidak tersedia. Hubungi driver atau admin.',
        null,
      );
    }
    final (atDest, destError) = await _isAtDestinationLevel(dropLat, dropLng, targetLat, targetLng, destLevel);
    if (!atDest) {
      return (false, destError ?? 'Scan barcode hanya bisa dilakukan saat Anda sudah tiba di tujuan.', null);
    }

    // Validasi 3: driver harus dekat penumpang (bersama di lokasi turun).
    // Mencegah scan di tengah jalan / driver minta scan sebelum sampai agar kontribusi berkurang.
    final driverUid = data[_fieldDriverUid] as String?;
    if (driverUid != null) {
      final (driverLat, driverLng) = await _getDriverPosition(driverUid);
      if (driverLat == null || driverLng == null) {
        return (
          false,
          'Posisi driver tidak terdeteksi. Pastikan driver membuka aplikasi dan berada di dekat Anda.',
          null,
        );
      }
      final distDriverPenumpang = _distanceMeters(dropLat, dropLng, driverLat, driverLng);
      if (distDriverPenumpang > radiusDriverPenumpangSaatSelesaiMeter) {
        return (
          false,
          'Driver harus berada di lokasi turun saat scan. Pastikan driver bersama Anda di tujuan.',
          null,
        );
      }
    }

    // Validasi 4: jarak minimum perjalanan (anti trip palsu)
    double? km;
    if (pickLat != null && pickLng != null) {
      km = _haversineKm(pickLat, pickLng, dropLat, dropLng);
      if (km < minTripDistanceKm) {
        return (
          false,
          'Jarak perjalanan terlalu pendek. Pastikan Anda sudah sampai tujuan yang benar.',
          null,
        );
      }
    }

    // Sembunyikan chat langsung untuk driver dan penumpang (pesanan selesai)
    final updateData = <String, dynamic>{
      'passengerScannedAt': FieldValue.serverTimestamp(),
      'status': statusCompleted,
      'completedAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
      'chatHiddenByPassenger': true,
      'chatHiddenByDriver': true,
      'passengerLastReadAt': FieldValue.serverTimestamp(),
      'driverLastReadAt': FieldValue.serverTimestamp(),
    };
    updateData['dropLat'] = dropLat;
    updateData['dropLng'] = dropLng;
    if (pickLat != null && pickLng != null) {
      km ??= _haversineKm(pickLat, pickLng, dropLat, dropLng);
      updateData['tripDistanceKm'] = km;
    }
    if (tripDistanceKm != null && tripDistanceKm >= 0) {
      km = tripDistanceKm;
      updateData['tripDistanceKm'] = tripDistanceKm;
    }
    double ferry = (ferryDistanceKm != null && ferryDistanceKm >= 0) ? ferryDistanceKm : 0.0;
    if (km != null && km >= 0 && ferry > km) ferry = km; // Anti-kecurangan: ferry tidak boleh melebihi total jarak
    if (ferry > 0) updateData['ferryDistanceKm'] = ferry;
    double? effectiveKmForCharge;
    if (km != null && km >= 0) {
      effectiveKmForCharge = (km - ferry).clamp(0.0, double.infinity);
      final tarifPerKm = await _getTarifPerKm();
      updateData['tripFareRupiah'] = (effectiveKmForCharge * tarifPerKm).round();
    }
    // Kontribusi travel: totalPenumpang × (jarak × tarif per km, min Rp 5.000). Jarak = sama dengan tripFare (setelah kurangi ferry).
    final orderType = (data['orderType'] as String?) ?? OrderModel.typeTravel;
    if (orderType == OrderModel.typeTravel &&
        pickLat != null &&
        pickLng != null &&
        effectiveKmForCharge != null) {
      final jumlahKerabat = (data['jumlahKerabat'] as num?)?.toInt() ?? 0;
      final totalPenumpang = jumlahKerabat > 0 ? 1 + jumlahKerabat : 1;
      final contrib = await _calcTripTravelContributionRupiah(
        totalPenumpang, pickLat, pickLng, dropLat, dropLng, effectiveKmForCharge,
      );
      if (contrib != null) updateData['tripTravelContributionRupiah'] = contrib;
    }
    await ref.update(updateData);
    return (true, null, orderId);
  }

  /// Cek apakah driver dan penumpang saling dekat (untuk nonaktifkan tombol Batal).
  /// [currentLat], [currentLng]: lokasi pengguna yang membuka (driver atau penumpang).
  /// [isDriver]: true = pemanggil adalah driver (bandingkan dengan lokasi penumpang dari order); false = penumpang (bandingkan dengan lokasi driver dari driver_status).
  static Future<bool> isDriverPenumpangDekatForCancel({
    required OrderModel order,
    required double currentLat,
    required double currentLng,
    required bool isDriver,
  }) async {
    if (isDriver) {
      final passLat = order.passengerLat;
      final passLng = order.passengerLng;
      if (passLat == null || passLng == null) return false;
      return _distanceMeters(currentLat, currentLng, passLat, passLng) <=
          radiusDekatMeter;
    } else {
      final (driverLat, driverLng) = await _getDriverPosition(order.driverUid);
      if (driverLat == null || driverLng == null) return false;
      return _distanceMeters(currentLat, currentLng, driverLat, driverLng) <=
          radiusDekatMeter;
    }
  }

  /// Cek apakah panggilan suara boleh digunakan: kesepakatan harga + driver ≤ 5 km dari penumpang.
  /// Return (boleh, alasan jika tidak).
  static Future<(bool, String)> canUseVoiceCall(OrderModel order) async {
    if (order.status != statusAgreed) {
      return (false, 'Panggilan suara hanya tersedia setelah kesepakatan harga.');
    }
    final passLat = order.passengerLat ?? order.pickupLat ?? order.originLat;
    final passLng = order.passengerLng ?? order.pickupLng ?? order.originLng;
    if (passLat == null || passLng == null) {
      return (false, 'Lokasi penumpang belum tersedia.');
    }
    final (driverLat, driverLng) = await _getDriverPosition(order.driverUid);
    if (driverLat == null || driverLng == null) {
      return (false, 'Lokasi driver belum tersedia.');
    }
    final distM = _distanceMeters(driverLat, driverLng, passLat, passLng);
    final radiusM = radiusVoiceCallKm * 1000;
    if (distM > radiusM) {
      return (
        false,
        'Panggilan suara tersedia saat driver dalam radius $radiusVoiceCallKm km dari penumpang (jarak saat ini: ${(distM / 1000).toStringAsFixed(1)} km).',
      );
    }
    return (true, '');
  }

  /// Set waktu driver sampai di titik penjemputan (sekali saja). Dipanggil dari driver app saat driver pertama kali dalam radius 300 m dari titik jemput.
  static Future<bool> setDriverArrivedAtPickupAt(String orderId) async {
    final ref = FirebaseFirestore.instance
        .collection(_collectionOrders)
        .doc(orderId);
    final doc = await ref.get();
    if (!doc.exists || doc.data() == null) return false;
    final data = doc.data()!;
    if ((data[_fieldStatus] as String?) != statusAgreed) return false;
    if (data['driverArrivedAtPickupAt'] != null) return true; // sudah diset
    await ref.update({
      'driverArrivedAtPickupAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    return true;
  }

  /// Driver konfirmasi penumpang dijemput tanpa scan (semi-otomatis). Sah jika HP driver dan penumpang berdekatan (≤30 m).
  static Future<(bool, String?)> driverConfirmPickupNoScan(
    String orderId,
    double pickupLat,
    double pickupLng,
  ) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return (false, 'Anda belum login.');

    final ref = FirebaseFirestore.instance
        .collection(_collectionOrders)
        .doc(orderId);
    final doc = await ref.get();
    if (!doc.exists || doc.data() == null) {
      return (false, 'Pesanan tidak ditemukan.');
    }
    final data = doc.data()!;
    if ((data[_fieldDriverUid] as String?) != user.uid) {
      return (false, 'Bukan pesanan Anda.');
    }
    if ((data[_fieldStatus] as String?) == statusPickedUp) {
      return (false, 'Penumpang sudah dijemput.');
    }
    if ((data[_fieldStatus] as String?) != statusAgreed) {
      return (false, 'Status pesanan tidak sesuai.');
    }

    final orderType = (data['orderType'] as String?) ?? OrderModel.typeTravel;
    if (orderType != OrderModel.typeTravel) {
      return (
        false,
        'Konfirmasi otomatis penjemputan hanya untuk travel. Gunakan scan barcode.',
      );
    }

    final orderModel = OrderModel.fromFirestore(doc);
    final passCoords = orderModel.coordsForDriverPickupProximity;
    if (passCoords == null) {
      return (false, 'Lokasi penumpang tidak tersedia.');
    }
    final passLat = passCoords.$1;
    final passLng = passCoords.$2;
    final distM = _distanceMeters(pickupLat, pickupLng, passLat, passLng);
    if (distM > radiusBerdekatanMeter) {
      return (
        false,
        'Hanya bisa saat HP Anda dan penumpang berdekatan (radius $radiusBerdekatanMeter m).',
      );
    }
    final violationFeeRupiah = await _getViolationFeeRupiah();

    final updateData = <String, dynamic>{
      'driverScannedAt': FieldValue.serverTimestamp(),
      'passengerScannedPickupAt': FieldValue.serverTimestamp(),
      'driverBarcodePayload': 'TRAKA:$orderId:D:COMPLETE:${const Uuid().v4()}',
      'pickupLat': pickupLat,
      'pickupLng': pickupLng,
      'status': statusPickedUp,
      'updatedAt': FieldValue.serverTimestamp(),
      'autoConfirmPickup': true,
    };
    // Pelanggaran hanya untuk travel, bukan kirim barang.
    if (orderType == OrderModel.typeTravel) {
      updateData['driverViolationFee'] = violationFeeRupiah;
    }
    await ref.update(updateData);

    // Catat pelanggaran driver (bayar via kontribusi gabungan).
    if (orderType == OrderModel.typeTravel) {
      await FirebaseFirestore.instance.collection('violation_records').add({
        'userId': user.uid,
        'orderId': orderId,
        'amount': violationFeeRupiah,
        'type': 'driver',
        'paidAt': null,
        'createdAt': FieldValue.serverTimestamp(),
      });
      await FirebaseFirestore.instance.collection('users').doc(user.uid).update({
        'outstandingViolationFee': FieldValue.increment(violationFeeRupiah),
        'outstandingViolationCount': FieldValue.increment(1),
      });
    }
    return (true, null);
  }

  /// Cek apakah penumpang bisa konfirmasi sampai tujuan: berdekatan (≤30 m) dengan driver ATAU (di tujuan dan dekat driver 300 m). Untuk tampilkan tombol tanpa scan.
  static Future<bool> passengerCanConfirmArrival(
    String orderId,
    double dropLat,
    double dropLng,
  ) async {
    final ref = FirebaseFirestore.instance
        .collection(_collectionOrders)
        .doc(orderId);
    final doc = await ref.get();
    if (!doc.exists || doc.data() == null) return false;
    final data = doc.data()!;
    if ((data[_fieldStatus] as String?) != statusPickedUp) return false;
    final orderTypeForUi =
        (data['orderType'] as String?) ?? OrderModel.typeTravel;
    if (orderTypeForUi != OrderModel.typeTravel) return false;
    final driverUid = data[_fieldDriverUid] as String?;
    if (driverUid == null) return false;
    final (driverLat, driverLng) = await _getDriverPosition(driverUid);
    if (driverLat == null || driverLng == null) return false;
    final distKeDriver = _distanceMeters(dropLat, dropLng, driverLat, driverLng);
    if (distKeDriver <= radiusBerdekatanMeter) return true;
    final destLat = (data['destLat'] as num?)?.toDouble();
    final destLng = (data['destLng'] as num?)?.toDouble();
    if (destLat != null && destLng != null) {
      if (_distanceMeters(dropLat, dropLng, destLat, destLng) >
          radiusDekatMeter) {
        return false;
      }
    }
    return distKeDriver <= radiusDekatMeter;
  }

  /// Penumpang konfirmasi sampai tujuan tanpa scan (semi-otomatis). Sah jika penumpang dan driver berdekatan (≤30 m) atau dalam radius 300 m dari tujuan dan dari driver.
  static Future<(bool, String?)> passengerConfirmArrivalNoScan(
    String orderId,
    double dropLat,
    double dropLng,
  ) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return (false, 'Anda belum login.');

    final ref = FirebaseFirestore.instance
        .collection(_collectionOrders)
        .doc(orderId);
    final doc = await ref.get();
    if (!doc.exists || doc.data() == null) {
      return (false, 'Pesanan tidak ditemukan.');
    }
    final data = doc.data()!;
    if ((data[_fieldPassengerUid] as String?) != user.uid) {
      return (false, 'Bukan pesanan Anda.');
    }
    if ((data[_fieldStatus] as String?) == statusCompleted) {
      return (false, 'Perjalanan sudah selesai.');
    }
    if ((data[_fieldStatus] as String?) != statusPickedUp) {
      return (false, 'Status pesanan tidak sesuai.');
    }

    final orderType = (data['orderType'] as String?) ?? OrderModel.typeTravel;
    if (orderType != OrderModel.typeTravel) {
      return (
        false,
        'Konfirmasi tanpa scan di tujuan hanya untuk travel. Kirim barang: gunakan scan barcode.',
      );
    }

    final driverUid = data[_fieldDriverUid] as String?;
    if (driverUid == null) return (false, 'Data driver tidak valid.');
    final (driverLat, driverLng) = await _getDriverPosition(driverUid);
    if (driverLat == null || driverLng == null) {
      return (false, 'Lokasi driver tidak tersedia.');
    }
    final distKeDriver = _distanceMeters(dropLat, dropLng, driverLat, driverLng);
    if (distKeDriver > radiusBerdekatanMeter) {
      final destLat = (data['destLat'] as num?)?.toDouble();
      final destLng = (data['destLng'] as num?)?.toDouble();
      if (destLat != null && destLng != null) {
        if (_distanceMeters(dropLat, dropLng, destLat, destLng) >
            radiusDekatMeter) {
          return (
            false,
            'Anda belum dalam radius $radiusDekatMeter m dari tujuan atau berdekatan $radiusBerdekatanMeter m dengan driver.',
          );
        }
      }
      if (distKeDriver > radiusDekatMeter) {
        return (
          false,
          'Anda belum dalam radius $radiusDekatMeter m dari driver atau berdekatan $radiusBerdekatanMeter m.',
        );
      }
    }
    final violationFeeRupiah = await _getViolationFeeRupiah();

    final updateData = <String, dynamic>{
      'passengerScannedAt': FieldValue.serverTimestamp(),
      'status': statusCompleted,
      'completedAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
      'dropLat': dropLat,
      'dropLng': dropLng,
      'chatHiddenByPassenger': true,
      'chatHiddenByDriver': true,
      'passengerLastReadAt': FieldValue.serverTimestamp(),
      'driverLastReadAt': FieldValue.serverTimestamp(),
      'autoConfirmComplete': true,
    };
    // Pelanggaran hanya untuk travel, bukan kirim barang.
    if (orderType == OrderModel.typeTravel) {
      updateData['passengerViolationFee'] = violationFeeRupiah;
    }
    final pickLat =
        (data['pickupLat'] as num?)?.toDouble() ??
        (data['passengerLat'] as num?)?.toDouble();
    final pickLng =
        (data['pickupLng'] as num?)?.toDouble() ??
        (data['passengerLng'] as num?)?.toDouble();
    if (pickLat != null && pickLng != null) {
      final kmPart = await _travelKmFerryEffective(pickLat, pickLng, dropLat, dropLng);
      updateData['tripDistanceKm'] = kmPart.km;
      if (kmPart.ferryKm > 0) updateData['ferryDistanceKm'] = kmPart.ferryKm;
      final tarifPerKm = await _getTarifPerKm();
      updateData['tripFareRupiah'] = (kmPart.effectiveKm * tarifPerKm).round();
      if (orderType == OrderModel.typeTravel) {
        final jumlahKerabat = (data['jumlahKerabat'] as num?)?.toInt() ?? 0;
        final totalPenumpang = jumlahKerabat > 0 ? 1 + jumlahKerabat : 1;
        final contrib = await _calcTripTravelContributionRupiah(
          totalPenumpang, pickLat, pickLng, dropLat, dropLng, kmPart.effectiveKm,
        );
        if (contrib != null) updateData['tripTravelContributionRupiah'] = contrib;
      }
    }
    await ref.update(updateData);

    // Pelanggaran penumpang: catat dan update outstanding di users (hanya travel).
    if (orderType == OrderModel.typeTravel) {
      await FirebaseFirestore.instance.collection('violation_records').add({
        'userId': user.uid,
        'orderId': orderId,
        'amount': violationFeeRupiah,
        'type': 'passenger',
        'paidAt': null,
        'createdAt': FieldValue.serverTimestamp(),
      });
      final userRef = FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid);
      await userRef.update({
        'outstandingViolationFee': FieldValue.increment(violationFeeRupiah),
        'outstandingViolationCount': FieldValue.increment(1),
      });
    }
    return (true, null);
  }

  /// Auto-complete pesanan saat driver dan penumpang menjauh (>500 m). Dipanggil dari driver atau penumpang app.
  /// [callerLat], [callerLng]: posisi pemanggil. [isDriver]: true jika pemanggil driver.
  static Future<(bool, String?)> completeOrderWhenFarApart(
    String orderId,
    double callerLat,
    double callerLng,
    bool isDriver,
  ) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return (false, 'Anda belum login.');

    final ref = FirebaseFirestore.instance
        .collection(_collectionOrders)
        .doc(orderId);
    final doc = await ref.get();
    if (!doc.exists || doc.data() == null) {
      return (false, 'Pesanan tidak ditemukan.');
    }
    final data = doc.data()!;
    if ((data[_fieldStatus] as String?) == statusCompleted) {
      return (false, 'Perjalanan sudah selesai.');
    }
    if ((data[_fieldStatus] as String?) != statusPickedUp) {
      return (false, 'Status pesanan tidak sesuai.');
    }

    final orderType = (data['orderType'] as String?) ?? OrderModel.typeTravel;
    if (orderType != OrderModel.typeTravel) {
      return (
        false,
        'Penyelesaian otomatis saat menjauh hanya untuk travel.',
      );
    }

    double otherLat;
    double otherLng;
    double dropLat;
    double dropLng;
    if (isDriver) {
      if ((data[_fieldDriverUid] as String?) != user.uid) {
        return (false, 'Bukan pesanan Anda.');
      }
      final orderModel = OrderModel.fromFirestore(doc);
      final passCoords = orderModel.coordsForDriverPickupProximity;
      if (passCoords == null) {
        return (false, 'Lokasi penumpang belum tersedia.');
      }
      otherLat = passCoords.$1;
      otherLng = passCoords.$2;
      dropLat = otherLat;
      dropLng = otherLng;
    } else {
      if ((data[_fieldPassengerUid] as String?) != user.uid) {
        return (false, 'Bukan pesanan Anda.');
      }
      final driverUid = data[_fieldDriverUid] as String?;
      if (driverUid == null) return (false, 'Data driver tidak valid.');
      final (driverLat, driverLng) = await _getDriverPosition(driverUid);
      if (driverLat == null || driverLng == null) {
        return (false, 'Lokasi driver tidak tersedia.');
      }
      otherLat = driverLat;
      otherLng = driverLng;
      dropLat = callerLat;
      dropLng = callerLng;
    }

    final distM = _distanceMeters(callerLat, callerLng, otherLat, otherLng);
    if (distM <= radiusMenjauhMeter) {
      return (false, 'Belum menjauh. Jarak masih ${distM.round()} m.');
    }

    final violationFeeRupiah = await _getViolationFeeRupiah();

    final updateData = <String, dynamic>{
      'passengerScannedAt': FieldValue.serverTimestamp(),
      'status': statusCompleted,
      'completedAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
      'dropLat': dropLat,
      'dropLng': dropLng,
      'chatHiddenByPassenger': true,
      'chatHiddenByDriver': true,
      'passengerLastReadAt': FieldValue.serverTimestamp(),
      'driverLastReadAt': FieldValue.serverTimestamp(),
      'autoConfirmComplete': true,
      'passengerViolationFee': violationFeeRupiah,
    };
    final pickLat =
        (data['pickupLat'] as num?)?.toDouble() ??
        (data['passengerLat'] as num?)?.toDouble();
    final pickLng =
        (data['pickupLng'] as num?)?.toDouble() ??
        (data['passengerLng'] as num?)?.toDouble();
    if (pickLat != null && pickLng != null) {
      final kmPart = await _travelKmFerryEffective(pickLat, pickLng, dropLat, dropLng);
      updateData['tripDistanceKm'] = kmPart.km;
      if (kmPart.ferryKm > 0) updateData['ferryDistanceKm'] = kmPart.ferryKm;
      final tarifPerKm = await _getTarifPerKm();
      updateData['tripFareRupiah'] = (kmPart.effectiveKm * tarifPerKm).round();
      if (orderType == OrderModel.typeTravel) {
        final jumlahKerabat = (data['jumlahKerabat'] as num?)?.toInt() ?? 0;
        final totalPenumpang = jumlahKerabat > 0 ? 1 + jumlahKerabat : 1;
        final contrib = await _calcTripTravelContributionRupiah(
          totalPenumpang, pickLat, pickLng, dropLat, dropLng, kmPart.effectiveKm,
        );
        if (contrib != null) updateData['tripTravelContributionRupiah'] = contrib;
      }
    }
    await ref.update(updateData);

    if (orderType == OrderModel.typeTravel) {
      final passengerUid = data[_fieldPassengerUid] as String?;
      if (passengerUid != null) {
        await FirebaseFirestore.instance.collection('violation_records').add({
          'userId': passengerUid,
          'orderId': orderId,
          'amount': violationFeeRupiah,
          'type': 'passenger',
          'paidAt': null,
          'createdAt': FieldValue.serverTimestamp(),
        });
        await FirebaseFirestore.instance.collection('users').doc(passengerUid).update({
          'outstandingViolationFee': FieldValue.increment(violationFeeRupiah),
          'outstandingViolationCount': FieldValue.increment(1),
        });
      }
    }
    return (true, null);
  }

  /// Penumpang scan barcode driver (sampai tujuan) atau driver scan barcode penerima (kirim barang). Status → completed.
  static Future<bool> setCompleted(String orderId) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return false;

    final ref = FirebaseFirestore.instance
        .collection(_collectionOrders)
        .doc(orderId);
    final doc = await ref.get();
    if (!doc.exists || doc.data() == null) return false;
    final data = doc.data()!;
    final driverUid = data[_fieldDriverUid] as String?;
    final passengerUid = data[_fieldPassengerUid] as String?;
    final receiverUid = data['receiverUid'] as String?;
    if (user.uid != driverUid &&
        user.uid != passengerUid &&
        user.uid != receiverUid) {
      return false;
    }

    await ref.update({
      'status': statusCompleted,
      'completedAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
      'chatHiddenByPassenger': true,
      'chatHiddenByDriver': true,
      'passengerLastReadAt': FieldValue.serverTimestamp(),
      'driverLastReadAt': FieldValue.serverTimestamp(),
    });
    return true;
  }

  /// Satu thread pra-sepakat kirim barang per pasangan penumpang–driver
  /// ([statusPendingAgreement] / [statusPendingReceiver]).
  /// Mencegah order ganda dan pesan otomatis chat berulang. Setelah [statusAgreed] atau [statusPickedUp],
  /// penumpang boleh membuat kirim barang baru ke driver yang sama.
  ///
  /// **Hybrid:** pembuatan order saat ini lewat Firestore; bila nanti lewat API, invariant yang sama
  /// harus ditegakkan di server.
  static Future<OrderModel?> getPassengerPendingKirimBarangWithDriver(
    String passengerUid,
    String driverUid,
  ) async {
    if (passengerUid.isEmpty || driverUid.isEmpty) return null;
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection(_collectionOrders)
          .where(_fieldPassengerUid, isEqualTo: passengerUid)
          .where(_fieldDriverUid, isEqualTo: driverUid)
          .limit(40)
          .get();
      OrderModel? newest;
      for (final doc in snapshot.docs) {
        final o = OrderModel.fromFirestore(doc);
        if (!o.isKirimBarang) continue;
        final s = o.status;
        if (s != statusPendingAgreement && s != statusPendingReceiver) continue;
        if (newest == null) {
          newest = o;
          continue;
        }
        final a = o.createdAt;
        final b = newest.createdAt;
        if (a != null && (b == null || a.isAfter(b))) {
          newest = o;
        }
      }
      return newest;
    } catch (e, st) {
      logError('OrderService.getPassengerPendingKirimBarangWithDriver', e, st);
      return null;
    }
  }

  /// Travel belum sepakat harga: [statusPendingAgreement] saja, pasangan penumpang–driver sama.
  static Future<OrderModel?> getPassengerPendingTravelWithDriver(
    String passengerUid,
    String driverUid,
  ) async {
    if (passengerUid.isEmpty || driverUid.isEmpty) return null;
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection(_collectionOrders)
          .where(_fieldPassengerUid, isEqualTo: passengerUid)
          .where(_fieldDriverUid, isEqualTo: driverUid)
          .limit(40)
          .get();
      OrderModel? newest;
      for (final doc in snapshot.docs) {
        final o = OrderModel.fromFirestore(doc);
        if (o.orderType != OrderModel.typeTravel) continue;
        if (o.status != statusPendingAgreement) continue;
        if (newest == null) {
          newest = o;
          continue;
        }
        final a = o.createdAt;
        final b = newest.createdAt;
        if (a != null && (b == null || a.isAfter(b))) {
          newest = o;
        }
      }
      return newest;
    } catch (e, st) {
      logError('OrderService.getPassengerPendingTravelWithDriver', e, st);
      return null;
    }
  }

  /// Cari pesanan aktif (pending_agreement atau agreed) antara penumpang dan driver.
  /// Untuk membuka chat dengan orderId yang sama.
  static Future<OrderModel?> getActiveOrderBetween(
    String passengerUid,
    String driverUid,
  ) async {
    final snapshot = await FirebaseFirestore.instance
        .collection(_collectionOrders)
        .where(_fieldPassengerUid, isEqualTo: passengerUid)
        .where(_fieldDriverUid, isEqualTo: driverUid)
        .where(
          _fieldStatus,
          whereIn: [statusPendingAgreement, statusAgreed, statusPickedUp],
        )
        .orderBy('createdAt', descending: true)
        .limit(1)
        .get();

    if (snapshot.docs.isEmpty) return null;
    return OrderModel.fromFirestore(snapshot.docs.first);
  }

  /// Pesanan aktif pertama untuk driver (untuk tab Chat driver).
  static Future<OrderModel?> getFirstActiveOrderForDriver(
    String driverUid,
  ) async {
    final snapshot = await FirebaseFirestore.instance
        .collection(_collectionOrders)
        .where(_fieldDriverUid, isEqualTo: driverUid)
        .where(
          _fieldStatus,
          whereIn: [statusPendingAgreement, statusAgreed, statusPickedUp],
        )
        .orderBy('createdAt', descending: true)
        .limit(1)
        .get();

    if (snapshot.docs.isEmpty) return null;
    return OrderModel.fromFirestore(snapshot.docs.first);
  }

  /// Daftar pesanan penumpang untuk halaman list chat (status bukan cancelled).
  static Future<List<OrderModel>> getOrdersForPassenger(
    String passengerUid,
  ) async {
    final snapshot = await FirebaseFirestore.instance
        .collection(_collectionOrders)
        .where(_fieldPassengerUid, isEqualTo: passengerUid)
        .where(
          _fieldStatus,
          whereIn: [
            statusPendingAgreement,
            statusAgreed,
            statusPickedUp,
            statusCompleted,
          ],
        )
        .orderBy('updatedAt', descending: true)
        .get();

    return snapshot.docs.map((d) => OrderModel.fromFirestore(d)).toList();
  }

  /// Daftar pesanan driver untuk halaman list chat (status bukan cancelled).
  static Future<List<OrderModel>> getOrdersForDriver(String driverUid) async {
    final snapshot = await FirebaseFirestore.instance
        .collection(_collectionOrders)
        .where(_fieldDriverUid, isEqualTo: driverUid)
        .where(
          _fieldStatus,
          whereIn: [
            statusPendingAgreement,
            statusAgreed,
            statusPickedUp,
            statusCompleted,
          ],
        )
        .orderBy('updatedAt', descending: true)
        .get();

    return snapshot.docs.map((d) => OrderModel.fromFirestore(d)).toList();
  }

  /// Penerima setuju jadi penerima (kirim barang). Status → pending_agreement; order lalu muncul ke driver.
  /// [receiverLat], [receiverLng], [receiverLocationText]: lokasi penerima (wajib untuk validasi scan).
  static Future<bool> setReceiverAgreed(
    String orderId, {
    double? receiverLat,
    double? receiverLng,
    String? receiverLocationText,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return false;
    final ref = FirebaseFirestore.instance
        .collection(_collectionOrders)
        .doc(orderId);
    final doc = await ref.get();
    if (!doc.exists || doc.data() == null) return false;
    final data = doc.data()!;
    if ((data['receiverUid'] as String?) != user.uid) return false;
    if ((data[_fieldStatus] as String?) != statusPendingReceiver) return false;
    final updateData = <String, dynamic>{
      'receiverAgreedAt': FieldValue.serverTimestamp(),
      'status': statusPendingAgreement,
      'updatedAt': FieldValue.serverTimestamp(),
    };
    if (receiverLat != null && receiverLng != null) {
      updateData['receiverLat'] = receiverLat;
      updateData['receiverLng'] = receiverLng;
      if (receiverLocationText != null && receiverLocationText.isNotEmpty) {
        updateData['receiverLocationText'] = receiverLocationText;
      }
    }
    await ref.update(updateData);
    return true;
  }

  /// Penerima menolak jadi penerima (kirim barang). Status → cancelled.
  static Future<bool> setReceiverRejected(String orderId) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return false;
    final ref = FirebaseFirestore.instance
        .collection(_collectionOrders)
        .doc(orderId);
    final doc = await ref.get();
    if (!doc.exists || doc.data() == null) return false;
    final data = doc.data()!;
    if ((data['receiverUid'] as String?) != user.uid) return false;
    if ((data[_fieldStatus] as String?) != statusPendingReceiver) return false;
    await ref.update({
      'status': statusCancelled,
      'updatedAt': FieldValue.serverTimestamp(),
    });
    return true;
  }

  /// Penerima scan barcode driver (barang diterima). Validasi fase COMPLETE. Set receiverScannedAt, status completed.
  /// Return (success, error, orderId). Kirim barang: tidak ada rating driver.
  static Future<(bool, String?, String?)> applyReceiverScanDriver(
    String rawPayload, {
    double? dropLat,
    double? dropLng,
    double? ferryDistanceKm,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return (false, 'Anda belum login.', null);

    final (orderId, fase, parseError) = parseDriverBarcodePayloadWithPhase(rawPayload);
    if (orderId == null || parseError != null) {
      return (false, parseError ?? 'Payload tidak valid.', null);
    }
    if (fase == 'PICKUP') {
      return (false, 'Ini barcode penjemputan. Pengirim yang scan saat serah barang ke driver.', null);
    }

    final ref = FirebaseFirestore.instance
        .collection(_collectionOrders)
        .doc(orderId);
    final doc = await ref.get();
    if (!doc.exists || doc.data() == null) {
      return (false, 'Pesanan tidak ditemukan.', null);
    }
    final data = doc.data()!;
    if ((data['receiverUid'] as String?) != user.uid) {
      return (false, 'Barcode ini bukan untuk pesanan Anda (penerima).', null);
    }
    if ((data['orderType'] as String?) != OrderModel.typeKirimBarang) {
      return (false, 'Bukan pesanan kirim barang.', null);
    }
    if ((data[_fieldStatus] as String?) == statusCompleted) {
      return (false, 'Barang sudah diterima.', null);
    }
    if ((data[_fieldStatus] as String?) != statusPickedUp) {
      return (false, 'Driver belum mengantarkan barang. Pengirim scan barcode penjemputan terlebih dahulu.', null);
    }

    if (dropLat == null || dropLng == null) {
      return (false, 'Lokasi Anda tidak terdeteksi. Pastikan GPS aktif.', null);
    }

    // Validasi: penerima di area tujuan (desa/kecamatan/kabupaten/provinsi)
    final destLevel = (data['destinationValidationLevel'] as String?) ?? 'kecamatan';
    final receiverLat = (data['receiverLat'] as num?)?.toDouble();
    final receiverLng = (data['receiverLng'] as num?)?.toDouble();
    if (receiverLat == null || receiverLng == null) {
      return (
        false,
        'Lokasi tujuan pesanan tidak tersedia. Hubungi driver atau admin.',
        null,
      );
    }
    final (atDest, destError) = await _isAtDestinationLevel(dropLat, dropLng, receiverLat, receiverLng, destLevel);
    if (!atDest) {
      return (false, destError ?? 'Scan barcode hanya bisa dilakukan saat Anda sudah tiba di tujuan.', null);
    }

    // Validasi: driver harus dekat penerima (bersama saat serah terima barang).
    final driverUid = data[_fieldDriverUid] as String?;
    if (driverUid != null) {
      final (driverLat, driverLng) = await _getDriverPosition(driverUid);
      if (driverLat == null || driverLng == null) {
        return (
          false,
          'Posisi driver tidak terdeteksi. Pastikan driver membuka aplikasi dan berada di dekat Anda.',
          null,
        );
      }
      final distDriverReceiver = _distanceMeters(dropLat, dropLng, driverLat, driverLng);
      if (distDriverReceiver > radiusDriverPenumpangSaatSelesaiMeter) {
        return (
          false,
          'Driver harus berada di lokasi saat serah terima. Pastikan driver bersama Anda.',
          null,
        );
      }
    }

    // Validasi jarak minimum (anti trip palsu)
    final pickLatRecv = (data['pickupLat'] as num?)?.toDouble() ?? (data['passengerLat'] as num?)?.toDouble();
    final pickLngRecv = (data['pickupLng'] as num?)?.toDouble() ?? (data['passengerLng'] as num?)?.toDouble();
    if (pickLatRecv != null && pickLngRecv != null) {
      final kmRecv = _haversineKm(pickLatRecv, pickLngRecv, dropLat, dropLng);
      if (kmRecv < minTripDistanceKm) {
        return (
          false,
          'Jarak pengiriman terlalu pendek. Pastikan Anda sudah menerima barang di lokasi yang benar.',
          null,
        );
      }
    }

    // Kirim barang: validasi lokasi tujuan selesai.
    // Sembunyikan chat langsung untuk driver dan penumpang (pesanan selesai)

    final updateData = <String, dynamic>{
      'receiverScannedAt': FieldValue.serverTimestamp(),
      'status': statusCompleted,
      'completedAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
      'dropLat': dropLat,
      'dropLng': dropLng,
      'chatHiddenByPassenger': true,
      'chatHiddenByDriver': true,
      'passengerLastReadAt': FieldValue.serverTimestamp(),
      'driverLastReadAt': FieldValue.serverTimestamp(),
    };
    final pickLat = pickLatRecv;
    final pickLng = pickLngRecv;
    if (pickLat != null && pickLng != null) {
      final km = _haversineKm(pickLat, pickLng, dropLat, dropLng);
      updateData['tripDistanceKm'] = km;
      double ferry = (ferryDistanceKm != null && ferryDistanceKm >= 0) ? ferryDistanceKm : 0.0;
      if (ferry > km) ferry = km; // Anti-kecurangan: ferry tidak boleh melebihi total jarak
      if (ferry > 0) updateData['ferryDistanceKm'] = ferry;
      final effectiveKm = (km - ferry).clamp(0.0, double.infinity);
      // Kontribusi kirim barang: jarak × tarif per km (berdasarkan tier provinsi dan kategori barang)
      final (tier, _) = await LacakBarangService.getTierAndFee(
        originLat: pickLat,
        originLng: pickLng,
        destLat: dropLat,
        destLng: dropLng,
      );
      final barangCategory = data['barangCategory'] as String?;
      final tarifPerKm = await AppConfigService.getTarifBarangPerKmWithCategory(tier, barangCategory);
      updateData['tripBarangFareRupiah'] = (effectiveKm * tarifPerKm).round();
    }
    await ref.update(updateData);
    return (true, null, orderId);
  }

  /// Stream pesanan dimana user adalah penerima (untuk konfirmasi "Anda ditunjuk sebagai penerima").
  /// [includeHidden] true = tampilkan semua termasuk yang disembunyikan (Data Order/Riwayat).
  /// false = exclude chatHiddenByReceiver (untuk list Pesan).
  static Stream<List<OrderModel>> streamOrdersForReceiver(
    String receiverUid, {
    bool includeHidden = true,
  }) {
    return FirebaseFirestore.instance
        .collection(_collectionOrders)
        .where('receiverUid', isEqualTo: receiverUid)
        .where(_fieldStatus, whereIn: [statusPendingReceiver, statusPendingAgreement, statusAgreed, statusPickedUp, statusCompleted])
        .snapshots()
        .map((snap) {
          var list = snap.docs.map((d) => OrderModel.fromFirestore(d)).toList();
          if (!includeHidden) {
            list = list.where((o) => !o.chatHiddenByReceiver).toList();
          }
          list.sort((a, b) {
            final at = a.updatedAt ?? a.createdAt;
            final bt = b.updatedAt ?? b.createdAt;
            if (at == null && bt == null) return 0;
            if (at == null) return 1;
            if (bt == null) return -1;
            return bt.compareTo(at);
          });
          return list;
        });
  }

  /// Stream pesanan untuk driver (untuk badge unread chat).
  /// Stream pesanan untuk driver (list chat). Filter: exclude chatHiddenByDriver.
  /// Termasuk status cancelled agar chat pesanan yang dibatalkan bisa dihapus manual.
  /// Dibatasi 50 order terakhir.
  static Stream<List<OrderModel>> streamOrdersForDriver(String driverUid) {
    return FirebaseFirestore.instance
        .collection(_collectionOrders)
        .where(_fieldDriverUid, isEqualTo: driverUid)
        .where(
          _fieldStatus,
          whereIn: [
            statusPendingAgreement,
            statusAgreed,
            statusPickedUp,
            statusCompleted,
            statusCancelled,
          ],
        )
        .orderBy('updatedAt', descending: true)
        .limit(streamOrdersLimit)
        .snapshots()
        .map((snap) => snap.docs
            .map((d) => OrderModel.fromFirestore(d))
            .where((o) => !o.chatHiddenByDriver)
            .toList());
  }

  /// Set waktu terakhir driver baca chat (untuk badge unread). Dipanggil saat driver buka chat.
  static Future<bool> setDriverLastReadAt(String orderId) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return false;
    final ref = FirebaseFirestore.instance
        .collection(_collectionOrders)
        .doc(orderId);
    final doc = await ref.get();
    if (!doc.exists) return false;
    final data = doc.data();
    if (data == null || (data[_fieldDriverUid] as String?) != user.uid) {
      return false;
    }
    await ref.update({'driverLastReadAt': FieldValue.serverTimestamp()});
    return true;
  }

  /// Set waktu terakhir penumpang baca chat (untuk badge unread). Dipanggil saat penumpang buka chat.
  static Future<bool> setPassengerLastReadAt(String orderId) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return false;
    final ref = FirebaseFirestore.instance
        .collection(_collectionOrders)
        .doc(orderId);
    final doc = await ref.get();
    if (!doc.exists) return false;
    final data = doc.data();
    if (data == null || (data[_fieldPassengerUid] as String?) != user.uid) {
      return false;
    }
    await ref.update({'passengerLastReadAt': FieldValue.serverTimestamp()});
    return true;
  }

  /// Set waktu terakhir penerima (receiver) baca chat. Untuk kirim barang.
  static Future<bool> setReceiverLastReadAt(String orderId) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return false;
    final ref = FirebaseFirestore.instance
        .collection(_collectionOrders)
        .doc(orderId);
    final doc = await ref.get();
    if (!doc.exists) return false;
    final data = doc.data();
    if (data == null || (data['receiverUid'] as String?) != user.uid) {
      return false;
    }
    await ref.update({'receiverLastReadAt': FieldValue.serverTimestamp()});
    return true;
  }

  static Future<bool> _withReadRetry(
    Future<bool> Function() attempt,
  ) async {
    for (var i = 0; i < 3; i++) {
      final ok = await attempt();
      if (ok) return true;
      await Future<void>.delayed(Duration(milliseconds: 120 * (i + 1)));
    }
    return false;
  }

  /// Sama seperti [setDriverLastReadAt] dengan retry singkat (koneksi buruk).
  static Future<bool> setDriverLastReadAtReliable(String orderId) =>
      _withReadRetry(() => setDriverLastReadAt(orderId));

  static Future<bool> setPassengerLastReadAtReliable(String orderId) =>
      _withReadRetry(() => setPassengerLastReadAt(orderId));

  static Future<bool> setReceiverLastReadAtReliable(String orderId) =>
      _withReadRetry(() => setReceiverLastReadAt(orderId));
}
