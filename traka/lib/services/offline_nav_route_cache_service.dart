import 'dart:convert';

import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'directions_service.dart';
import 'route_utils.dart';

/// Hasil baca cache disk: polyline + langkah + indeks langkah saat disimpan.
class OfflineNavRouteSnapshot {
  const OfflineNavRouteSnapshot({
    required this.data,
    required this.currentStepIndex,
  });

  final DirectionsResultWithSteps data;
  final int currentStepIndex;
}

/// Cache rute + langkah TBT ke disk (48 jam) agar tetap navigasi saat jaringan buruk / app dibuka ulang.
/// Peta utama tetap Google Maps; garis & teks petunjuk memakai snapshot terakhir.
class OfflineNavRouteCacheService {
  OfflineNavRouteCacheService._();

  static const _prefsKey = 'traka_offline_nav_snapshot_v1';
  static const int _schemaVersion = 1;
  /// Lebih lama = lebih mirip “lanjut navigasi” setelah sinyal buruk atau buka app lagi.
  static const Duration maxAge = Duration(hours: 72);
  static const double _destMatchMaxM = 850;
  static const int _maxPolylinePoints = 3600;
  /// Batas panjang string JSON (SharedPreferences / stabilitas decode).
  static const int _maxEncodedPayloadChars = 950000;

  static List<LatLng> _trimPolyline(List<LatLng> points) {
    if (points.length <= _maxPolylinePoints) return List<LatLng>.from(points);
    final step = points.length / _maxPolylinePoints;
    final out = <LatLng>[];
    for (var i = 0; i < _maxPolylinePoints; i++) {
      final idx = (i * step).floor().clamp(0, points.length - 1);
      out.add(points[idx]);
    }
    if (out.isEmpty || out.last.latitude != points.last.latitude ||
        out.last.longitude != points.last.longitude) {
      out.add(points.last);
    }
    return out;
  }

  static Map<String, dynamic> _stepToJson(RouteStep s) => {
        'instruction': s.instruction,
        'distanceText': s.distanceText,
        'distanceMeters': s.distanceMeters,
        'startDistanceMeters': s.startDistanceMeters,
        'endDistanceMeters': s.endDistanceMeters,
      };

  static RouteStep? _stepFromJson(dynamic raw) {
    if (raw is! Map) return null;
    final m = raw.cast<String, dynamic>();
    return RouteStep(
      instruction: m['instruction'] as String? ?? '',
      distanceText: m['distanceText'] as String? ?? '',
      distanceMeters: (m['distanceMeters'] as num?)?.toDouble() ?? 0,
      startDistanceMeters: (m['startDistanceMeters'] as num?)?.toDouble() ?? 0,
      endDistanceMeters: (m['endDistanceMeters'] as num?)?.toDouble() ?? 0,
    );
  }

  static List<LatLng>? _pointsFromJson(dynamic raw) {
    if (raw is! List) return null;
    final out = <LatLng>[];
    for (final e in raw) {
      if (e is! List || e.length < 2) continue;
      final la = (e[0] as num?)?.toDouble();
      final lo = (e[1] as num?)?.toDouble();
      if (la == null || lo == null) continue;
      out.add(LatLng(la, lo));
    }
    return out.isEmpty ? null : out;
  }

  /// Simpan snapshot rute kerja utama (bukan navigasi ke order).
  static List<Map<String, dynamic>>? _trafficFracsForDisk({
    required List<LatLng> polyline,
    required List<RoutePolylineTrafficSegment> segments,
  }) {
    if (segments.isEmpty) return null;
    final totalG = RouteUtils.polylineLengthMeters(polyline);
    if (totalG <= 0) return null;
    return segments
        .map(
          (s) => <String, dynamic>{
            'r': s.trafficRatio,
            's': (s.startDistanceMeters / totalG).clamp(0.0, 1.0),
            'e': (s.endDistanceMeters / totalG).clamp(0.0, 1.0),
          },
        )
        .toList();
  }

