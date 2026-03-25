import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../config/app_constants.dart';
import '../config/traka_api_config.dart';
import '../utils/retry_utils.dart';
import 'app_analytics_service.dart';
import 'directions_service.dart';
import 'driver_hybrid_diagnostics.dart';
import 'traka_api_service.dart';
import 'rating_service.dart';
import 'route_utils.dart';

/// Data driver dengan rute aktif (untuk penumpang memilih travel).
/// [driverLat], [driverLng]: posisi driver saat ini (untuk map & filter jarak).
/// [maxPassengers], [currentPassengerCount]: untuk warna icon mobil (nanti dari Data Mobil).
class ActiveDriverRoute {
  final String driverUid;
  final String routeJourneyNumber;
  final String routeOriginText;
  final String routeDestText;
  final double routeOriginLat;
  final double routeOriginLng;
  final double routeDestLat;
  final double routeDestLng;

  /// Posisi driver saat ini (dari driver_status).
  final double driverLat;
  final double driverLng;
  final String? driverName;
  final String? driverPhotoUrl;

  /// Kapasitas mobil (dari Data Mobil). Null = belum diisi, icon hijau.
  final int? maxPassengers;

  /// Jenis mobil / merek (dari data driver, users). Contoh: Toyota, Daihatsu.
  final String? vehicleMerek;

  /// Type mobil / model (dari data driver, users). Contoh: Avanza, Xenia.
  final String? vehicleType;

  /// Jumlah penumpang saat ini (dari orders agreed/picked_up). Null = 0.
  final int? currentPassengerCount;

  /// Timestamp terakhir update lokasi driver (dari driver_status.lastUpdated).
  /// Digunakan untuk menentukan apakah driver sedang bergerak.
  final DateTime? lastUpdated;

  /// Driver sudah verifikasi (SIM terverifikasi: driverSIMVerifiedAt atau driverSIMNomorHash ada di users).
  final bool isVerified;

  /// Rata-rata rating driver (1-5) dari order completed. Null jika belum ada rating.
  final double? averageRating;

  /// Jumlah review driver.
  final int reviewCount;

  /// Kategori rute dari jadwal driver: dalam_kota, antar_kabupaten, antar_provinsi, nasional.
  /// Null = driver dari Beranda (belum pilih kategori) atau data lama.
  final String? routeCategory;

  const ActiveDriverRoute({
    required this.driverUid,
    required this.routeJourneyNumber,
    required this.routeOriginText,
    required this.routeDestText,
    required this.routeOriginLat,
    required this.routeOriginLng,
    required this.routeDestLat,
    required this.routeDestLng,
    required this.driverLat,
    required this.driverLng,
    this.driverName,
    this.driverPhotoUrl,
    this.maxPassengers,
    this.vehicleMerek,
    this.vehicleType,
    this.currentPassengerCount,
    this.lastUpdated,
    this.isVerified = false,
    this.averageRating,
    this.reviewCount = 0,
    this.routeCategory,
  });

  /// Sisa kapasitas penumpang (hanya penumpang yang mengurangi; kirim barang tidak).
  /// Null jika maxPassengers belum diisi.
  int? get remainingPassengerCapacity {
    if (maxPassengers == null || maxPassengers! <= 0) return null;
    final current = currentPassengerCount ?? 0;
    final remaining = maxPassengers! - current;
    return remaining < 0 ? 0 : remaining;
  }

  /// True jika driver masih punya kursi untuk penumpang (untuk kategori penumpang).
  bool get hasPassengerCapacity {
    final r = remainingPassengerCapacity;
    return r != null && r > 0;
  }

  /// Apakah driver sedang bergerak berdasarkan waktu update terakhir.
  /// Jika update dalam threshold detik terakhir, dianggap sedang bergerak.
  /// Dipakai Cari Travel (penumpang). Driver update 1-2 detik saat jalan.
  bool get isMoving {
    if (lastUpdated == null) return false;
    final now = DateTime.now();
    final difference = now.difference(lastUpdated!);
    return difference.inSeconds <= AppConstants.penumpangIsMovingThresholdSeconds;
  }

}

/// Hasil [getActiveDriversForMapResult]: daftar driver + statistik kegagalan Directions per kandidat.
class ActiveDriversMapResult {
  const ActiveDriversMapResult({
    required this.drivers,
    this.routeCandidatesTotal = 0,
    this.skippedDirectionsEmpty = 0,
    this.skippedDirectionsError = 0,
  });

