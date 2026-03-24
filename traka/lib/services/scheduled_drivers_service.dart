import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'geocoding_service.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import 'route_utils.dart';
import 'directions_service.dart';

/// Data driver dengan jadwal rute untuk tanggal tertentu.
class ScheduledDriverRoute {
  final String driverUid;
  final String scheduleOriginText;
  final String scheduleDestText;
  final double scheduleOriginLat;
  final double scheduleOriginLng;
  final double scheduleDestLat;
  final double scheduleDestLng;
  final DateTime scheduleDate;
  final DateTime departureTime;
  final String? driverName;
  final String? driverPhotoUrl;
  final int? maxPassengers;
  final String? vehicleMerek;
  final String? vehicleType;
  final bool isVerified;

  const ScheduledDriverRoute({
    required this.driverUid,
    required this.scheduleOriginText,
    required this.scheduleDestText,
    required this.scheduleOriginLat,
    required this.scheduleOriginLng,
    required this.scheduleDestLat,
    required this.scheduleDestLng,
    required this.scheduleDate,
    required this.departureTime,
    this.driverName,
    this.driverPhotoUrl,
    this.maxPassengers,
    this.vehicleMerek,
    this.vehicleType,
    this.isVerified = false,
  });
}

/// Service untuk mencari driver berdasarkan jadwal dengan logika rute yang melewati.
class ScheduledDriversService {
  static const String _collectionDriverSchedules = 'driver_schedules';
  static const String _collectionUsers = 'users';
  static const String _collectionVehicleData = 'vehicle_data';