  static Future<void> saveWorkRoute({
    required double destLat,
    required double destLng,
    required List<LatLng> polyline,
    required List<RouteStep> steps,
    required int currentStepIndex,
    required String distanceText,
    required String durationText,
    required int durationSeconds,
    List<String> warnings = const [],
    String? tollInfoText,
    List<RoutePolylineTrafficSegment> trafficSegments = const [],
  }) async {
    if (steps.isEmpty || polyline.length < 2) return;
    final trimmed = _trimPolyline(polyline);
    final payload = <String, dynamic>{
      'v': _schemaVersion,
      'savedAtMs': DateTime.now().millisecondsSinceEpoch,
      'kind': 'work',
      'destLat': destLat,
      'destLng': destLng,
      'points': trimmed.map((p) => [p.latitude, p.longitude]).toList(),
      'steps': steps.map(_stepToJson).toList(),
      'currentStepIndex': currentStepIndex.clamp(0, steps.length - 1),
      'distanceText': distanceText,
      'durationText': durationText,
      'durationSeconds': durationSeconds,
      'warnings': warnings,
      'tollInfoText': tollInfoText,
    };
    final fracs = _trafficFracsForDisk(polyline: polyline, segments: trafficSegments);
    if (fracs != null) payload['trafficFracs'] = fracs;
    await _writePayload(payload);
  }

  /// Simpan snapshot navigasi ke penumpang / tujuan order.
  static Future<void> saveOrderNavigation({
    required String orderId,
    required bool navigatingToDestination,
    required double destLat,
    required double destLng,
    required List<LatLng> polyline,
    required List<RouteStep> steps,
    required int currentStepIndex,
    required String distanceText,
    required String durationText,
    required int durationSeconds,
    List<String> warnings = const [],
    String? tollInfoText,
    List<RoutePolylineTrafficSegment> trafficSegments = const [],
  }) async {
    if (orderId.isEmpty || steps.isEmpty || polyline.length < 2) return;
    final trimmed = _trimPolyline(polyline);
    final payload = <String, dynamic>{
      'v': _schemaVersion,
      'savedAtMs': DateTime.now().millisecondsSinceEpoch,
      'kind': 'order',
      'orderId': orderId,
      'navMode': navigatingToDestination ? 'dropoff' : 'pickup',
      'destLat': destLat,
      'destLng': destLng,
      'points': trimmed.map((p) => [p.latitude, p.longitude]).toList(),
      'steps': steps.map(_stepToJson).toList(),
      'currentStepIndex': currentStepIndex.clamp(0, steps.length - 1),
      'distanceText': distanceText,
      'durationText': durationText,
      'durationSeconds': durationSeconds,
      'warnings': warnings,
      'tollInfoText': tollInfoText,
    };
    final fracs = _trafficFracsForDisk(polyline: polyline, segments: trafficSegments);
    if (fracs != null) payload['trafficFracs'] = fracs;
    await _writePayload(payload);
  }