  final List<ActiveDriverRoute> drivers;
  /// Jumlah driver yang dicek di mode rute (sama dengan panjang daftar sebelum filter polyline).
  final int routeCandidatesTotal;
  final int skippedDirectionsEmpty;
  final int skippedDirectionsError;

  /// Semua kandidat gagal di [DirectionsService.getAlternativeRoutes] (kosong atau error), sehingga tidak ada yang lolos filter rute.
  bool get allCandidatesFailedAtDirections =>
      routeCandidatesTotal > 0 &&
      drivers.isEmpty &&
      skippedDirectionsEmpty + skippedDirectionsError == routeCandidatesTotal;
}

/// Service untuk daftar driver yang sedang siap kerja (ada rute aktif).
/// Dipakai penumpang untuk "Cari travel".
class ActiveDriversService {
  static const String _collectionDriverStatus = 'driver_status';
  static const String _collectionUsers = 'users';
  static const String _collectionVehicleData = 'vehicle_data';
  static const String _statusSiapKerja = 'siap_kerja';

  /// Maksimal usia lastUpdated (jam) agar driver dianggap aktif.
  /// Driver dengan lastUpdated > 6 jam dianggap tidak aktif (HP mati, sinyal putus).
  /// Disesuaikan untuk Kalimantan: jarak jauh, sinyal terbatas.
  static const int maxLastUpdatedHours = 6;

  /// Jarak maksimal (meter) driver dari titik penjemputan — mode «Driver sekitar» & lini dasar OD pendek.
  /// Untuk pencarian «searah» jarak jauh, dipakai nilai dari [_matchingParamsForPassengerOd].
  static const double maxDriverDistanceFromPickupMeters = 40000; // 40 km

  /// Plafon dokumen saat fallback Firestore untuk `siap_kerja` — cegah baca koleksi tanpa batas (mode degradasi).
  /// Diurutkan [lastUpdated] menurun agar subset memakai driver yang paling baru terlihat aktif (perlu indeks komposit).
  static const int _firestoreFallbackMaxDocs = 400;

  /// Radius «Driver sekitar» jika penumpang baru saja mencari rute jarak jauh (OD meter); memperluas jangkauan.
  static double nearbySearchRadiusMetersForPriorOd(double? priorPassengerOdMeters) {
    if (priorPassengerOdMeters == null || priorPassengerOdMeters < 30000) {
      return maxDriverDistanceFromPickupMeters;
    }
    if (priorPassengerOdMeters < 80000) return 55000;
    if (priorPassengerOdMeters < 150000) return 70000;
    return 85000;
  }

  static Future<({List<Map<String, dynamic>> list, bool hitCap})>
      _fetchDriverStatusFromFirestore() async {
    late final QuerySnapshot<Map<String, dynamic>> snapshot;
    try {
      snapshot = await FirebaseFirestore.instance
          .collection(_collectionDriverStatus)
          .where('status', isEqualTo: _statusSiapKerja)
          .orderBy('lastUpdated', descending: true)
          .limit(_firestoreFallbackMaxDocs)
          .get();
    } on FirebaseException catch (e) {
      if (e.code == 'failed-precondition') {
        if (kDebugMode) {
          debugPrint(
            'ActiveDriversService: firestore index missing (?), unordered siap_kerja fallback',
          );
        }
        snapshot = await FirebaseFirestore.instance
            .collection(_collectionDriverStatus)
            .where('status', isEqualTo: _statusSiapKerja)
            .limit(_firestoreFallbackMaxDocs)
            .get();
      } else {
        rethrow;
      }
    }
    final hitCap = snapshot.docs.length >= _firestoreFallbackMaxDocs;
    final list = snapshot.docs.map((doc) {
      final data = doc.data();
      data['uid'] = doc.id;
      return data;
    }).toList();
    return (list: list, hitCap: hitCap);
  }

