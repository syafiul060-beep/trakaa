import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../config/traka_api_config.dart';
import 'traka_api_service.dart';

/// Data rute kerja aktif dari Firestore (untuk restore saat app dibuka lagi).
class DriverActiveRouteData {
  final double originLat;
  final double originLng;
  final double destLat;
  final double destLng;
  final String originText;
  final String destText;
  final String? routeJourneyNumber;
  final DateTime? routeStartedAt;
  final int? estimatedDurationSeconds;
  final bool routeFromJadwal;

  /// Index rute alternatif yang dipilih (0, 1, 2, ...).
  final int routeSelectedIndex;

  /// ID jadwal yang sedang dijalankan (pesanan terjadwal). Hanya terisi jika routeFromJadwal true.
  final String? scheduleId;

  const DriverActiveRouteData({
    required this.originLat,
    required this.originLng,
    required this.destLat,
    required this.destLng,
    required this.originText,
    required this.destText,
    this.routeJourneyNumber,
    this.routeStartedAt,
    this.estimatedDurationSeconds,
    this.routeFromJadwal = false,
    this.routeSelectedIndex = 0,
    this.scheduleId,
  });
}

/// Service untuk update status dan lokasi driver ke Firestore.
/// Driver yang aktif (status "siap_kerja" dengan rute) akan terlihat oleh penumpang yang mencari travel.
class DriverStatusService {
  static const String _collectionDriverStatus = 'driver_status';

  /// Status driver: "siap_kerja" = sedang kerja (ada rute), "tidak_aktif" = tidak kerja.
  static const String statusSiapKerja = 'siap_kerja';
  static const String statusTidakAktif = 'tidak_aktif';

  /// Jarak minimal perpindahan (meter) untuk update lokasi otomatis.
  /// 2 km: hemat Firestore writes & baterai, tetap cukup untuk tracking.
  static const double minDistanceToUpdateMeters = 2000; // 2 km

  /// Interval waktu maksimal (menit) untuk update lokasi paksa (meskipun tidak pindah jauh).
  static const int maxMinutesForceUpdate = 15; // 15 menit

  /// Untuk live tracking (driver menuju jemput): update lebih sering ala Gojek/Grab.
  static const double minDistanceLiveTrackingMeters = 50; // 50 m
  static const int maxSecondsLiveTracking = 5; // 5 detik (jemput penumpang)

  /// Hemat write: ada penumpang agreed menunggu jemput, tapi driver belum tap arahkan / lacak penuh.
  /// Cukup untuk notifikasi jarak ~1 km / 500 m tanpa spam seperti live tracking 50 m.
  static const double minDistancePickupProximityMeters = 300;
  static const int maxSecondsPickupProximity = 60;

