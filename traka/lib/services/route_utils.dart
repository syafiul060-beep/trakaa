import 'dart:math' show cos, sin, atan2;

import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

/// Utility functions untuk operasi rute dan polyline.
class RouteUtils {
  /// Toleransi jarak untuk mengecek apakah titik berada di dekat polyline (dalam meter).
  /// Default: 10 km = 10000 meter.
  static const double defaultToleranceMeters = 10000;

  /// Hitung jarak terdekat dari suatu titik ke polyline (dalam meter).
  /// Menggunakan algoritma untuk mencari jarak minimum dari titik ke setiap segmen garis.
  static double distanceToPolyline(LatLng point, List<LatLng> polyline) {
    if (polyline.isEmpty) return double.infinity;
    if (polyline.length == 1) {
      return Geolocator.distanceBetween(
        point.latitude,
        point.longitude,
        polyline.first.latitude,
        polyline.first.longitude,
      );
    }

    double minDistance = double.infinity;
    for (int i = 0; i < polyline.length - 1; i++) {
      final p1 = polyline[i];
      final p2 = polyline[i + 1];
      final distance = _distanceToLineSegment(point, p1, p2);
      if (distance < minDistance) {
        minDistance = distance;
      }
    }
    return minDistance;
  }

  /// Proyeksi titik GPS ke polyline (snap to road).
  /// Returns (titik terdekat di jalan, segmentIndex, ratio dalam segmen 0..1).
  /// Jika polyline kosong, return (point, -1, 0).
  /// [maxDistanceMeters]: jika GPS lebih jauh dari jalan, return point asli (tidak snap).
  static (LatLng point, int segmentIndex, double ratio) projectPointOntoPolyline(
    LatLng point,
    List<LatLng> polyline, {
    double maxDistanceMeters = 80,
  }) {
    if (polyline.isEmpty) return (point, -1, 0.0);
    if (polyline.length == 1) {
      return (polyline.first, 0, 0.0);
    }

    double minDist = double.infinity;
    LatLng bestPoint = point;
    int bestSegment = 0;
    double bestRatio = 0.0;

    for (int i = 0; i < polyline.length - 1; i++) {
      final p1 = polyline[i];
      final p2 = polyline[i + 1];
      final (proj, t) = _projectOntoSegment(point, p1, p2);
      final d = Geolocator.distanceBetween(
        point.latitude,
        point.longitude,
        proj.latitude,
        proj.longitude,
      );
      if (d < minDist) {
        minDist = d;
        bestPoint = proj;
        bestSegment = i;
        bestRatio = t.clamp(0.0, 1.0);
      }
    }
    if (minDist > maxDistanceMeters) return (point, -1, 0.0);
    return (bestPoint, bestSegment, bestRatio);
  }

  /// Proyeksi titik ke segmen garis. Returns (titik terdekat, t 0..1).
  static (LatLng point, double t) _projectOntoSegment(
    LatLng point,
    LatLng lineStart,
    LatLng lineEnd,
  ) {
    final dx = lineEnd.longitude - lineStart.longitude;
    final dy = lineEnd.latitude - lineStart.latitude;
    if (dx == 0 && dy == 0) {
      return (lineStart, 0.0);
    }
    final px = point.longitude - lineStart.longitude;
    final py = point.latitude - lineStart.latitude;
    final t = ((px * dx) + (py * dy)) / ((dx * dx) + (dy * dy));
    final clampedT = t.clamp(0.0, 1.0);
    final lat = lineStart.latitude + clampedT * dy;
    final lng = lineStart.longitude + clampedT * dx;
    return (LatLng(lat, lng), clampedT);
  }