  /// Daftar driver dengan rute aktif (status siap_kerja + ada data rute).
  /// Hanya driver yang lastUpdated dalam 6 jam terakhir (untuk filter HP mati/tidak aktif).
  /// maxPassengers dari vehicle_data; currentPassengerCount dari driver_status.
  ///
  /// [pickupLat], [pickupLng]: jika ada, coba GET /api/match/drivers dulu (Tahap 2).
  /// [city]: slug kota untuk matching (opsional).
  /// [radiusKm], [limit]: dinamis berdasarkan jarak asal–tujuan (opsional).
  /// Fallback: jika match kosong/error, pakai getDriverStatusList atau Firestore.
  static Future<List<ActiveDriverRoute>> getActiveDriverRoutes({
    double? pickupLat,
    double? pickupLng,
    double? matchDestLat,
    double? matchDestLng,
    String? city,
    double? radiusKm,
    int? limit,
  }) async =>
      RetryUtils.withRetry(
        () => _getActiveDriverRoutesImpl(
          pickupLat: pickupLat,
          pickupLng: pickupLng,
          matchDestLat: matchDestLat,
          matchDestLng: matchDestLng,
          city: city,
          radiusKm: radiusKm,
          limit: limit,
        ),
        maxAttempts: TrakaApiConfig.isApiEnabled ? 3 : 2,
        baseDelayMs: 1500,
      );