  /// Update status driver ke Firestore.
  /// [status]: "siap_kerja" atau "tidak_aktif"
  /// [position]: posisi driver saat ini (lat, lng)
  /// [routeOrigin]: titik awal rute (jika ada)
  /// [routeDestination]: titik tujuan rute (jika ada)
  /// [routeOriginText]: teks lokasi awal rute
  /// [routeDestinationText]: teks lokasi tujuan rute
  /// [routeJourneyNumber]: nomor rute perjalanan (unik, terisi otomatis)
  /// [routeStartedAt]: waktu mulai rute (tanggal dan hari)
  /// [estimatedDurationSeconds]: estimasi waktu perjalanan (detik), untuk auto-end
  /// [currentPassengerCount]: jumlah penumpang agreed/picked_up untuk rute ini (untuk warna icon mobil)
  /// [routeSelectedIndex]: index rute alternatif yang dipilih (0, 1, 2, ...)
  /// [scheduleId]: ID jadwal yang dijalankan (untuk pesanan terjadwal); dipakai saat routeFromJadwal true.
  /// [routeCategory]: kategori rute (dalam_kota, antar_kabupaten, antar_provinsi, nasional).
  /// [city]: slug kota/kabupaten untuk GEO matching (#9). Dari subAdministrativeArea.
  /// [maxPassengers]: kapasitas mobil untuk filter matching (Tahap 4.2). Dari users.vehicleJumlahPenumpang.
  static Future<void> updateDriverStatus({
    required String status,
    required Position position,
    LatLng? routeOrigin,
    LatLng? routeDestination,
    String? routeOriginText,
    String? routeDestinationText,
    String? routeJourneyNumber,
    DateTime? routeStartedAt,
    int? estimatedDurationSeconds,
    int? currentPassengerCount,
    bool routeFromJadwal = false,
    int routeSelectedIndex = 0,
    String? scheduleId,
    String? routeCategory,
    String? city,
    int? maxPassengers,
    String? routeOriginKabKey,
    String? routeDestKabKey,
    String? routeOriginProvKey,
    String? routeDestProvKey,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final data = <String, dynamic>{
      'uid': user.uid,
      'status': status,
      'latitude': position.latitude,
      'longitude': position.longitude,
      'lastUpdated': FieldValue.serverTimestamp(),
    };

    if (currentPassengerCount != null) {
      data['currentPassengerCount'] = currentPassengerCount;
    }

    // Jika driver siap kerja (ada rute), simpan info rute + nomor rute perjalanan
    if (status == statusSiapKerja &&
        routeOrigin != null &&
        routeDestination != null) {
      data['routeOriginLat'] = routeOrigin.latitude;
      data['routeOriginLng'] = routeOrigin.longitude;
      data['routeDestLat'] = routeDestination.latitude;
      data['routeDestLng'] = routeDestination.longitude;
      data['routeOriginText'] = routeOriginText ?? '';
      data['routeDestText'] = routeDestinationText ?? '';
      data['routeFromJadwal'] = routeFromJadwal;
      data['routeSelectedIndex'] = routeSelectedIndex >= 0
          ? routeSelectedIndex
          : 0;
      if (routeJourneyNumber != null) {
        data['routeJourneyNumber'] = routeJourneyNumber;
      }
      if (scheduleId != null && scheduleId.isNotEmpty) {
        data['scheduleId'] = scheduleId;
      }
      if (routeStartedAt != null) {
        data['routeStartedAt'] = Timestamp.fromDate(routeStartedAt);
      }
      if (estimatedDurationSeconds != null) {
        data['estimatedDurationSeconds'] = estimatedDurationSeconds;
      }
      if (routeCategory != null && routeCategory.isNotEmpty) {
        data['routeCategory'] = routeCategory;
      }
      if (routeOriginKabKey != null && routeOriginKabKey.isNotEmpty) {
        data['routeOriginKabKey'] = routeOriginKabKey;
      } else {
        data['routeOriginKabKey'] = null;
      }
      if (routeDestKabKey != null && routeDestKabKey.isNotEmpty) {
        data['routeDestKabKey'] = routeDestKabKey;
      } else {
        data['routeDestKabKey'] = null;
      }
      if (routeOriginProvKey != null && routeOriginProvKey.isNotEmpty) {
        data['routeOriginProvKey'] = routeOriginProvKey;
      } else {
        data['routeOriginProvKey'] = null;
      }
      if (routeDestProvKey != null && routeDestProvKey.isNotEmpty) {
        data['routeDestProvKey'] = routeDestProvKey;
      } else {
        data['routeDestProvKey'] = null;
      }
    } else {
      // Jika tidak aktif, hapus info rute
      data['routeOriginLat'] = null;
      data['routeOriginLng'] = null;
      data['routeDestLat'] = null;
      data['routeDestLng'] = null;
      data['routeOriginText'] = null;
      data['routeDestText'] = null;
      data['routeJourneyNumber'] = null;
      data['routeStartedAt'] = null;
      data['estimatedDurationSeconds'] = null;
      data['currentPassengerCount'] = null;
      data['routeFromJadwal'] = null;
      data['routeSelectedIndex'] = null;
      data['scheduleId'] = null;
      data['routeCategory'] = null;
      data['routeOriginKabKey'] = null;
      data['routeDestKabKey'] = null;
      data['routeOriginProvKey'] = null;
      data['routeDestProvKey'] = null;
    }

    if (TrakaApiConfig.isApiEnabled) {
      final apiBody = <String, dynamic>{
        'latitude': position.latitude,
        'longitude': position.longitude,
        'status': status,
        if (currentPassengerCount != null) 'currentPassengerCount': currentPassengerCount,
        if (city != null && city.isNotEmpty) 'city': city,
        if (maxPassengers != null && maxPassengers > 0) 'maxPassengers': maxPassengers,
      };
      if (status == statusSiapKerja &&
          routeOrigin != null &&
          routeDestination != null) {
        apiBody['routeOriginLat'] = routeOrigin.latitude;
        apiBody['routeOriginLng'] = routeOrigin.longitude;
        apiBody['routeDestLat'] = routeDestination.latitude;
        apiBody['routeDestLng'] = routeDestination.longitude;
        apiBody['routeOriginText'] = routeOriginText ?? '';
        apiBody['routeDestText'] = routeDestinationText ?? '';
        apiBody['routeFromJadwal'] = routeFromJadwal;
        apiBody['routeSelectedIndex'] = routeSelectedIndex >= 0 ? routeSelectedIndex : 0;
        if (routeJourneyNumber != null) apiBody['routeJourneyNumber'] = routeJourneyNumber;
        if (scheduleId != null && scheduleId.isNotEmpty) apiBody['scheduleId'] = scheduleId;
        if (routeStartedAt != null) apiBody['routeStartedAt'] = routeStartedAt.toIso8601String();
        if (estimatedDurationSeconds != null) apiBody['estimatedDurationSeconds'] = estimatedDurationSeconds;
        if (routeCategory != null && routeCategory.isNotEmpty) apiBody['routeCategory'] = routeCategory;
        if (routeOriginKabKey != null && routeOriginKabKey.isNotEmpty) {
          apiBody['routeOriginKabKey'] = routeOriginKabKey;
        }
        if (routeDestKabKey != null && routeDestKabKey.isNotEmpty) {
          apiBody['routeDestKabKey'] = routeDestKabKey;
        }
        if (routeOriginProvKey != null && routeOriginProvKey.isNotEmpty) {
          apiBody['routeOriginProvKey'] = routeOriginProvKey;
        }
        if (routeDestProvKey != null && routeDestProvKey.isNotEmpty) {
          apiBody['routeDestProvKey'] = routeDestProvKey;
        }
      }
      await TrakaApiService.postDriverLocation(apiBody);
      // Firestore tetap memakai koordinat [position] di [data]. Redis (hybrid) di server
      // memakai titik ter-snap Roads; jangan timpa Firestore dengan snap agar konsisten
      // dengan GPS perangkat untuk tampilan driver & pembaca Firestore langsung.
      // Dual-write ke Firestore: penumpang non-hybrid bisa tetap menemukan driver
      await FirebaseFirestore.instance
          .collection(_collectionDriverStatus)
          .doc(user.uid)
          .set(data, SetOptions(merge: true));
    } else {
      await FirebaseFirestore.instance
          .collection(_collectionDriverStatus)
          .doc(user.uid)
          .set(data, SetOptions(merge: true));
    }
  }

  /// Update hanya currentPassengerCount (dipanggil saat daftar pesanan berubah).
  /// Tahap 4.1: API support PATCH partial update.
  static Future<void> updateCurrentPassengerCount(int count) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    if (TrakaApiConfig.isApiEnabled) {
      await TrakaApiService.patchDriverStatus(currentPassengerCount: count);
    }
    await FirebaseFirestore.instance
        .collection(_collectionDriverStatus)
        .doc(user.uid)
        .set({'currentPassengerCount': count}, SetOptions(merge: true));
  }

