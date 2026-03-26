import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:rxdart/rxdart.dart';

import 'route_session_service.dart';

/// Kontribusi driver: driver wajib bayar kontribusi per rute, kirim barang, dan pelanggaran.
const bool kContributionEnabled = true;

/// Status kontribusi driver: wajib bayar jika ada rute belum lunas / barang / pelanggaran.
/// Trigger: selesai rute perjalanan (bukan 1× kapasitas mobil).
class DriverContributionStatus {
  final int unpaidTravelRupiah;
  final int totalBarangContributionRupiah;
  final int contributionBarangPaidUpToRupiah;
  final double outstandingViolationFee;
  final bool mustPayContribution;
  final int contributionTravelRupiah;
  final int contributionBarangRupiah;
  final int totalRupiah;
  final List<RouteSessionModel> unpaidRouteSessions;

  const DriverContributionStatus({
    required this.unpaidTravelRupiah,
    required this.totalBarangContributionRupiah,
    required this.contributionBarangPaidUpToRupiah,
    required this.outstandingViolationFee,
    required this.mustPayContribution,
    required this.contributionTravelRupiah,
    required this.contributionBarangRupiah,
    required this.totalRupiah,
    this.unpaidRouteSessions = const [],
  });

  /// Unpaid kirim barang contribution (Rp).
  int get unpaidBarangRupiah =>
      (totalBarangContributionRupiah - contributionBarangPaidUpToRupiah).clamp(0, 0x7FFFFFFF);
}

/// Service untuk cek status kontribusi driver (per rute + kirim barang + pelanggaran).
class DriverContributionService {
  static const String _collectionUsers = 'users';

  /// Stream status kontribusi driver. Trigger: rute belum lunas (bukan 1× kapasitas).
  static Stream<DriverContributionStatus> streamContributionStatus() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return Stream.value(
        const DriverContributionStatus(
          unpaidTravelRupiah: 0,
          totalBarangContributionRupiah: 0,
          contributionBarangPaidUpToRupiah: 0,
          outstandingViolationFee: 0,
          mustPayContribution: false,
          contributionTravelRupiah: 0,
          contributionBarangRupiah: 0,
          totalRupiah: 0,
        ),
      );
    }

    final routeStream = RouteSessionService.streamUnpaidRouteSessionsForDriver();
    final userStream = FirebaseFirestore.instance
        .collection(_collectionUsers)
        .doc(user.uid)
        .snapshots();

    return Rx.combineLatest2<List<RouteSessionModel>, DocumentSnapshot,
        DriverContributionStatus>(
      routeStream,
      userStream,
      (unpaidSessions, userDoc) {
        final unpaidTravel = unpaidSessions.fold<int>(
          0,
          (running, s) => running + s.contributionRupiah,
        );
        final d = userDoc.data() as Map<String, dynamic>?;
        final totalBarang = (d?['totalBarangContributionRupiah'] as num?)?.toInt() ?? 0;
        final barangPaidUp = (d?['contributionBarangPaidUpToRupiah'] as num?)?.toInt() ?? 0;
        final violationFee = (d?['outstandingViolationFee'] as num?)?.toDouble() ?? 0.0;

        final unpaidBarang = (totalBarang - barangPaidUp).clamp(0, 0x7FFFFFFF);
        final mustPayTravel = kContributionEnabled && unpaidTravel > 0;
        final mustPayBarang = unpaidBarang > 0;
        final mustPayViolation = violationFee > 0;
        final mustPay = mustPayTravel || mustPayBarang || mustPayViolation;

        final contributionTravelRupiah = unpaidTravel;
        final contributionBarangRupiah = unpaidBarang;
        final violationRupiah = violationFee.round();
        final totalRupiah = contributionTravelRupiah + contributionBarangRupiah + violationRupiah;

        return DriverContributionStatus(
          unpaidTravelRupiah: unpaidTravel,
          totalBarangContributionRupiah: totalBarang,
          contributionBarangPaidUpToRupiah: barangPaidUp,
          outstandingViolationFee: violationFee,
          mustPayContribution: mustPay,
          contributionTravelRupiah: contributionTravelRupiah,
          contributionBarangRupiah: contributionBarangRupiah,
          totalRupiah: totalRupiah,
          unpaidRouteSessions: unpaidSessions,
        );
      },
    );
  }

  /// Panggil Cloud Function untuk verifikasi pembayaran gabungan (kontribusi + pelanggaran).
  static Future<Map<String, dynamic>> verifyContributionPayment({
    required String purchaseToken,
    required String orderId,
    String? productId,
    String? packageName,
  }) async {
    final functions = FirebaseFunctions.instance;
    final callable = functions.httpsCallable('verifyContributionPayment');
    final result = await callable.call<Map<String, dynamic>>({
      'purchaseToken': purchaseToken,
      'orderId': orderId,
      if (productId != null) 'productId': productId,
      if (packageName != null) 'packageName': packageName,
    });
    return result.data;
  }
}