  /// Titik baru dari (lat, lng) dengan bearing (derajat) dan jarak (meter).
  /// Untuk offset kamera head unit: target di depan mobil agar mobil tampil di bawah.
  static LatLng offsetPoint(LatLng from, double bearingDegrees, double distanceMeters) {
    const toRad = 3.14159265359 / 180;
    const toDeg = 180 / 3.14159265359;
    final lat1 = from.latitude * toRad;
    final brng = bearingDegrees * toRad;
    final d = distanceMeters / 111320; // ~111320 m per degree lat
    final lat2Rad = lat1 + d * cos(brng);
    final lng2 = from.longitude + (d * sin(brng)) / cos(lat1);
    return LatLng(lat2Rad * toDeg, lng2);
  }

  /// Bearing (derajat 0-360) dari titik A ke B. 0=utara, 90=timur, 180=selatan, 270=barat.
  static double bearingBetween(LatLng from, LatLng to) {
    const toRad = 3.14159265359 / 180;
    const toDeg = 180 / 3.14159265359;
    final lat1 = from.latitude * toRad;
    final lat2 = to.latitude * toRad;
    final dLng = (to.longitude - from.longitude) * toRad;
    final x = cos(lat2) * sin(dLng);
    final y = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLng);
    final bearing = (atan2(x, y) * toDeg + 360) % 360;
    return bearing;
  }

  /// Bearing dari posisi sepanjang polyline (arah perjalanan). Untuk icon/kamera rotasi.
  /// [point]: posisi saat ini (bisa hasil projectPointOntoPolyline).
  /// [polyline]: rute jalan.
  /// [segmentIndex], [ratio]: dari projectPointOntoPolyline. Jika -1, hitung dari point.
  /// Returns bearing 0-360 atau 0 jika tidak bisa dihitung.
  static double computeBearingFromPolyline(
    LatLng point,
    List<LatLng> polyline, {
    int segmentIndex = -1,
    double ratio = 0,
  }) {
    if (polyline.isEmpty || polyline.length < 2) return 0;
    int seg = segmentIndex;
    if (seg < 0) {
      final proj = projectPointOntoPolyline(point, polyline, maxDistanceMeters: 150);
      seg = proj.$2;
      if (seg < 0) return 0;
    }
    if (seg >= polyline.length - 1) {
      final p1 = polyline[polyline.length - 2];
      final p2 = polyline.last;
      return bearingBetween(p1, p2);
    }
    final p1 = polyline[seg];
    final p2 = polyline[seg + 1];
    return bearingBetween(p1, p2);
  }

  /// Posisi di polyline dari (segmentIndex, ratio). ratio 0=awal segmen, 1=akhir.
  static LatLng getPointOnPolyline(
    List<LatLng> polyline,
    int segmentIndex,
    double ratio,
  ) {
    if (polyline.isEmpty) return const LatLng(0, 0);
    if (polyline.length == 1) return polyline.first;
    final i = segmentIndex.clamp(0, polyline.length - 2);
    final r = ratio.clamp(0.0, 1.0);
    final p1 = polyline[i];
    final p2 = polyline[i + 1];
    return LatLng(
      p1.latitude + (p2.latitude - p1.latitude) * r,
      p1.longitude + (p2.longitude - p1.longitude) * r,
    );
  }

  /// Interpolasi sepanjang polyline dari (segA, ratioA) ke (segB, ratioB).
  /// progress 0..1. Returns posisi di jalan (mengikuti alur jalan).
  static LatLng interpolateAlongPolyline(
    List<LatLng> polyline,
    int segA,
    double ratioA,
    int segB,
    double ratioB,
    double progress,
  ) {
    if (polyline.isEmpty || polyline.length == 1) {
      return polyline.isNotEmpty ? polyline.first : const LatLng(0, 0);
    }
    final p = progress.clamp(0.0, 1.0);
    if (p <= 0) return getPointOnPolyline(polyline, segA, ratioA);
    if (p >= 1) return getPointOnPolyline(polyline, segB, ratioB);

    final distA = _cumulativeDistanceToSegment(polyline, segA) + ratioA * _segmentLength(polyline, segA);
    final distB = _cumulativeDistanceToSegment(polyline, segB) + ratioB * _segmentLength(polyline, segB);
    final distStart = distA < distB ? distA : distB;
    final distEnd = distA < distB ? distB : distA;
    final totalDist = distStart + (distEnd - distStart) * p;
    return _pointAtDistance(polyline, totalDist);
  }

  static double _segmentLength(List<LatLng> polyline, int segIndex) {
    if (segIndex < 0 || segIndex >= polyline.length - 1) return 0;
    final p1 = polyline[segIndex];
    final p2 = polyline[segIndex + 1];
    return Geolocator.distanceBetween(p1.latitude, p1.longitude, p2.latitude, p2.longitude);
  }

  static double _cumulativeDistanceToSegment(List<LatLng> polyline, int segIndex) {
    double sum = 0;
    for (int i = 0; i < segIndex && i < polyline.length - 1; i++) {
      sum += _segmentLength(polyline, i);
    }
    return sum;
  }

  /// Jarak (meter) dari awal polyline ke posisi (segmentIndex, ratio).
  /// Untuk deteksi step aktif saat turn-by-turn.
  static double distanceAlongPolyline(
    List<LatLng> polyline,
    int segmentIndex,
    double ratio,
  ) {
    if (polyline.isEmpty || polyline.length < 2) return 0;
    if (segmentIndex < 0) return 0;
    final cum = _cumulativeDistanceToSegment(polyline, segmentIndex);
    final segLen = _segmentLength(polyline, segmentIndex);
    return cum + (ratio.clamp(0.0, 1.0) * segLen);
  }

  /// Titik di polyline X meter di depan posisi. Untuk target kamera (head unit).
  /// Selalu mengikuti rute jalan, tidak pakai bearing—menghindari kamera mengarah ke laut.
  /// Returns null jika posisi tidak di dekat rute.
  static LatLng? pointAheadOnPolyline(
    LatLng from,
    List<LatLng> polyline,
    double distanceMeters, {
    double maxDistanceMeters = 150,
  }) {
    if (polyline.isEmpty || polyline.length < 2) return null;
    final (_, seg, ratio) = projectPointOntoPolyline(
      from,
      polyline,
      maxDistanceMeters: maxDistanceMeters,
    );
    if (seg < 0) return null;
    final distFromStart = distanceAlongPolyline(polyline, seg, ratio);
    final totalLength = distanceAlongPolyline(
      polyline,
      polyline.length - 2,
      1.0,
    );
    final distAhead = distFromStart + distanceMeters;
    if (distAhead >= totalLength) return polyline.last;
    return _pointAtDistance(polyline, distAhead);
  }

  static LatLng _pointAtDistance(List<LatLng> polyline, double distanceMeters) {
    if (polyline.isEmpty) return const LatLng(0, 0);
    if (polyline.length == 1) return polyline.first;
    double acc = 0;
    for (int i = 0; i < polyline.length - 1; i++) {
      final len = _segmentLength(polyline, i);
      if (acc + len >= distanceMeters) {
        final ratio = (distanceMeters - acc) / len;
        return getPointOnPolyline(polyline, i, ratio);
      }
      acc += len;
    }
    return polyline.last;
  }

  /// Segment index di posisi distanceMeters sepanjang polyline. Untuk bearing.
  static int _segmentIndexAtDistance(List<LatLng> polyline, double distanceMeters) {
    if (polyline.isEmpty || polyline.length < 2) return 0;
    double acc = 0;
    for (int i = 0; i < polyline.length - 1; i++) {
      final len = _segmentLength(polyline, i);
      if (acc + len >= distanceMeters) return i;
      acc += len;
    }
    return polyline.length - 2;
  }

  /// Bearing di posisi distanceMeters sepanjang polyline (arah perjalanan).
  static double bearingAtDistance(List<LatLng> polyline, double distanceMeters) {
    if (polyline.isEmpty || polyline.length < 2) return 0;
    final seg = _segmentIndexAtDistance(polyline, distanceMeters);
    return bearingBetween(polyline[seg], polyline[seg + 1]);
  }

  /// Interpolasi + bearing. Returns (point, bearing) untuk kamera/icon rotasi.
  static (LatLng point, double bearing) interpolateWithBearing(
    List<LatLng> polyline,
    int segA,
    double ratioA,
    int segB,
    double ratioB,
    double progress,
  ) {
    final point = interpolateAlongPolyline(polyline, segA, ratioA, segB, ratioB, progress);
    final distA = _cumulativeDistanceToSegment(polyline, segA) + ratioA * _segmentLength(polyline, segA);
    final distB = _cumulativeDistanceToSegment(polyline, segB) + ratioB * _segmentLength(polyline, segB);
    final distStart = distA < distB ? distA : distB;
    final distEnd = distA < distB ? distB : distA;
    final totalDist = distStart + (distEnd - distStart) * progress.clamp(0.0, 1.0);
    final bearing = bearingAtDistance(polyline, totalDist);
    return (point, bearing);
  }

  /// Hitung jarak dari titik ke segmen garis (dalam meter).
  /// Menggunakan proyeksi ortogonal untuk mencari titik terdekat pada segmen.
  static double _distanceToLineSegment(
    LatLng point,
    LatLng lineStart,
    LatLng lineEnd,
  ) {
    // Vektor dari start ke end
    final dx = lineEnd.longitude - lineStart.longitude;
    final dy = lineEnd.latitude - lineStart.latitude;

    // Jika segmen adalah titik tunggal
    if (dx == 0 && dy == 0) {
      return Geolocator.distanceBetween(
        point.latitude,
        point.longitude,
        lineStart.latitude,
        lineStart.longitude,
      );
    }

    // Vektor dari start ke point
    final px = point.longitude - lineStart.longitude;
    final py = point.latitude - lineStart.latitude;

    // Proyeksi skalar
    final t = ((px * dx) + (py * dy)) / ((dx * dx) + (dy * dy));

    // Clamp t ke [0, 1] untuk memastikan titik berada di segmen
    final clampedT = t.clamp(0.0, 1.0);

    // Titik terdekat pada segmen
    final closestLat = lineStart.latitude + clampedT * dy;
    final closestLng = lineStart.longitude + clampedT * dx;

    // Jarak dari point ke titik terdekat
    return Geolocator.distanceBetween(
      point.latitude,
      point.longitude,
      closestLat,
      closestLng,
    );
  }

  /// Cek apakah suatu titik berada di dekat polyline (dalam toleransi tertentu).
  /// [toleranceMeters]: Jarak toleransi dalam meter. Default: 10 km.
  static bool isPointNearPolyline(
    LatLng point,
    List<LatLng> polyline, {
    double toleranceMeters = defaultToleranceMeters,
  }) {
    if (polyline.isEmpty) return false;
    final distance = distanceToPolyline(point, polyline);
    return distance <= toleranceMeters;
  }

  /// Cek apakah rute driver melewati lokasi awal dan tujuan penumpang.
  /// Driver ditampilkan jika:
  /// - Rute driver melewati lokasi awal penumpang (dalam toleransi)
  /// - Rute driver melewati lokasi tujuan penumpang (dalam toleransi)
  /// [driverRoutePolyline]: Polyline rute driver (dari origin ke destination).
  /// [passengerOrigin]: Lokasi awal penumpang.
  /// [passengerDest]: Lokasi tujuan penumpang.
  /// [toleranceMeters]: Toleransi jarak dalam meter. Default: 10 km.
  static bool doesRoutePassThrough(
    List<LatLng> driverRoutePolyline,
    LatLng passengerOrigin,
    LatLng passengerDest, {
    double toleranceMeters = defaultToleranceMeters,
  }) {
    if (driverRoutePolyline.isEmpty) return false;

    // Cek apakah rute melewati lokasi awal penumpang
    final passesOrigin = isPointNearPolyline(
      passengerOrigin,
      driverRoutePolyline,
      toleranceMeters: toleranceMeters,
    );

    // Cek apakah rute melewati lokasi tujuan penumpang
    final passesDest = isPointNearPolyline(
      passengerDest,
      driverRoutePolyline,
      toleranceMeters: toleranceMeters,
    );

    // Jika rute melewati kedua titik, cek urutan: origin harus sebelum dest
    if (passesOrigin && passesDest) {
      return _isOriginBeforeDest(
        driverRoutePolyline,
        passengerOrigin,
        passengerDest,
        toleranceMeters: toleranceMeters,
      );
    }

    return false;
  }

  /// Cek apakah lokasi awal muncul sebelum lokasi tujuan dalam polyline.
  /// Ini memastikan bahwa rute benar-benar melewati kedua titik dalam urutan yang benar.
  static bool _isOriginBeforeDest(
    List<LatLng> polyline,
    LatLng origin,
    LatLng dest, {
    double toleranceMeters = defaultToleranceMeters,
  }) {
    int originIndex = -1;
    int destIndex = -1;

    // Cari indeks terdekat untuk origin dan dest
    double minOriginDist = double.infinity;
    double minDestDist = double.infinity;

    for (int i = 0; i < polyline.length; i++) {
      final point = polyline[i];
      final originDist = Geolocator.distanceBetween(
        origin.latitude,
        origin.longitude,
        point.latitude,
        point.longitude,
      );
      final destDist = Geolocator.distanceBetween(
        dest.latitude,
        dest.longitude,
        point.latitude,
        point.longitude,
      );

      if (originDist < minOriginDist && originDist <= toleranceMeters) {
        minOriginDist = originDist;
        originIndex = i;
      }
      if (destDist < minDestDist && destDist <= toleranceMeters) {
        minDestDist = destDist;
        destIndex = i;
      }
    }

    // Origin harus muncul sebelum dest dalam polyline
    return originIndex >= 0 && destIndex >= 0 && originIndex < destIndex;
  }

  /// Indeks posisi titik sepanjang polyline (titik polyline terdekat dalam toleransi).
  /// Untuk cek "driver belum melewati penumpang": driverIndex < passengerOriginIndex.
  static int getIndexAlongPolyline(
    LatLng point,
    List<LatLng> polyline, {
    double toleranceMeters = defaultToleranceMeters,
  }) {
    if (polyline.isEmpty) return -1;
    int bestIndex = -1;
    double minDist = double.infinity;
    for (int i = 0; i < polyline.length; i++) {
      final p = polyline[i];
      final d = Geolocator.distanceBetween(
        point.latitude,
        point.longitude,
        p.latitude,
        p.longitude,
      );
      if (d < minDist && d <= toleranceMeters) {
        minDist = d;
        bestIndex = i;
      }
    }
    return bestIndex;
  }

  /// Cek apakah posisi driver belum melewati titik penumpang sepanjang rute.
  static bool isDriverBeforePointAlongRoute(
    LatLng driverPosition,
    LatLng passengerPoint,
    List<LatLng> routePolyline, {
    double toleranceMeters = defaultToleranceMeters,
  }) {
    final driverIdx = getIndexAlongPolyline(
      driverPosition,
      routePolyline,
      toleranceMeters: toleranceMeters,
    );
    final passengerIdx = getIndexAlongPolyline(
      passengerPoint,
      routePolyline,
      toleranceMeters: toleranceMeters,
    );
    return driverIdx >= 0 && passengerIdx >= 0 && driverIdx < passengerIdx;
  }

  /// Cek apakah titik dekat dengan salah satu rute dari daftar polyline.
  /// Untuk cross-route matching: pickup dan dropoff boleh di rute berbeda.
  static bool isPointNearAnyRoute(
    LatLng point,
    List<List<LatLng>> routes, {
    double toleranceMeters = defaultToleranceMeters,
  }) {
    for (final route in routes) {
      if (isPointNearPolyline(point, route, toleranceMeters: toleranceMeters)) {
        return true;
      }
    }
    return false;
  }

  /// Cek urutan perjalanan: pickup sebelum dropoff berdasarkan jarak ke tujuan driver.
  /// Pickup lebih jauh dari tujuan = driver melewati pickup dulu, baru dropoff.
  static bool isPickupBeforeDropoffByDistance(
    LatLng pickup,
    LatLng dropoff,
    LatLng driverDest,
  ) {
    final distPickupToDest = Geolocator.distanceBetween(
      pickup.latitude,
      pickup.longitude,
      driverDest.latitude,
      driverDest.longitude,
    );
    final distDropoffToDest = Geolocator.distanceBetween(
      dropoff.latitude,
      dropoff.longitude,
      driverDest.latitude,
      driverDest.longitude,
    );
    return distPickupToDest > distDropoffToDest;
  }

  /// Cek apakah posisi driver belum melewati titik penjemputan (berdasarkan jarak dari origin).
  /// Driver lebih dekat ke origin = belum sampai pickup.
  static bool isDriverBeforePickupByDistance(
    LatLng driverPosition,
    LatLng pickup,
    LatLng driverOrigin,
  ) {
    final distDriverToOrigin = Geolocator.distanceBetween(
      driverPosition.latitude,
      driverPosition.longitude,
      driverOrigin.latitude,
      driverOrigin.longitude,
    );
    final distPickupToOrigin = Geolocator.distanceBetween(
      pickup.latitude,
      pickup.longitude,
      driverOrigin.latitude,
      driverOrigin.longitude,
    );
    return distDriverToOrigin < distPickupToOrigin;
  }

  /// Cek apakah driver sudah melewati pickup tapi masih dalam jarak [maxMetersPast] meter.
  /// Untuk menampilkan driver yang baru saja lewat titik penjemputan (masih bisa putar balik/detour).
  static bool isDriverWithinXMetersPastPickup(
    LatLng driverPosition,
    LatLng pickup,
    LatLng driverOrigin, {
    double maxMetersPast = 10000,
  }) {
    final distDriverToOrigin = Geolocator.distanceBetween(
      driverPosition.latitude,
      driverPosition.longitude,
      driverOrigin.latitude,
      driverOrigin.longitude,
    );
    final distPickupToOrigin = Geolocator.distanceBetween(
      pickup.latitude,
      pickup.longitude,
      driverOrigin.latitude,
      driverOrigin.longitude,
    );
    if (distDriverToOrigin <= distPickupToOrigin) return false; // Belum lewat
    final distDriverToPickup = Geolocator.distanceBetween(
      driverPosition.latitude,
      driverPosition.longitude,
      pickup.latitude,
      pickup.longitude,
    );
    return distDriverToPickup <= maxMetersPast;
  }

  /// Cari rute yang melewati titik (untuk cek driver sebelum pickup).
  /// Returns index rute atau -1 jika tidak ada.
  static int findRouteIndexWithPoint(
    LatLng point,
    List<List<LatLng>> routes, {
    double toleranceMeters = defaultToleranceMeters,
  }) {
    for (int i = 0; i < routes.length; i++) {
      if (isPointNearPolyline(point, routes[i], toleranceMeters: toleranceMeters)) {
        return i;
      }
    }
    return -1;
  }

  /// Cek apakah posisi driver berada di dekat salah satu rute alternatif.
  /// Digunakan untuk auto-switch rute.
  /// [driverPosition]: Posisi driver saat ini.
  /// [alternativeRoutes]: List rute alternatif (polyline).
  /// [toleranceMeters]: Toleransi jarak dalam meter. Default: 10 km.
  /// Returns: Index rute yang terdekat jika dalam toleransi, atau -1 jika tidak ada.
  static int findNearestRouteIndex(
    LatLng driverPosition,
    List<List<LatLng>> alternativeRoutes, {
    double toleranceMeters = defaultToleranceMeters,
  }) {
    int nearestIndex = -1;
    double minDistance = double.infinity;

    for (int i = 0; i < alternativeRoutes.length; i++) {
      final route = alternativeRoutes[i];
      final distance = distanceToPolyline(driverPosition, route);
      if (distance < minDistance && distance <= toleranceMeters) {
        minDistance = distance;
        nearestIndex = i;
      }
    }

    return nearestIndex;
  }
}
