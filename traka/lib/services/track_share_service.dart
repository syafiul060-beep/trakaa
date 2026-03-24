import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../config/feature_flags.dart';
import '../models/order_model.dart';
import 'exemption_service.dart';
import 'order_service.dart';

/// Service untuk membagikan link lacak perjalanan ke keluarga.
/// - Travel: penumpang harus bayar Lacak Driver dulu.
/// - Kirim barang: pengirim/penerima harus bayar Lacak Barang dulu (siapa bagi link, siapa bayar).
/// Link tidak berlaku saat pesanan sampai tujuan (status completed).
class TrackShareService {
  static const String _collection = 'track_share_links';

  /// Base URL halaman track (untuk keluarga buka di browser).
  /// Deploy track.html ke Firebase Hosting: https://syafiul-traka.web.app/track.html
  static const String trackBaseUrl = 'https://syafiul-traka.web.app/track.html';

  static String _randomToken() {
    const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
    final r = Random.secure();
    return List.generate(32, (_) => chars[r.nextInt(chars.length)]).join();
  }

  /// Generate token dan simpan ke Firestore, lalu return URL untuk dibagikan.
  /// [isReceiver] untuk kirim barang: true = penerima yang bagi link, false = pengirim.
  /// Validasi: travel = bayar Lacak Driver; kirim barang = bayar Lacak Barang (pengirim/receiver sesuai role).
  static Future<String> generateShareUrl(OrderModel order, {bool isReceiver = false}) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw Exception('Belum login');

    if (order.status == OrderService.statusCompleted ||
        order.status == OrderService.statusCancelled) {
      throw Exception('Perjalanan sudah selesai. Link tidak dapat dibuat.');
    }

    if (order.driverUid.isEmpty) {
      throw Exception('Data driver tidak valid.');
    }

    if (order.isKirimBarang) {
      if (order.receiverScannedAt != null) {
        throw Exception('Barang sudah diterima. Link tidak dapat dibuat.');
      }
      if (isReceiver) {
        if (order.receiverLacakBarangPaidAt == null) {
          throw Exception('Bayar Lacak Barang dulu untuk membagikan link ke keluarga.');
        }
      } else {
        if (order.passengerLacakBarangPaidAt == null) {
          throw Exception('Bayar Lacak Barang dulu untuk membagikan link ke keluarga.');
        }
      }

      final passengerLat = order.passengerLat ?? order.originLat ?? 0.0;
      final passengerLng = order.passengerLng ?? order.originLng ?? 0.0;
      final receiverLat = order.receiverLat ?? order.destLat ?? 0.0;
      final receiverLng = order.receiverLng ?? order.destLng ?? 0.0;
      if (passengerLat == 0 && passengerLng == 0) {
        throw Exception('Lokasi pengirim tidak valid.');
      }
      if (receiverLat == 0 && receiverLng == 0) {
        throw Exception('Lokasi penerima tidak valid.');
      }

      final token = _randomToken();
      // passengerUid / receiverUid = pemilik peran di pesanan (bukan sekadar siapa yang mengetuk Bagikan).
      // Firestore rules mengizinkan create jika auth salah satu dari keduanya (kirim barang).
      final receiverUid = order.receiverUid ?? '';
      await FirebaseFirestore.instance.collection(_collection).doc(token).set({
        'orderId': order.id,
        'orderType': OrderModel.typeKirimBarang,
        'driverUid': order.driverUid,
        'originText': order.originText,
        'destText': order.destText,
        'orderNumber': order.orderNumber ?? order.id,
        'status': order.status,
        'passengerUid': order.passengerUid,
        'receiverUid': receiverUid,
        'passengerLat': passengerLat,
        'passengerLng': passengerLng,
        'receiverLat': receiverLat,
        'receiverLng': receiverLng,
        'passengerName': order.passengerName,
        'receiverName': order.receiverName ?? 'Penerima',
        'createdAt': FieldValue.serverTimestamp(),
      });

      return '$trackBaseUrl?t=$token';
    }

    // Travel
    final exempt = await ExemptionService.isCurrentUserLacakExempt();
    if (kLacakDriverPaymentRequired && !exempt && order.passengerTrackDriverPaidAt == null) {
      throw Exception('Bayar Lacak Driver dulu untuk membagikan link ke keluarga.');
    }

    final token = _randomToken();
    await FirebaseFirestore.instance.collection(_collection).doc(token).set({
      'orderId': order.id,
      'orderType': OrderModel.typeTravel,
      'driverUid': order.driverUid,
      'originText': order.originText,
      'destText': order.destText,
      'orderNumber': order.orderNumber ?? order.id,
      'status': order.status,
      'passengerUid': user.uid,
      'createdAt': FieldValue.serverTimestamp(),
    });

    return '$trackBaseUrl?t=$token';
  }
}