  /// Cek apakah perlu update lokasi berdasarkan jarak dan waktu.
  /// Mengembalikan true jika harus update (pindah >= 2 km atau sudah >= 15 menit sejak update terakhir).
  static bool shouldUpdateLocation({
    required Position currentPosition,
    Position? lastUpdatedPosition,
    DateTime? lastUpdatedTime,
  }) {
    // Jika belum pernah update, harus update
    if (lastUpdatedPosition == null || lastUpdatedTime == null) {
      return true;
    }

    // Cek jarak perpindahan
    final distance = Geolocator.distanceBetween(
      lastUpdatedPosition.latitude,
      lastUpdatedPosition.longitude,
      currentPosition.latitude,
      currentPosition.longitude,
    );

    // Jika pindah >= 2 km, update
    if (distance >= minDistanceToUpdateMeters) {
      return true;
    }

    // Cek waktu sejak update terakhir
    final minutesSinceLastUpdate = DateTime.now()
        .difference(lastUpdatedTime)
        .inMinutes;

    // Jika sudah >= 15 menit, update paksa (meskipun tidak pindah jauh)
    if (minutesSinceLastUpdate >= maxMinutesForceUpdate) {
      return true;
    }

    return false;
  }

  /// Cek apakah perlu update lokasi untuk live tracking (penumpang Lacak Driver).
  /// Lebih sering: pindah >= 50 m atau sudah >= [maxSecondsLiveTracking] detik.
  static bool shouldUpdateLocationForLiveTracking({
    required Position currentPosition,
    Position? lastUpdatedPosition,
    DateTime? lastUpdatedTime,
  }) {
    if (lastUpdatedPosition == null || lastUpdatedTime == null) return true;
    final distance = Geolocator.distanceBetween(
      lastUpdatedPosition.latitude,
      lastUpdatedPosition.longitude,
      currentPosition.latitude,
      currentPosition.longitude,
    );
    if (distance >= minDistanceLiveTrackingMeters) return true;
    final secondsSince = DateTime.now().difference(lastUpdatedTime).inSeconds;
    if (secondsSince >= maxSecondsLiveTracking) return true;
    return false;
  }