  static Future<List<ActiveDriverRoute>> _getActiveDriverRoutesImpl({
    double? pickupLat,
    double? pickupLng,
    double? matchDestLat,
    double? matchDestLng,
    String? city,
    double? radiusKm,
    int? limit,
  }) async {
    List<Map<String, dynamic>> driverStatusList = [];
    var activeDriversSource = 'firestore';
    String? activeDriversReason;
    var firestoreCapHit = false;

    if (TrakaApiConfig.isApiEnabled) {
      activeDriversSource = 'geo_match';
      if (pickupLat != null && pickupLng != null) {
        try {
          var matchList = await TrakaApiService.getMatchDrivers(
            lat: pickupLat,
            lng: pickupLng,
            destLat: matchDestLat,
            destLng: matchDestLng,
            city: city,
            radiusKm: radiusKm ?? 30,
            limit: limit ?? 50,
            minCapacity: 1,
          );
          // Driver GEO di Redis memakai slug kab/kota; query tanpa city memakai "default".
          // Bila penumpang dan driver beda bucket GEO, coba lagi tanpa slug (default).
          if (matchList.isEmpty &&
              city != null &&
              city.isNotEmpty) {
            matchList = await TrakaApiService.getMatchDrivers(
              lat: pickupLat,
              lng: pickupLng,
              destLat: matchDestLat,
              destLng: matchDestLng,
              city: null,
              radiusKm: radiusKm ?? 30,
              limit: limit ?? 50,
              minCapacity: 1,
            );
          }
          if (matchList.isNotEmpty) {
            driverStatusList = matchList;
            if (kDebugMode) debugPrint('ActiveDriversService: match API mengembalikan ${driverStatusList.length} driver');
          }
        } catch (e) {
          if (kDebugMode) debugPrint('ActiveDriversService: match API error, fallback: $e');
          activeDriversReason = 'match_error';
        }
      } else {
        activeDriversReason = 'no_pickup_coords';
        activeDriversSource = 'api_list';
      }
      if (driverStatusList.isEmpty) {
        activeDriversSource = 'api_list';
        try {
          driverStatusList = await TrakaApiService.getDriverStatusList();
          driverStatusList = driverStatusList
              .where((d) => (d['status'] as String?) == _statusSiapKerja)
              .toList();
        } catch (e) {
          if (kDebugMode) debugPrint('ActiveDriversService: API error, fallback Firestore: $e');
          activeDriversReason = activeDriversReason == null
              ? 'api_list_error'
              : '$activeDriversReason|api_list_error';
        }
      }
      if (driverStatusList.isEmpty) {
        if (kDebugMode) debugPrint('ActiveDriversService: API kosong, fallback ke Firestore');
        final fs = await _fetchDriverStatusFromFirestore();
        driverStatusList = fs.list;
        firestoreCapHit = fs.hitCap;
        activeDriversSource = 'firestore';
        activeDriversReason ??= 'exhausted_geo_and_api';
        if (firestoreCapHit) {
          activeDriversReason = '$activeDriversReason|fs_cap_hit';
          DriverHybridDiagnostics.breadcrumb(
            'passenger.activeDrivers.firestore_cap_hit limit=$_firestoreFallbackMaxDocs',
          );
        }
        DriverHybridDiagnostics.breadcrumb(
          'passenger.activeDrivers.firestore_fallback n=${driverStatusList.length}',
        );
        if (kDebugMode) debugPrint('ActiveDriversService: Firestore mengembalikan ${driverStatusList.length} driver');
      }
    } else {
      final fs = await _fetchDriverStatusFromFirestore();
      driverStatusList = fs.list;
      firestoreCapHit = fs.hitCap;
      activeDriversSource = 'firestore';
      activeDriversReason =
          firestoreCapHit ? 'hybrid_off|fs_cap_hit' : 'hybrid_off';
      if (firestoreCapHit) {
        DriverHybridDiagnostics.breadcrumb(
          'passenger.activeDrivers.firestore_cap_hit limit=$_firestoreFallbackMaxDocs',
        );
      }
    }

    AppAnalyticsService.logPassengerActiveDriversSource(
      source: activeDriversSource,
      reason: activeDriversReason,
      resultCount: driverStatusList.length,
      firestoreCapHit: firestoreCapHit,
    );

    final list = <ActiveDriverRoute>[];
    for (final d in driverStatusList) {
      final uid = (d['uid'] ?? d['driverUid']) as String? ?? '';
      final status = d['status'] as String?;
      if (status != _statusSiapKerja) continue;
      final originLat = (d['routeOriginLat'] as num?)?.toDouble();
      final originLng = (d['routeOriginLng'] as num?)?.toDouble();
      final destLat = (d['routeDestLat'] as num?)?.toDouble();
      final destLng = (d['routeDestLng'] as num?)?.toDouble();
      final driverLat = (d['latitude'] as num?)?.toDouble();
      final driverLng = (d['longitude'] as num?)?.toDouble();
      final journeyNumber = d['routeJourneyNumber'] as String?;
      final currentPassengerCount = (d['currentPassengerCount'] as num?)
          ?.toInt();
      DateTime? lastUpdated;
      final lastUpdatedRaw = d['lastUpdated'];
      if (lastUpdatedRaw is Timestamp) {
        lastUpdated = lastUpdatedRaw.toDate();
      } else if (lastUpdatedRaw is String) {
        lastUpdated = DateTime.tryParse(lastUpdatedRaw);
      }
      // Filter: driver dianggap tidak aktif jika lastUpdated > 6 jam (HP mati, sinyal putus)
      if (lastUpdated == null ||
          DateTime.now().difference(lastUpdated).inHours >= maxLastUpdatedHours) {
        continue;
      }
      if (originLat == null ||
          originLng == null ||
          destLat == null ||
          destLng == null ||
          driverLat == null ||
          driverLng == null ||
          journeyNumber == null ||
          journeyNumber.isEmpty) {
        continue;
      }

      String? driverName;
      String? driverPhotoUrl;
      bool isVerified = false;
      String? vehicleMerek;
      String? vehicleType;
      int? maxPassengers;
      try {
        final userDoc = await FirebaseFirestore.instance
            .collection(_collectionUsers)
            .doc(uid)
            .get();
        final userData = userDoc.data();
        driverName = userData?['displayName'] as String?;
        driverPhotoUrl = userData?['photoUrl'] as String?;
        isVerified =
            userData?['driverSIMVerifiedAt'] != null ||
            userData?['driverSIMNomorHash'] != null;
        // Data kendaraan dari data driver (users): jenis mobil, type mobil, kapasitas penumpang
        vehicleMerek = userData?['vehicleMerek'] as String?;
        vehicleType = userData?['vehicleType'] as String?;
        final jumlahPenumpang = userData?['vehicleJumlahPenumpang'] as num?;
        if (jumlahPenumpang != null) {
          final n = jumlahPenumpang.toInt();
          maxPassengers = n <= 0 ? null : n;
        }
      } catch (_) {}

      // Fallback: kapasitas dari vehicle_data jika belum ada di users
      if (maxPassengers == null) {
        try {
          final vehicleDoc = await FirebaseFirestore.instance
              .collection(_collectionVehicleData)
              .doc(uid)
              .get();
          final vehicleData = vehicleDoc.data();
          if (vehicleData != null &&
              (vehicleData['maxPassengers'] as num?) != null) {
            final n = (vehicleData['maxPassengers'] as num).toInt();
            maxPassengers = n <= 0 ? null : n;
          }
        } catch (_) {}
      }

      final routeCategory = d['routeCategory'] as String?;
      list.add(
        ActiveDriverRoute(
          driverUid: uid,
          routeJourneyNumber: journeyNumber,
          routeOriginText: (d['routeOriginText'] as String?) ?? '',
          routeDestText: (d['routeDestText'] as String?) ?? '',
          routeOriginLat: originLat,
          routeOriginLng: originLng,
          routeDestLat: destLat,
          routeDestLng: destLng,
          driverLat: driverLat,
          driverLng: driverLng,
          driverName: driverName,
          driverPhotoUrl: driverPhotoUrl,
          maxPassengers: maxPassengers,
          vehicleMerek: vehicleMerek,
          vehicleType: vehicleType,
          currentPassengerCount: currentPassengerCount,
          lastUpdated: lastUpdated,
          isVerified: isVerified,
          routeCategory: routeCategory,
        ),
      );
    }
    // Fetch ratings in parallel untuk semua driver
    final ratings = await Future.wait(
      list.map((r) async {
        final avg = await RatingService.getDriverAverageRating(r.driverUid);
        final count = await RatingService.getDriverReviewCount(r.driverUid);
        return (avg, count);
      }),
    );
    return [
      for (var i = 0; i < list.length; i++)
        ActiveDriverRoute(
          driverUid: list[i].driverUid,
          routeJourneyNumber: list[i].routeJourneyNumber,
          routeOriginText: list[i].routeOriginText,
          routeDestText: list[i].routeDestText,
          routeOriginLat: list[i].routeOriginLat,
          routeOriginLng: list[i].routeOriginLng,
          routeDestLat: list[i].routeDestLat,
          routeDestLng: list[i].routeDestLng,
          driverLat: list[i].driverLat,
          driverLng: list[i].driverLng,
          driverName: list[i].driverName,
          driverPhotoUrl: list[i].driverPhotoUrl,
          maxPassengers: list[i].maxPassengers,
          vehicleMerek: list[i].vehicleMerek,
          vehicleType: list[i].vehicleType,
          currentPassengerCount: list[i].currentPassengerCount,
          lastUpdated: list[i].lastUpdated,
          isVerified: list[i].isVerified,
          averageRating: ratings[i].$1,
          reviewCount: ratings[i].$2,
          routeCategory: list[i].routeCategory,
        ),
    ];
  }