  static Future<void> _writePayload(Map<String, dynamic> payload) async {
    var toWrite = Map<String, dynamic>.from(payload);
    var encoded = jsonEncode(toWrite);
    // [trafficFracs] kecil (~ puluhan byte per step); jika total hanya sedikit
    // di atas batas, simpan tanpa fraksi macet agar polyline + TBT tetap ke disk.
    if (encoded.length > _maxEncodedPayloadChars &&
        toWrite.containsKey('trafficFracs')) {
      toWrite = Map<String, dynamic>.from(toWrite)..remove('trafficFracs');
      encoded = jsonEncode(toWrite);
    }
    if (encoded.length > _maxEncodedPayloadChars) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, encoded);
  }

  static bool _isFresh(int savedAtMs) {
    final saved = DateTime.fromMillisecondsSinceEpoch(savedAtMs);
    return DateTime.now().difference(saved) <= maxAge;
  }

  /// Muat snapshot rute kerja jika tujuan cocok (meter) dan masih segar.
  static Future<OfflineNavRouteSnapshot?> loadWorkRouteMatch({
    required double destLat,
    required double destLng,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    if (raw == null || raw.isEmpty) return null;
    Map<String, dynamic> map;
    try {
      map = jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
    if ((map['v'] as num?)?.toInt() != _schemaVersion) return null;
    if (map['kind'] != 'work') return null;
    final savedAt = (map['savedAtMs'] as num?)?.toInt();
    if (savedAt == null || !_isFresh(savedAt)) return null;
    final dLat = (map['destLat'] as num?)?.toDouble();
    final dLng = (map['destLng'] as num?)?.toDouble();
    if (dLat == null || dLng == null) return null;
    if (Geolocator.distanceBetween(destLat, destLng, dLat, dLng) >
        _destMatchMaxM) {
      return null;
    }
    final data = _parseDirectionsWithSteps(map);
    if (data == null) return null;
    final idx = (map['currentStepIndex'] as num?)?.toInt() ?? 0;
    return OfflineNavRouteSnapshot(
      data: data,
      currentStepIndex: idx.clamp(0, data.steps.length - 1),
    );
  }

  /// Muat snapshot navigasi order jika [orderId] dan mode jemput/antar cocok.
  static Future<OfflineNavRouteSnapshot?> loadOrderNavigationMatch({
    required String orderId,
    required bool navigatingToDestination,
  }) async {
    if (orderId.isEmpty) return null;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    if (raw == null || raw.isEmpty) return null;
    Map<String, dynamic> map;
    try {
      map = jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
    if ((map['v'] as num?)?.toInt() != _schemaVersion) return null;
    if (map['kind'] != 'order') return null;
    final oid = map['orderId'] as String? ?? '';
    if (oid != orderId) return null;
    final mode = map['navMode'] as String? ?? '';
    final want = navigatingToDestination ? 'dropoff' : 'pickup';
    if (mode != want) return null;
    final savedAt = (map['savedAtMs'] as num?)?.toInt();
    if (savedAt == null || !_isFresh(savedAt)) return null;
    final parsed = _parseDirectionsWithSteps(map);
    if (parsed == null) return null;
    final idx = (map['currentStepIndex'] as num?)?.toInt() ?? 0;
    return OfflineNavRouteSnapshot(
      data: parsed,
      currentStepIndex: idx.clamp(0, parsed.steps.length - 1),
    );
  }

  static DirectionsResultWithSteps? _parseDirectionsWithSteps(
    Map<String, dynamic> map,
  ) {
    final points = _pointsFromJson(map['points']);
    if (points == null || points.length < 2) return null;
    final stepsRaw = map['steps'];
    if (stepsRaw is! List) return null;
    final steps = <RouteStep>[];
    for (final s in stepsRaw) {
      final step = _stepFromJson(s);
      if (step != null) steps.add(step);
    }
    if (steps.isEmpty) return null;
    final distanceText = map['distanceText'] as String? ?? '';
    final durationText = map['durationText'] as String? ?? '';
    final durationSeconds = (map['durationSeconds'] as int?) ?? 0;
    final warnings = <String>[];
    final w = map['warnings'];
    if (w is List) {
      for (final x in w) {
        if (x is String) warnings.add(x);
      }
    }
    final toll = map['tollInfoText'] as String?;
    double distKm = 0;
    for (var i = 1; i < points.length; i++) {
      distKm += Geolocator.distanceBetween(
            points[i - 1].latitude,
            points[i - 1].longitude,
            points[i].latitude,
            points[i].longitude,
          ) /
          1000.0;
    }
    final result = DirectionsResult(
      points: points,
      distanceKm: distKm,
      distanceText: distanceText,
      durationSeconds: durationSeconds,
      durationText: durationText,
      tollInfoText: toll,
      warnings: warnings,
    );
    final trafficSegments = _trafficSegmentsFromPointsAndFracs(
      points,
      map['trafficFracs'],
    );
    return DirectionsResultWithSteps(
      result: result,
      steps: steps,
      trafficSegments: trafficSegments,
    );
  }

  static List<RoutePolylineTrafficSegment> _trafficSegmentsFromPointsAndFracs(
    List<LatLng> pts,
    dynamic fracsRaw,
  ) {
    if (pts.length < 2) return [];
    if (fracsRaw is! List || fracsRaw.isEmpty) return [];
    final L = RouteUtils.polylineLengthMeters(pts);
    if (L <= 0) return [];
    final out = <RoutePolylineTrafficSegment>[];
    for (final raw in fracsRaw) {
      if (raw is! Map) continue;
      final m = Map<String, dynamic>.from(raw);
      final r = (m['r'] as num?)?.toDouble() ?? 1.0;
      final sf = (m['s'] as num?)?.toDouble() ?? 0.0;
      final ef = (m['e'] as num?)?.toDouble() ?? 0.0;
      final sm = (sf.clamp(0.0, 1.0)) * L;
      final em = (ef.clamp(0.0, 1.0)) * L;
      final slice = RouteUtils.slicePolylineByDistanceRange(pts, sm, em);
      if (slice.length < 2) continue;
      out.add(
        RoutePolylineTrafficSegment(
          points: slice,
          trafficRatio: r,
          startDistanceMeters: sm,
          endDistanceMeters: em,
        ),
      );
    }
    return out;
  }

  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefsKey);
  }
}