  /// Update lokasi untuk notifikasi jarak penumpang (agreed, belum jemput) — lebih jarang dari live tracking.
  static bool shouldUpdateLocationForPickupProximity({
    required Position currentPosition,
    Position? lastUpdatedPosition,
    DateTime? lastUpdatedTime,
  }) {
    if (lastUpdatedPosition == null || lastUpdatedTime == null) return true;
    final distance = Geolocator.distanceBetween(
      lastUpdatedPosition.latitude,
      lastUpdatedPosition.longitude,
      currentPosition.latitude,
      currentPosition.longitude,
    );
    if (distance >= minDistancePickupProximityMeters) return true;
    final secondsSince = DateTime.now().difference(lastUpdatedTime).inSeconds;
    if (secondsSince >= maxSecondsPickupProximity) return true;
    return false;
  }

  /// Hapus status driver (ketika logout atau selesai bekerja).
  static Future<void> removeDriverStatus() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    if (TrakaApiConfig.isApiEnabled) {
      await TrakaApiService.deleteDriverStatus();
    }
    // Hapus dari Firestore (dual-write: hybrid juga tulis Firestore)
    await FirebaseFirestore.instance
        .collection(_collectionDriverStatus)
        .doc(user.uid)
        .delete();
  }

  /// Parse map status driver (JSON API) menjadi [DriverActiveRouteData], atau null.
  static DriverActiveRouteData? _driverActiveRouteFromApiMap(Map<String, dynamic>? data) {
    if (data == null) return null;
    final status = data['status'] as String?;
    if (status != statusSiapKerja) return null;
    final originLat = (data['routeOriginLat'] as num?)?.toDouble();
    final originLng = (data['routeOriginLng'] as num?)?.toDouble();
    final destLat = (data['routeDestLat'] as num?)?.toDouble();
    final destLng = (data['routeDestLng'] as num?)?.toDouble();
    if (originLat == null || originLng == null || destLat == null || destLng == null) {
      return null;
    }
    final routeStartedAtStr = data['routeStartedAt'] as String?;
    final estSec = (data['estimatedDurationSeconds'] as num?)?.toInt();
    final fromJadwal = data['routeFromJadwal'] as bool? ?? false;
    final selectedIndex = (data['routeSelectedIndex'] as num?)?.toInt() ?? 0;
    final scheduleId = data['scheduleId'] as String?;
    DateTime? routeStartedAt;
    if (routeStartedAtStr != null) {
      routeStartedAt = DateTime.tryParse(routeStartedAtStr);
    }
    return DriverActiveRouteData(
      originLat: originLat,
      originLng: originLng,
      destLat: destLat,
      destLng: destLng,
      originText: (data['routeOriginText'] as String?) ?? '',
      destText: (data['routeDestText'] as String?) ?? '',
      routeJourneyNumber: data['routeJourneyNumber'] as String?,
      routeStartedAt: routeStartedAt,
      estimatedDurationSeconds: estSec,
      routeFromJadwal: fromJadwal,
      routeSelectedIndex: selectedIndex >= 0 ? selectedIndex : 0,
      scheduleId: scheduleId,
    );
  }

  /// Ambil rute kerja aktif driver dari Firestore/API (jika status siap_kerja + ada data rute).
  /// Dipanggil saat app dibuka untuk restore rute yang masih aktif.
  static Future<DriverActiveRouteData?> getActiveRouteFromFirestore() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return null;

    if (TrakaApiConfig.isApiEnabled) {
      final data = await TrakaApiService.getDriverStatus(user.uid);
      final fromApi = _driverActiveRouteFromApiMap(data);
      if (fromApi != null) return fromApi;
      // API kosong / belum sinkron — dual-write Firestore masih bisa punya rute lengkap.
    }

    final doc = await FirebaseFirestore.instance
        .collection(_collectionDriverStatus)
        .doc(user.uid)
        .get();

    if (!doc.exists) return null;
    final data = doc.data();
    if (data == null) return null;

    final status = data['status'] as String?;
    if (status != statusSiapKerja) return null;

    final originLat = data['routeOriginLat'] as num?;
    final originLng = data['routeOriginLng'] as num?;
    final destLat = data['routeDestLat'] as num?;
    final destLng = data['routeDestLng'] as num?;
    if (originLat == null ||
        originLng == null ||
        destLat == null ||
        destLng == null) {
      return null;
    }

    final startedAt = data['routeStartedAt'] as Timestamp?;
    final estSec = data['estimatedDurationSeconds'] as num?;
    final fromJadwal = data['routeFromJadwal'] as bool?;
    final selectedIndex = data['routeSelectedIndex'] as num?;
    final scheduleId = data['scheduleId'] as String?;

    return DriverActiveRouteData(
      originLat: originLat.toDouble(),
      originLng: originLng.toDouble(),
      destLat: destLat.toDouble(),
      destLng: destLng.toDouble(),
      originText: (data['routeOriginText'] as String?) ?? '',
      destText: (data['routeDestText'] as String?) ?? '',
      routeJourneyNumber: data['routeJourneyNumber'] as String?,
      routeStartedAt: startedAt?.toDate(),
      estimatedDurationSeconds: estSec?.toInt(),
      routeFromJadwal: fromJadwal ?? false,
      routeSelectedIndex: selectedIndex != null && selectedIndex.toInt() >= 0
          ? selectedIndex.toInt()
          : 0,
      scheduleId: scheduleId,
    );
  }

  /// Stream posisi driver (lat, lng) dari driver_status. Untuk "Cek lokasi driver" oleh pengirim/penerima.
  static Stream<(double, double)?> streamDriverPosition(String driverUid) {
    if (TrakaApiConfig.isApiEnabled) {
      return TrakaApiService.streamDriverStatus(driverUid).map((data) {
        if (data == null) return null;
        final lat = (data['latitude'] as num?)?.toDouble();
        final lng = (data['longitude'] as num?)?.toDouble();
        if (lat == null || lng == null) return null;
        return (lat, lng);
      });
    }
    return FirebaseFirestore.instance
        .collection(_collectionDriverStatus)
        .doc(driverUid)
        .snapshots()
        .map((doc) {
      if (!doc.exists) return null;
      final d = doc.data();
      if (d == null) return null;
      final lat = (d['latitude'] as num?)?.toDouble();
      final lng = (d['longitude'] as num?)?.toDouble();
      if (lat == null || lng == null) return null;
      return (lat, lng);
    });
  }

  /// Fetch status driver sekali (untuk tombol Refresh di Lacak Driver/Barang).
  static Future<Map<String, dynamic>?> fetchDriverStatusOnce(String driverUid) async {
    if (TrakaApiConfig.isApiEnabled) {
      return TrakaApiService.getDriverStatus(driverUid);
    }
    final doc = await FirebaseFirestore.instance
        .collection(_collectionDriverStatus)
        .doc(driverUid)
        .get();
    return doc.exists ? doc.data() : null;
  }

  /// Stream data driver status (untuk Lacak Driver/Barang). Mengembalikan Map atau null.
  static Stream<Map<String, dynamic>?> streamDriverStatusData(String driverUid) {
    if (TrakaApiConfig.isApiEnabled) {
      return TrakaApiService.streamDriverStatus(driverUid);
    }
    return FirebaseFirestore.instance
        .collection(_collectionDriverStatus)
        .doc(driverUid)
        .snapshots()
        .map((doc) {
      if (!doc.exists) return null;
      return doc.data();
    });
  }
}