  /// Driver yang cocok untuk ditampilkan di map penumpang.
  /// Logika luas (cross-route): pickup dan dropoff boleh di rute alternatif berbeda.
  /// Contoh: driver Batulicin-Banjarmasin (biru), penumpang Satui-Banjarbaru;
  /// Satui di rute biru, Banjarbaru di rute kuning → tetap match.
  /// Filter driver dalam radius dari center (mode «Driver sekitar»).
  /// [maxDistanceMeters] default [maxDriverDistanceFromPickupMeters].
  static List<ActiveDriverRoute> filterByDistanceFromCenter(
    List<ActiveDriverRoute> drivers,
    double centerLat,
    double centerLng, {
    double? maxDistanceMeters,
  }) {
    final maxD = maxDistanceMeters ?? maxDriverDistanceFromPickupMeters;
    return drivers.where((d) {
      final dist = Geolocator.distanceBetween(
        centerLat,
        centerLng,
        d.driverLat,
        d.driverLng,
      );
      return dist <= maxD;
    }).toList();
  }

  static ({double radiusKm, int limit}) _radiusLimitFromDistance(double distanceMeters) {
    if (distanceMeters < 30000) {
      return (radiusKm: 30, limit: 50);
    }
    if (distanceMeters < 80000) {
      return (radiusKm: 60, limit: 65);
    }
    return (radiusKm: 100, limit: 80);
  }

  /// Koridor polyline + jarak driver–jemput: diringkas untuk OD pendek, dilonggarkan untuk travel jauh
  /// (satu provinsi/kalimantan dll.) supaya titik jemput di pedesaan & driver di jalur utama tetap ketemu.
  static ({
    double pickupToleranceMeters,
    double dropoffToleranceMeters,
    double maxDriverFromPickupMeters,
    double maxMetersPastPickup,
  }) _matchingParamsForPassengerOd(double odMeters) {
    if (odMeters < 30000) {
      return (
        pickupToleranceMeters: RouteUtils.defaultToleranceMeters,
        dropoffToleranceMeters: RouteUtils.passengerDropoffToleranceMeters,
        maxDriverFromPickupMeters: maxDriverDistanceFromPickupMeters,
        maxMetersPastPickup: 5000,
      );
    }
    if (odMeters < 80000) {
      return (
        pickupToleranceMeters: 12000,
        dropoffToleranceMeters: 32000,
        maxDriverFromPickupMeters: 55000,
        maxMetersPastPickup: 8000,
      );
    }
    if (odMeters < 150000) {
      return (
        pickupToleranceMeters: 16000,
        dropoffToleranceMeters: 38000,
        maxDriverFromPickupMeters: 75000,
        maxMetersPastPickup: 12000,
      );
    }
    return (
      pickupToleranceMeters: 20000,
      dropoffToleranceMeters: 45000,
      maxDriverFromPickupMeters: 95000,
      maxMetersPastPickup: 15000,
    );
  }

