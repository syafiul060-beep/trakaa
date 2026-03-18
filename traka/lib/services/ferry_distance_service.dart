import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';

import '../config/province_island.dart';
import 'lacak_barang_service.dart';

/// Status driver di kapal laut (untuk Lacak Barang).
class FerryStatus {
  final bool isOnFerry;
  final DateTime? etaPortAt;
  final String? routeLabel;

  const FerryStatus({
    required this.isOnFerry,
    this.etaPortAt,
    this.routeLabel,
  });
}

/// Estimasi jarak kapal laut (km) antar pulau untuk pengurangan kontribusi.
class FerryDistanceService {
  static const String _collection = 'app_config';
  static const String _docId = 'ferry_distances';

  /// Jarak ferry default (km) per pasangan pulau. Key: "pulau1_pulau2" (alfabetis).
  static const Map<String, int> _defaultFerryKm = {
    'Bali & Nusa Tenggara_Jawa': 3,      // Gilimanuk-Ketapang
    'Jawa_Sumatera': 25,                 // Merak-Bakauheni
    'Jawa_Kalimantan': 400,
    'Jawa_Sulawesi': 500,
    'Kalimantan_Sumatera': 100,
    'Kalimantan_Sulawesi': 300,
    'Bali & Nusa Tenggara_Sulawesi': 350,
    'Maluku_Papua': 200,
    'Maluku_Sulawesi': 400,
    'Sumatera_Maluku': 800,
    'Papua_Sulawesi': 600,
  };

  static String _islandPairKey(String a, String b) {
    final list = [a, b]..sort();
    return '${list[0]}_${list[1]}';
  }

  /// Estimasi jarak kapal (km) jika asal dan tujuan beda pulau. Null jika sama pulau.
  static Future<double?> getEstimatedFerryKm({
    required double originLat,
    required double originLng,
    required double destLat,
    required double destLng,
  }) async {
    final originProvince = await LacakBarangService.getProvinceFromLatLng(
      originLat,
      originLng,
    );
    final destProvince = await LacakBarangService.getProvinceFromLatLng(
      destLat,
      destLng,
    );
    if (originProvince == null || destProvince == null) return null;

    final originIsland = ProvinceIsland.getIslandForProvince(originProvince);
    final destIsland = ProvinceIsland.getIslandForProvince(destProvince);
    if (originIsland == null || destIsland == null) return null;
    if (originIsland == destIsland) return null;

    final key = _islandPairKey(originIsland, destIsland);

    try {
      final doc = await FirebaseFirestore.instance
          .collection(_collection)
          .doc(_docId)
          .get();
      if (doc.exists && doc.data() != null) {
        final v = doc.data()![key];
        if (v != null) {
          final n = (v is num) ? v.toInt() : int.tryParse(v.toString());
          if (n != null && n >= 0) return n.toDouble();
        }
      }
    } catch (_) {}

    return (_defaultFerryKm[key] ?? 300).toDouble();
  }

  /// Durasi ferry default (jam) per pasangan pulau.
  static const Map<String, double> _defaultFerryDurationHours = {
    'Bali & Nusa Tenggara_Jawa': 0.5,
    'Jawa_Sumatera': 2.0,
    'Jawa_Kalimantan': 24.0,
    'Jawa_Sulawesi': 36.0,
    'Kalimantan_Sumatera': 12.0,
    'Kalimantan_Sulawesi': 18.0,
    'Bali & Nusa Tenggara_Sulawesi': 20.0,
    'Maluku_Papua': 12.0,
    'Maluku_Sulawesi': 24.0,
    'Sumatera_Maluku': 48.0,
    'Papua_Sulawesi': 36.0,
  };

  static const double _detectionRadiusKm = 25.0;
  static const double _minRouteKm = 40.0;

  /// Cek apakah driver sedang di kapal laut (inferensi geometris).
  /// Return FerryStatus. Jika tidak di kapal, isOnFerry = false.
  static Future<FerryStatus> checkDriverOnFerry({
    required double originLat,
    required double originLng,
    required double destLat,
    required double destLng,
    required double driverLat,
    required double driverLng,
  }) async {
    final originProvince = await LacakBarangService.getProvinceFromLatLng(
      originLat,
      originLng,
    );
    final destProvince = await LacakBarangService.getProvinceFromLatLng(
      destLat,
      destLng,
    );
    if (originProvince == null || destProvince == null) {
      return const FerryStatus(isOnFerry: false);
    }

    final originIsland = ProvinceIsland.getIslandForProvince(originProvince);
    final destIsland = ProvinceIsland.getIslandForProvince(destProvince);
    if (originIsland == null || destIsland == null || originIsland == destIsland) {
      return const FerryStatus(isOnFerry: false);
    }

    final totalKm = _haversineKm(originLat, originLng, destLat, destLng);
    if (totalKm < _minRouteKm) return const FerryStatus(isOnFerry: false);

    final midLat = (originLat + destLat) / 2;
    final midLng = (originLng + destLng) / 2;
    final distToMid = _haversineKm(driverLat, driverLng, midLat, midLng);
    if (distToMid > _detectionRadiusKm) return const FerryStatus(isOnFerry: false);

    final key = _islandPairKey(originIsland, destIsland);
    double durationHours = _defaultFerryDurationHours[key] ?? 2.0;
    try {
      final doc = await FirebaseFirestore.instance
          .collection(_collection)
          .doc(_docId)
          .get();
      if (doc.exists && doc.data() != null) {
        final durations = doc.data()!['durations'] as Map<String, dynamic>?;
        final v = durations?[key];
        if (v != null) {
          final n = (v is num) ? v.toDouble() : double.tryParse(v.toString());
          if (n != null && n > 0) durationHours = n;
        }
      }
    } catch (_) {}

    // Asumsi driver di tengah perjalanan ferry → sisa durasi = 50%
    final etaPortAt = DateTime.now().add(
      Duration(minutes: (durationHours * 0.5 * 60).round()),
    );

    return FerryStatus(
      isOnFerry: true,
      etaPortAt: etaPortAt,
      routeLabel: '$originIsland – $destIsland',
    );
  }

  static double _haversineKm(double lat1, double lng1, double lat2, double lng2) {
    const R = 6371.0;
    final dLat = (lat2 - lat1) * math.pi / 180;
    final dLng = (lng2 - lng1) * math.pi / 180;
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(lat1 * math.pi / 180) *
            math.cos(lat2 * math.pi / 180) *
            math.sin(dLng / 2) *
            math.sin(dLng / 2);
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return R * c;
  }
}