  /// Dapatkan driver dengan jadwal yang: (1) provinsi sama (jika satu provinsi), (2) rute searah.
  /// [date]: Tanggal jadwal yang dicari.
  /// [passengerOriginLat/Lng]: Lokasi awal penumpang.
  /// [passengerDestLat/Lng]: Tujuan penumpang.
  /// [passengerOriginProvince/DestProvince]: Provinsi asal/tujuan penumpang; jika satu provinsi, hanya jadwal dengan provinsi yang sama yang dipertimbangkan.
  /// Rute driver harus searah: melewati lokasi asal penumpang lalu lokasi tujuan penumpang (bukan lawan arah).
  static Future<List<ScheduledDriverRoute>> getScheduledDriversForMap({
    required DateTime date,
    required double passengerOriginLat,
    required double passengerOriginLng,
    required double passengerDestLat,
    required double passengerDestLng,
    String? passengerOriginProvince,
    String? passengerDestProvince,
  }) async {
    try {
      // Ambil semua jadwal untuk tanggal tertentu
      final dateStart = DateTime(date.year, date.month, date.day);
      final snap = await FirebaseFirestore.instance
          .collection(_collectionDriverSchedules)
          .get();

      final allSchedules = <ScheduledDriverRoute>[];

      // Proses setiap driver dan jadwalnya
      for (final doc in snap.docs) {
        final driverUid = doc.id;
        final list = doc.data()['schedules'] as List<dynamic>?;
        if (list == null) continue;

        // Ambil info driver (nama, foto, dll) — user dan vehicle paralel
        String? driverName;
        String? driverPhotoUrl;
        bool isVerified = false;
        int? maxPassengers;
        String? vehicleMerek;
        String? vehicleType;

        try {
          final results = await Future.wait([
            FirebaseFirestore.instance
                .collection(_collectionUsers)
                .doc(driverUid)
                .get(),
            FirebaseFirestore.instance
                .collection(_collectionVehicleData)
                .doc(driverUid)
                .get(),
          ]);
          final userData = (results[0] as DocumentSnapshot).data() as Map<String, dynamic>?;
          final vehicleData = (results[1] as DocumentSnapshot).data() as Map<String, dynamic>?;
          driverName = userData?['displayName'] as String?;
          driverPhotoUrl = userData?['photoUrl'] as String?;
          isVerified =
              userData?['driverSIMVerifiedAt'] != null ||
              userData?['driverSIMNomorHash'] != null;
          vehicleMerek = userData?['vehicleMerek'] as String?;
          vehicleType = userData?['vehicleType'] as String?;
          final jumlahPenumpang = userData?['vehicleJumlahPenumpang'] as num?;
          if (jumlahPenumpang != null) {
            final n = jumlahPenumpang.toInt();
            maxPassengers = n <= 0 ? null : n;
          }
          if (maxPassengers == null &&
              vehicleData != null &&
              (vehicleData['maxPassengers'] as num?) != null) {
            final n = (vehicleData['maxPassengers'] as num).toInt();
            maxPassengers = n <= 0 ? null : n;
          }
        } catch (_) {}

        // Proses setiap jadwal driver
        for (final e in list) {
          final map = Map<String, dynamic>.from(e as Map<dynamic, dynamic>);
          final dateStamp = map['date'] as Timestamp?;
          if (dateStamp == null) continue;

          final scheduleDate = dateStamp.toDate();
          final scheduleDateOnly = DateTime(
            scheduleDate.year,
            scheduleDate.month,
            scheduleDate.day,
          );
          if (scheduleDateOnly != dateStart) continue;
          if (map['hiddenAt'] != null) continue;

          // Cek apakah jam keberangkatan sudah lewat (untuk jadwal hari ini)
          final todayStart = DateTime(
            DateTime.now().year,
            DateTime.now().month,
            DateTime.now().day,
          );
          if (scheduleDateOnly == todayStart) {
            final depStamp = map['departureTime'] as Timestamp?;
            if (depStamp != null &&
                depStamp.toDate().isBefore(DateTime.now())) {
              continue;
            }
          }

          final originText = (map['origin'] as String?)?.trim() ?? '';
          final destText = (map['destination'] as String?)?.trim() ?? '';
          if (originText.isEmpty || destText.isEmpty) continue;

          // Geocode origin dan destination paralel untuk mendapatkan koordinat
          try {
            final geoResults = await Future.wait([
              GeocodingService.locationFromAddress(
                '$originText, Indonesia',
                appendIndonesia: false,
              ),
              GeocodingService.locationFromAddress(
                '$destText, Indonesia',
                appendIndonesia: false,
              ),
            ]);
            final originLocations = geoResults[0];
            final destLocations = geoResults[1];

            if (originLocations.isEmpty || destLocations.isEmpty) continue;

            final originLat = originLocations.first.latitude;
            final originLng = originLocations.first.longitude;
            final destLat = destLocations.first.latitude;
            final destLng = destLocations.first.longitude;

            // Filter provinsi hanya bila penumpang cari dalam satu provinsi (asal = tujuan).
            // Kalau penumpang beda provinsi (asal X, tujuan Y) dan driver juga beda provinsi → tidak filter provinsi, cukup cek melewati.
            final pOrigin = (passengerOriginProvince ?? '').trim().toLowerCase();
            final pDest = (passengerDestProvince ?? '').trim().toLowerCase();
            final passengerSameProvince = pOrigin.isNotEmpty && pDest.isNotEmpty && pOrigin == pDest;
            final passengerOneProvinceOnly = (pOrigin.isNotEmpty && pDest.isEmpty) || (pOrigin.isEmpty && pDest.isNotEmpty);
            final hasProvinceFilter = (passengerSameProvince || passengerOneProvinceOnly);
            if (hasProvinceFilter) {
              try {
                final placemarkResults = await Future.wait([
                  GeocodingService.placemarkFromCoordinates(originLat, originLng),
                  GeocodingService.placemarkFromCoordinates(destLat, destLng),
                ]);
                final driverOriginPlacemarks = placemarkResults[0];
                final driverDestPlacemarks = placemarkResults[1];
                final driverOriginProvince = (driverOriginPlacemarks.isNotEmpty
                    ? (driverOriginPlacemarks.first.administrativeArea ?? '')
                    : '').trim().toLowerCase();
                final driverDestProvince = (driverDestPlacemarks.isNotEmpty
                    ? (driverDestPlacemarks.first.administrativeArea ?? '')
                    : '').trim().toLowerCase();
                final sameProvince = (pOrigin.isNotEmpty && (driverOriginProvince == pOrigin || driverDestProvince == pOrigin)) ||
                    (pDest.isNotEmpty && (driverOriginProvince == pDest || driverDestProvince == pDest));
                if (!sameProvince) continue;
              } catch (_) {
                continue;
              }
            }

            // Gunakan rute tersimpan (routePolyline) jika ada; else fetch alternatif dari API
            List<LatLng>? driverRoutePoints;
            final storedPolyline = map['routePolyline'] as List<dynamic>?;
            if (storedPolyline != null && storedPolyline.isNotEmpty) {
              driverRoutePoints = <LatLng>[];
              for (final e in storedPolyline) {
                final m = e as Map<dynamic, dynamic>?;
                if (m == null) continue;
                final lat = (m['lat'] as num?)?.toDouble();
                final lng = (m['lng'] as num?)?.toDouble();
                if (lat != null && lng != null) {
                  driverRoutePoints.add(LatLng(lat, lng));
                }
              }
              if (driverRoutePoints.isEmpty) driverRoutePoints = null;
            }

            bool passesThroughSameDirection = false;
            final passengerOrigin = LatLng(passengerOriginLat, passengerOriginLng);
            final passengerDest = LatLng(passengerDestLat, passengerDestLng);

            if (driverRoutePoints != null && driverRoutePoints.length >= 2) {
              // Rute tersimpan: cek hanya rute itu (selaras peta penumpang: jemput 10 km, turun 25 km)
              passesThroughSameDirection = RouteUtils.doesRoutePassThrough(
                driverRoutePoints,
                passengerOrigin,
                passengerDest,
                originToleranceMeters: RouteUtils.defaultToleranceMeters,
                destToleranceMeters: RouteUtils.passengerDropoffToleranceMeters,
              );
            } else {
              // Fallback: fetch alternatif, cek jika salah satu melewati
              final alternativeRoutes =
                  await DirectionsService.getAlternativeRoutes(
                    originLat: originLat,
                    originLng: originLng,
                    destLat: destLat,
                    destLng: destLng,
                  );
              for (final route in alternativeRoutes) {
                if (RouteUtils.doesRoutePassThrough(
                  route.points,
                  passengerOrigin,
                  passengerDest,
                  originToleranceMeters: RouteUtils.defaultToleranceMeters,
                  destToleranceMeters: RouteUtils.passengerDropoffToleranceMeters,
                )) {
                  passesThroughSameDirection = true;
                  break;
                }
              }
            }

            if (passesThroughSameDirection) {
              final depStamp = map['departureTime'] as Timestamp?;
              allSchedules.add(
                ScheduledDriverRoute(
                  driverUid: driverUid,
                  scheduleOriginText: originText,
                  scheduleDestText: destText,
                  scheduleOriginLat: originLat,
                  scheduleOriginLng: originLng,
                  scheduleDestLat: destLat,
                  scheduleDestLng: destLng,
                  scheduleDate: scheduleDate,
                  departureTime: depStamp?.toDate() ?? scheduleDate,
                  driverName: driverName,
                  driverPhotoUrl: driverPhotoUrl,
                  maxPassengers: maxPassengers,
                  vehicleMerek: vehicleMerek,
                  vehicleType: vehicleType,
                  isVerified: isVerified,
                ),
              );
            }
          } catch (e) {
            // Jika error geocode atau ambil polyline, skip jadwal ini
            if (kDebugMode) debugPrint(
              'ScheduledDriversService: Error proses jadwal untuk driver $driverUid: $e',
            );
            continue;
          }
        }
      }

      // Sort berdasarkan waktu keberangkatan (terdekat dulu)
      allSchedules.sort((a, b) {
        return a.departureTime.compareTo(b.departureTime);
      });

      // Tampilkan semua jadwal yang melewati (tanpa filter jarak atau limit)
      return allSchedules;
    } catch (e) {
      if (kDebugMode) debugPrint('ScheduledDriversService.getScheduledDriversForMap error: $e');
      return [];
    }
  }