  /// Peta penumpang «Cari travel»: filter driver `siap_kerja` yang **searah** dengan asal/tujuan penumpang.
  ///
  /// **Kebijakan OD + koridor (bukan satu polyline pilihan driver):**
  /// - Kunci operasional driver di `driver_status` = **asal & tujuan rute** (OD) + opsional `routeCategory`.
  /// - Garis biru/hijau yang dipilih driver di app hanya untuk navigasi; **matching** memanggil
  ///   Directions **alternatif** untuk OD yang sama, lalu cek apakah jemput & turun penumpang
  ///   masuk **koridor buffer** ke salah satu polyline itu ([RouteUtils.defaultToleranceMeters] /
  ///   [RouteUtils.passengerDropoffToleranceMeters]). Jadi jalan alternatif menuju tujuan akhir
  ///   yang sama tetap konsisten untuk pencarian.
  /// - Jika `alternatives` kosong, fallback satu rute [DirectionsService.getRoute] (tetap OD sama).
  /// - Dokumen: [AppConstants.matchingOdCorridorDocRelative] (folder `traka/`).
  ///
  /// Sama seperti [getActiveDriversForMap] tetapi menyertakan statistik Directions (untuk dialog fallback).
  ///
  /// [onlyDriversBeforePassenger]: jika true, driver harus belum melewati titik jemput; untuk OD ≥
  /// [AppConstants.passengerOdMetersRelaxDriverBeforePickupFilter] aturan ini **tidak dipakai** (travel jauh).
  static Future<ActiveDriversMapResult> getActiveDriversForMapResult({
    double? passengerOriginLat,
    double? passengerOriginLng,
    double? passengerDestLat,
    double? passengerDestLng,
    String? city,
    bool onlyDriversBeforePassenger = true,
  }) async {
    double? radiusKm;
    int? limit;
    if (passengerOriginLat != null &&
        passengerOriginLng != null &&
        passengerDestLat != null &&
        passengerDestLng != null) {
      final distM = Geolocator.distanceBetween(
        passengerOriginLat,
        passengerOriginLng,
        passengerDestLat,
        passengerDestLng,
      );
      final rl = _radiusLimitFromDistance(distM);
      radiusKm = rl.radiusKm;
      limit = rl.limit;
    }
    final all = await getActiveDriverRoutes(
      pickupLat: passengerOriginLat,
      pickupLng: passengerOriginLng,
      matchDestLat: passengerDestLat,
      matchDestLng: passengerDestLng,
      city: city,
      radiusKm: radiusKm,
      limit: limit,
    );
    if (all.isEmpty) {
      return ActiveDriversMapResult(drivers: const <ActiveDriverRoute>[]);
    }

    if (passengerOriginLat == null ||
        passengerOriginLng == null ||
        passengerDestLat == null ||
        passengerDestLng == null) {
      return ActiveDriversMapResult(drivers: all);
    }

    final passengerOrigin = LatLng(passengerOriginLat, passengerOriginLng);
    final passengerDest = LatLng(passengerDestLat, passengerDestLng);
    final odMeters = Geolocator.distanceBetween(
      passengerOriginLat,
      passengerOriginLng,
      passengerDestLat,
      passengerDestLng,
    );
    final matchParams = _matchingParamsForPassengerOd(odMeters);
    final enforceDriverBeforePickup = onlyDriversBeforePassenger &&
        odMeters < AppConstants.passengerOdMetersRelaxDriverBeforePickupFilter;
    final filtered = <ActiveDriverRoute>[];
    var skippedDirectionsEmpty = 0;
    var skippedDirectionsError = 0;

    for (final d in all) {
      try {
        var alternativeRoutes = await DirectionsService.getAlternativeRoutes(
          originLat: d.routeOriginLat,
          originLng: d.routeOriginLng,
          destLat: d.routeDestLat,
          destLng: d.routeDestLng,
        );

        if (alternativeRoutes.isEmpty) {
          final single = await DirectionsService.getRoute(
            originLat: d.routeOriginLat,
            originLng: d.routeOriginLng,
            destLat: d.routeDestLat,
            destLng: d.routeDestLng,
          );
          if (single != null && single.points.length >= 2) {
            alternativeRoutes = [single];
          }
        }

        if (alternativeRoutes.isEmpty) {
          skippedDirectionsEmpty++;
          continue;
        }

        final routePolylines = alternativeRoutes.map((r) => r.points).toList();
        final driverDest = LatLng(d.routeDestLat, d.routeDestLng);
        final driverOrigin = LatLng(d.routeOriginLat, d.routeOriginLng);

        // Jemput / turun: toleransi naik untuk OD jauh (lihat [_matchingParamsForPassengerOd]).
        final pickupNearAny = RouteUtils.isPointNearAnyRoute(
          passengerOrigin,
          routePolylines,
          toleranceMeters: matchParams.pickupToleranceMeters,
        );
        final dropoffNearAny = RouteUtils.isPointNearAnyRoute(
          passengerDest,
          routePolylines,
          toleranceMeters: matchParams.dropoffToleranceMeters,
        );

        if (!pickupNearAny || !dropoffNearAny) continue;

        if (!RouteUtils.isPickupBeforeDropoffByDistance(
          passengerOrigin,
          passengerDest,
          driverDest,
        )) {
          continue;
        }

        if (enforceDriverBeforePickup) {
          final driverPos = LatLng(d.driverLat, d.driverLng);
          final pickupRouteIdx = RouteUtils.findRouteIndexWithPoint(
            passengerOrigin,
            routePolylines,
            toleranceMeters: matchParams.pickupToleranceMeters,
          );
          bool driverOk = pickupRouteIdx >= 0 &&
              RouteUtils.isDriverBeforePointAlongRoute(
                driverPos,
                passengerOrigin,
                routePolylines[pickupRouteIdx],
                toleranceMeters: matchParams.pickupToleranceMeters,
              );
          if (!driverOk) {
            driverOk = RouteUtils.isDriverBeforePickupByDistance(
              driverPos,
              passengerOrigin,
              driverOrigin,
            );
          }
          if (!driverOk) {
            driverOk = RouteUtils.isDriverWithinXMetersPastPickup(
              driverPos,
              passengerOrigin,
              driverOrigin,
              maxMetersPast: matchParams.maxMetersPastPickup,
            );
          }
          if (!driverOk) continue;
        }

        final distToPickup = Geolocator.distanceBetween(
          passengerOriginLat,
          passengerOriginLng,
          d.driverLat,
          d.driverLng,
        );
        if (distToPickup > matchParams.maxDriverFromPickupMeters) continue;

        filtered.add(d);
      } catch (e) {
        skippedDirectionsError++;
        if (kDebugMode) {
          debugPrint(
            'ActiveDriversService.getActiveDriversForMap: Error cek rute untuk driver ${d.driverUid}: $e',
          );
        }
      }
    }

    filtered.sort((a, b) {
      final distA = Geolocator.distanceBetween(
        passengerOriginLat,
        passengerOriginLng,
        a.driverLat,
        a.driverLng,
      );
      final distB = Geolocator.distanceBetween(
        passengerOriginLat,
        passengerOriginLng,
        b.driverLat,
        b.driverLng,
      );
      return distA.compareTo(distB);
    });

    final out = filtered.take(AppConstants.maxDriversOnPassengerSearchMap).toList();
    return ActiveDriversMapResult(
      drivers: out,
      routeCandidatesTotal: all.length,
      skippedDirectionsEmpty: skippedDirectionsEmpty,
      skippedDirectionsError: skippedDirectionsError,
    );
  }

  static Future<List<ActiveDriverRoute>> getActiveDriversForMap({
    double? passengerOriginLat,
    double? passengerOriginLng,
    double? passengerDestLat,
    double? passengerDestLng,
    String? city,
    bool onlyDriversBeforePassenger = true,
  }) async {
    final r = await getActiveDriversForMapResult(
      passengerOriginLat: passengerOriginLat,
      passengerOriginLng: passengerOriginLng,
      passengerDestLat: passengerDestLat,
      passengerDestLng: passengerDestLng,
      city: city,
      onlyDriversBeforePassenger: onlyDriversBeforePassenger,
    );
    return r.drivers;
  }
}