  /// Rekomendasi jadwal: driver yang titik awal rutenya dekat lokasi penumpang.
  /// [forDate]: Tanggal yang dicari (default: hari ini).
  /// [passengerLat] [passengerLng]: Lokasi penumpang (GPS/riwayat).
  /// [maxRadiusMeters]: Jarak maks radius dari titik awal driver ke penumpang (default 50 km).
  /// [maxCount]: Maksimal jadwal (default 5, driver berbeda).
  static Future<List<ScheduledDriverRoute>> getRecommendedSchedulesForDate({
    required double passengerLat,
    required double passengerLng,
    DateTime? forDate,
    int maxRadiusMeters = 50000,
    int maxCount = 5,
  }) async {
    try {
      final now = DateTime.now();
      final target = forDate ?? now;
      final dateStart = DateTime(target.year, target.month, target.day);
      final snap = await FirebaseFirestore.instance
          .collection(_collectionDriverSchedules)
          .get();

      final candidates = <({ScheduledDriverRoute route, double distanceM})>[];

      for (final doc in snap.docs) {
        final driverUid = doc.id;
        final list = doc.data()['schedules'] as List<dynamic>?;
        if (list == null) continue;

        String? driverName;
        String? driverPhotoUrl;
        bool isVerified = false;
        int? maxPassengers;
        String? vehicleMerek;
        String? vehicleType;

        try {
          final results = await Future.wait([
            FirebaseFirestore.instance.collection(_collectionUsers).doc(driverUid).get(),
            FirebaseFirestore.instance.collection(_collectionVehicleData).doc(driverUid).get(),
          ]);
          final userData = (results[0] as DocumentSnapshot).data() as Map<String, dynamic>?;
          final vehicleData = (results[1] as DocumentSnapshot).data() as Map<String, dynamic>?;
          driverName = userData?['displayName'] as String?;
          driverPhotoUrl = userData?['photoUrl'] as String?;
          isVerified =
              userData?['driverSIMVerifiedAt'] != null ||
              userData?['driverSIMNomorHash'] != null;
          vehicleMerek = userData?['vehicleMerek'] as String?;
          vehicleType = userData?['vehicleType'] as String?;
          final jumlahPenumpang = userData?['vehicleJumlahPenumpang'] as num?;
          if (jumlahPenumpang != null) {
            final n = jumlahPenumpang.toInt();
            maxPassengers = n <= 0 ? null : n;
          }
          if (maxPassengers == null &&
              vehicleData != null &&
              (vehicleData['maxPassengers'] as num?) != null) {
            final n = (vehicleData['maxPassengers'] as num).toInt();
            maxPassengers = n <= 0 ? null : n;
          }
        } catch (_) {}

        for (final e in list) {
          final map = Map<String, dynamic>.from(e as Map<dynamic, dynamic>);
          final dateStamp = map['date'] as Timestamp?;
          if (dateStamp == null) continue;

          final scheduleDate = dateStamp.toDate();
          final scheduleDateOnly = DateTime(
            scheduleDate.year,
            scheduleDate.month,
            scheduleDate.day,
          );
          if (scheduleDateOnly != dateStart) continue;
          if (map['hiddenAt'] != null) continue;

          final depStamp = map['departureTime'] as Timestamp?;
          if (depStamp != null) {
            final dep = depStamp.toDate();
            if (scheduleDateOnly == DateTime(now.year, now.month, now.day) &&
                dep.isBefore(now)) continue;
          }

          final originText = (map['origin'] as String?)?.trim() ?? '';
          final destText = (map['destination'] as String?)?.trim() ?? '';
          if (originText.isEmpty || destText.isEmpty) continue;

          try {
            final originLocations = await GeocodingService.locationFromAddress(
              '$originText, Indonesia',
              appendIndonesia: false,
            );
            if (originLocations.isEmpty) continue;

            final originLat = originLocations.first.latitude;
            final originLng = originLocations.first.longitude;
            final distanceM = Geolocator.distanceBetween(
              passengerLat,
              passengerLng,
              originLat,
              originLng,
            );
            if (distanceM > maxRadiusMeters) continue;

            final destLocations = await GeocodingService.locationFromAddress(
              '$destText, Indonesia',
              appendIndonesia: false,
            );
            if (destLocations.isEmpty) continue;

            final destLat = destLocations.first.latitude;
            final destLng = destLocations.first.longitude;

            candidates.add((
              route: ScheduledDriverRoute(
                driverUid: driverUid,
                scheduleOriginText: originText,
                scheduleDestText: destText,
                scheduleOriginLat: originLat,
                scheduleOriginLng: originLng,
                scheduleDestLat: destLat,
                scheduleDestLng: destLng,
                scheduleDate: scheduleDate,
                departureTime: depStamp?.toDate() ?? scheduleDate,
                driverName: driverName,
                driverPhotoUrl: driverPhotoUrl,
                maxPassengers: maxPassengers,
                vehicleMerek: vehicleMerek,
                vehicleType: vehicleType,
                isVerified: isVerified,
              ),
              distanceM: distanceM,
            ));
          } catch (_) {
            continue;
          }
        }
      }

      candidates.sort((a, b) => a.distanceM.compareTo(b.distanceM));

      final seenDrivers = <String>{};
      final result = <ScheduledDriverRoute>[];
      for (final c in candidates) {
        if (seenDrivers.add(c.route.driverUid)) {
          result.add(c.route);
          if (result.length >= maxCount) break;
        }
      }
      return result;
    } catch (e) {
      if (kDebugMode) debugPrint('ScheduledDriversService.getRecommendedSchedulesForToday error: $e');
      return [];
    }
  }
}
