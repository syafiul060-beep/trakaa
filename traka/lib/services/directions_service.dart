import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;

import '../config/maps_config.dart';
import '../utils/retry_utils.dart';
import 'navigation_diagnostics.dart';
import 'route_utils.dart';

/// Cache untuk hasil Directions API (hemat biaya API).
final Map<String, ({DirectionsResult result, DateTime expiredAt})> _routeCache = {};
final Map<String, ({DirectionsResultWithSteps data, DateTime expiredAt})> _routeWithStepsCache = {};
final Map<String, ({List<DirectionsResult> results, DateTime expiredAt})> _altRouteCache = {};
final Map<String, ({List<DirectionsResultWithSteps> results, DateTime expiredAt})> _altRouteWithStepsCache = {};
const Duration _cacheDuration = Duration(hours: 1);
/// Cache khusus [getAlternativeRoutes]: OD sama jarang berubah; memperpanjang TTL mengurangi panggilan API.
const Duration _altRouteCacheDuration = Duration(hours: 2);

/// Parse warnings dari objek route (penutupan jalan, dll).
List<String> _parseWarnings(Map<String, dynamic> route) {
  final warnings = <String>[];
  final w = route['warnings'] as List<dynamic>?;
  if (w != null) {
    for (final x in w) {
      if (x is String) warnings.add(x);
    }
  }
  return warnings;
}

String _cacheKey(double oLat, double oLng, double dLat, double dLng, {bool traffic = false}) =>
    '${oLat.toStringAsFixed(4)}_${oLng.toStringAsFixed(4)}_${dLat.toStringAsFixed(4)}_${dLng.toStringAsFixed(4)}${traffic ? "_traffic" : ""}';

const Duration _trafficCacheDuration = Duration(minutes: 5);

/// Snapshot rute terakhir per OD (tanpa TTL) untuk fallback saat `OVER_QUERY_LIMIT` / error jaringan.
final Map<String, DirectionsResult> _lastSuccessRouteSnapshot = {};
final Map<String, DirectionsResultWithSteps> _lastSuccessRouteWithStepsSnapshot = {};
final Map<String, List<DirectionsResult>> _lastSuccessAltRoutesSnapshot = {};
final Map<String, List<DirectionsResultWithSteps>>
    _lastSuccessAltRoutesWithStepsSnapshot = {};

const int _maxSnapshotEntries = 64;

void _trimOldestStringKeyMap<T>(Map<String, T> map) {
  while (map.length > _maxSnapshotEntries) {
    map.remove(map.keys.first);
  }
}

bool _statusWorthStaleFallback(String? status) {
  if (status == null) return false;
  return status == 'OVER_QUERY_LIMIT' ||
      status == 'OVER_DAILY_LIMIT' ||
      status == 'UNKNOWN_ERROR';
}

void _evictExpiredCache() {
  final now = DateTime.now();
  _routeCache.removeWhere((_, v) => v.expiredAt.isBefore(now));
  _routeWithStepsCache.removeWhere((_, v) => v.expiredAt.isBefore(now));
  _altRouteCache.removeWhere((_, v) => v.expiredAt.isBefore(now));
  _altRouteWithStepsCache.removeWhere((_, v) => v.expiredAt.isBefore(now));
}

/// Hasil fetch ETA/rute singkat (untuk UI: bedakan gagal vs kosong).
class DirectionsEtaOutcome {
  const DirectionsEtaOutcome({
    this.result,
    this.errorStatus,
    this.usedStaleCache = false,
  });

  final DirectionsResult? result;
  /// Status dari JSON Directions (`ZERO_RESULTS`, `OVER_QUERY_LIMIT`, …), `HTTP_*`, atau `ERROR`.
  final String? errorStatus;

  /// Rute dari snapshot terakhir saat API gagal (kuota/jaringan) — ETA mungkin tidak akurat.
  final bool usedStaleCache;

  bool get hasRoute => result != null;
}

/// Hasil dari Directions API: polyline + jarak + waktu.
class DirectionsResult {
  final List<LatLng> points;
  final double distanceKm;
  final String distanceText;
  final int durationSeconds;
  final String durationText;
  /// Info tol (dari Routes API). Kosong jika belum di-fetch.
  final String? tollInfoText;
  /// Peringatan rute (penutupan jalan, dll) dari API.
  final List<String> warnings;

  const DirectionsResult({
    required this.points,
    required this.distanceKm,
    required this.distanceText,
    required this.durationSeconds,
    required this.durationText,
    this.tollInfoText,
    this.warnings = const [],
  });
}

/// Segmen polyline dengan fraksi «macet» (warna garis rute).
class RoutePolylineTrafficSegment {
  final List<LatLng> points;
  final double trafficRatio;
  final double startDistanceMeters;
  final double endDistanceMeters;

  const RoutePolylineTrafficSegment({
    required this.points,
    required this.trafficRatio,
    required this.startDistanceMeters,
    required this.endDistanceMeters,
  });
}

/// Satu langkah petunjuk belok (turn-by-turn).
class RouteStep {
  final String instruction;
  final String distanceText;
  final double distanceMeters;
  /// Jarak kumulatif dari awal rute (meter).
  final double startDistanceMeters;
  /// Jarak kumulatif sampai akhir step (meter).
  final double endDistanceMeters;

  const RouteStep({
    required this.instruction,
    required this.distanceText,
    required this.distanceMeters,
    required this.startDistanceMeters,
    required this.endDistanceMeters,
  });
}

/// Hasil rute dengan steps untuk turn-by-turn.
class DirectionsResultWithSteps {
  final DirectionsResult result;
  final List<RouteStep> steps;
  final List<RoutePolylineTrafficSegment> trafficSegments;

  const DirectionsResultWithSteps({
    required this.result,
    required this.steps,
    this.trafficSegments = const [],
  });
}

/// Hasil [getRouteWithSteps]: data bisa null; [usedStaleCache] true jika dari snapshot (API/kuota gagal).
class DirectionsWithStepsOutcome {
  const DirectionsWithStepsOutcome({
    this.data,
    this.usedStaleCache = false,
    this.errorStatus,
  });

  final DirectionsResultWithSteps? data;
  final bool usedStaleCache;
  /// Status Directions / HTTP / `backoff` saat kuota — untuk analytics; null jika sukses normal.
  final String? errorStatus;

  bool get hasRoute => data != null;
}

/// Mendapatkan rute (polyline) dari Google Directions API.
class DirectionsService {
  static const String _baseUrl =
      'https://maps.googleapis.com/maps/api/directions/json';

  /// Kurangi spam request setelah `OVER_QUERY_LIMIT` / `OVER_DAILY_LIMIT`.
  static DateTime? _stepsQuotaBackoffUntil;

  /// Ambil rute lengkap (polyline + jarak + waktu) dari origin ke destination.
  /// Hasil di-cache 1 jam per origin-destination (hemat API).
  static Future<DirectionsResult?> getRoute({
    required double originLat,
    required double originLng,
    required double destLat,
    required double destLng,
  }) async {
    final o = await getRouteEta(
      originLat: originLat,
      originLng: originLng,
      destLat: destLat,
      destLng: destLng,
    );
    return o.result;
  }

  /// Sama seperti [getRoute] tetapi selalu mengembalikan outcome (untuk pesan error + retry di UI).
  static Future<DirectionsEtaOutcome> getRouteEta({
    required double originLat,
    required double originLng,
    required double destLat,
    required double destLng,
  }) async {
    _evictExpiredCache();
    final key = _cacheKey(originLat, originLng, destLat, destLng);
    final cached = _routeCache[key];
    if (cached != null && cached.expiredAt.isAfter(DateTime.now())) {
      return DirectionsEtaOutcome(result: cached.result, errorStatus: null);
    }

    final apiKey = MapsConfig.directionsApiKey;
    if (apiKey.isEmpty && kDebugMode) {
      debugPrint('Directions API: MAPS_API_KEY kosong. Jalankan via run_hybrid.ps1 atau tambah --dart-define=MAPS_API_KEY=xxx');
    }
    final uri = Uri.parse(_baseUrl).replace(
      queryParameters: {
        'origin': '$originLat,$originLng',
        'destination': '$destLat,$destLng',
        'mode': 'driving',
        'key': apiKey,
      },
    );
    try {
      final response = await RetryUtils.withRetry(() async {
        final r = await http.get(uri);
        if (r.statusCode >= 500 || r.statusCode == 429) {
          throw Exception('HTTP ${r.statusCode}');
        }
        return r;
      });
      if (response.statusCode != 200) {
        final stale = _lastSuccessRouteSnapshot[key];
        if (stale != null) {
          return DirectionsEtaOutcome(
            result: stale,
            errorStatus: 'HTTP_${response.statusCode}',
            usedStaleCache: true,
          );
        }
        return DirectionsEtaOutcome(result: null, errorStatus: 'HTTP_${response.statusCode}');
      }
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final status = data['status'] as String?;
      if (status != 'OK') {
        if (_statusWorthStaleFallback(status)) {
          final stale = _lastSuccessRouteSnapshot[key];
          if (stale != null) {
            return DirectionsEtaOutcome(
              result: stale,
              errorStatus: status,
              usedStaleCache: true,
            );
          }
        }
        return DirectionsEtaOutcome(result: null, errorStatus: status ?? 'NOT_OK');
      }
      final routes = data['routes'] as List<dynamic>?;
      if (routes == null || routes.isEmpty) {
        return const DirectionsEtaOutcome(result: null, errorStatus: 'NO_ROUTES');
      }
      final route = routes.first as Map<String, dynamic>;
      final points = _extractPolylineFromSteps(route) ?? _extractOverviewPolyline(route);
      if (points == null || points.isEmpty) {
        return const DirectionsEtaOutcome(result: null, errorStatus: 'NO_POLYLINE');
      }

      double distanceKm = 0;
      String distanceText = '-';
      int durationSeconds = 0;
      String durationText = '-';
      final legs = route['legs'] as List<dynamic>?;
      if (legs != null && legs.isNotEmpty) {
        final leg = legs.first as Map<String, dynamic>;
        final dist = leg['distance'] as Map<String, dynamic>?;
        final dur = leg['duration'] as Map<String, dynamic>?;
        if (dist != null) {
          distanceKm = ((dist['value'] as num?) ?? 0) / 1000;
          distanceText =
              (dist['text'] as String?) ??
              '${distanceKm.toStringAsFixed(1)} km';
        }
        if (dur != null) {
          durationSeconds = (dur['value'] as num?)?.toInt() ?? 0;
          durationText = (dur['text'] as String?) ?? '-';
        }
      }

      final warnings = _parseWarnings(route);
      final result = DirectionsResult(
        points: points,
        distanceKm: distanceKm,
        distanceText: distanceText,
        durationSeconds: durationSeconds,
        durationText: durationText,
        warnings: warnings,
      );
      _routeCache[key] = (result: result, expiredAt: DateTime.now().add(_cacheDuration));
      _lastSuccessRouteSnapshot[key] = result;
      _trimOldestStringKeyMap(_lastSuccessRouteSnapshot);
      return DirectionsEtaOutcome(result: result, errorStatus: null);
    } catch (_) {
      final stale = _lastSuccessRouteSnapshot[key];
      if (stale != null) {
        return DirectionsEtaOutcome(
          result: stale,
          errorStatus: 'ERROR',
          usedStaleCache: true,
        );
      }
      return const DirectionsEtaOutcome(result: null, errorStatus: 'ERROR');
    }
  }

  /// Ambil rute lengkap dengan steps untuk turn-by-turn.
  /// [trafficAware]: true = ETA berdasarkan lalu lintas (departure_time=now).
  static Future<DirectionsWithStepsOutcome> getRouteWithSteps({
    required double originLat,
    required double originLng,
    required double destLat,
    required double destLng,
    bool trafficAware = false,
  }) async {
    _evictExpiredCache();
    final key = _cacheKey(originLat, originLng, destLat, destLng, traffic: trafficAware);
    final cached = _routeWithStepsCache[key];
    if (cached != null && cached.expiredAt.isAfter(DateTime.now())) {
      return DirectionsWithStepsOutcome(data: cached.data, usedStaleCache: false);
    }

    final now = DateTime.now();
    if (_stepsQuotaBackoffUntil != null && now.isBefore(_stepsQuotaBackoffUntil!)) {
      final stale = _lastSuccessRouteWithStepsSnapshot[key];
      if (stale != null) {
        return DirectionsWithStepsOutcome(
          data: stale,
          usedStaleCache: true,
          errorStatus: 'backoff',
        );
      }
    }

    final params = <String, String>{
      'origin': '$originLat,$originLng',
      'destination': '$destLat,$destLng',
      'mode': 'driving',
      'key': MapsConfig.directionsApiKey,
    };
    if (trafficAware) {
      params['departure_time'] = 'now';
      params['traffic_model'] = 'best_guess';
    }
    final uri = Uri.parse(_baseUrl).replace(queryParameters: params);
    try {
      final response = await RetryUtils.withRetry(() async {
        final r = await http.get(uri);
        if (r.statusCode >= 500 || r.statusCode == 429) {
          throw Exception('HTTP ${r.statusCode}');
        }
        return r;
      });
      if (response.statusCode != 200) {
        final stale = _lastSuccessRouteWithStepsSnapshot[key];
        if (stale != null) {
          return DirectionsWithStepsOutcome(
            data: stale,
            usedStaleCache: true,
            errorStatus: 'http_${response.statusCode}',
          );
        }
        NavigationDiagnostics.reportDirectionsFailureThrottled(
          scope: 'getRouteWithSteps',
          errorKey: 'http_${response.statusCode}',
        );
        return DirectionsWithStepsOutcome(
          data: null,
          errorStatus: 'http_${response.statusCode}',
        );
      }
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final status = data['status'] as String?;
      if (status != 'OK') {
        if (status == 'OVER_QUERY_LIMIT' || status == 'OVER_DAILY_LIMIT') {
          _stepsQuotaBackoffUntil = DateTime.now().add(const Duration(seconds: 120));
        }
        if (_statusWorthStaleFallback(status)) {
          final stale = _lastSuccessRouteWithStepsSnapshot[key];
          if (stale != null) {
            return DirectionsWithStepsOutcome(
              data: stale,
              usedStaleCache: true,
              errorStatus: status,
            );
          }
        }
        NavigationDiagnostics.reportDirectionsFailureThrottled(
          scope: 'getRouteWithSteps',
          errorKey: status ?? 'not_ok',
        );
        return DirectionsWithStepsOutcome(data: null, errorStatus: status ?? 'not_ok');
      }
      _stepsQuotaBackoffUntil = null;
      final routes = data['routes'] as List<dynamic>?;
      if (routes == null || routes.isEmpty) {
        return const DirectionsWithStepsOutcome(data: null, errorStatus: 'zero_routes');
      }
      final route = routes.first as Map<String, dynamic>;
      final points = _extractPolylineFromSteps(route) ?? _extractOverviewPolyline(route);
      if (points == null || points.isEmpty) {
        return const DirectionsWithStepsOutcome(data: null, errorStatus: 'no_polyline');
      }

      double distanceKm = 0;
      String distanceText = '-';
      int durationSeconds = 0;
      String durationText = '-';
      final legs = route['legs'] as List<dynamic>?;
      final steps = <RouteStep>[];
      double cumMeters = 0;

      if (legs != null && legs.isNotEmpty) {
        final leg = legs.first as Map<String, dynamic>;
        final dist = leg['distance'] as Map<String, dynamic>?;
        final dur = leg['duration'] as Map<String, dynamic>?;
        final durInTraffic = leg['duration_in_traffic'] as Map<String, dynamic>?;
        if (dist != null) {
          distanceKm = ((dist['value'] as num?) ?? 0) / 1000;
          distanceText =
              (dist['text'] as String?) ??
              '${distanceKm.toStringAsFixed(1)} km';
        }
        if (dur != null) {
          durationSeconds = (dur['value'] as num?)?.toInt() ?? 0;
          durationText = (dur['text'] as String?) ?? '-';
        }
        if (trafficAware && durInTraffic != null) {
          durationSeconds = (durInTraffic['value'] as num?)?.toInt() ?? durationSeconds;
          durationText = (durInTraffic['text'] as String?) ?? durationText;
        }
        final legSteps = leg['steps'] as List<dynamic>?;
        if (legSteps != null) {
          for (final s in legSteps) {
            final step = s as Map<String, dynamic>;
            final stepDist = step['distance'] as Map<String, dynamic>?;
            final stepDistM = (stepDist?['value'] as num?)?.toDouble() ?? 0;
            final stepDistText = (stepDist?['text'] as String?) ?? '-';
            final html = (step['html_instructions'] as String?) ?? '';
            final instruction = html.replaceAll(RegExp(r'<[^>]*>'), '').trim();
            final startM = cumMeters;
            cumMeters += stepDistM;
            steps.add(RouteStep(
              instruction: instruction.isEmpty ? 'Lanjutkan' : instruction,
              distanceText: stepDistText,
              distanceMeters: stepDistM,
              startDistanceMeters: startM,
              endDistanceMeters: cumMeters,
            ));
          }
        }
      }

      final warnings = _parseWarnings(route);
      final result = DirectionsResult(
        points: points,
        distanceKm: distanceKm,
        distanceText: distanceText,
        durationSeconds: durationSeconds,
        durationText: durationText,
        warnings: warnings,
      );
      final trafficSegments = legs != null && legs.isNotEmpty
          ? _trafficSegmentsFromLeg(legs.first as Map<String, dynamic>, points)
          : <RoutePolylineTrafficSegment>[];
      final withSteps = DirectionsResultWithSteps(
        result: result,
        steps: steps,
        trafficSegments: trafficSegments,
      );
      _routeWithStepsCache[key] = (
        data: withSteps,
        expiredAt: DateTime.now().add(trafficAware ? _trafficCacheDuration : _cacheDuration),
      );
      _lastSuccessRouteWithStepsSnapshot[key] = withSteps;
      _trimOldestStringKeyMap(_lastSuccessRouteWithStepsSnapshot);
      return DirectionsWithStepsOutcome(data: withSteps, usedStaleCache: false);
    } catch (_) {
      final stale = _lastSuccessRouteWithStepsSnapshot[key];
      if (stale != null) {
        return DirectionsWithStepsOutcome(
          data: stale,
          usedStaleCache: true,
          errorStatus: 'network',
        );
      }
      NavigationDiagnostics.reportDirectionsFailureThrottled(
        scope: 'getRouteWithSteps',
        errorKey: 'network',
      );
      return const DirectionsWithStepsOutcome(data: null, errorStatus: 'network');
    }
  }

  /// Ambil semua alternatif rute dari origin ke destination.
  /// [trafficAware]: true = durasi berdasarkan lalu lintas.
  static Future<List<DirectionsResult>> getAlternativeRoutes({
    required double originLat,
    required double originLng,
    required double destLat,
    required double destLng,
    bool trafficAware = false,
  }) async {
    _evictExpiredCache();
    final key = _cacheKey(originLat, originLng, destLat, destLng, traffic: trafficAware);
    final cached = _altRouteCache[key];
    if (cached != null && cached.expiredAt.isAfter(DateTime.now())) {
      return cached.results;
    }

    final params = <String, String>{
      'origin': '$originLat,$originLng',
      'destination': '$destLat,$destLng',
      'mode': 'driving',
      'alternatives': 'true',
      'key': MapsConfig.directionsApiKey,
    };
    if (trafficAware) {
      params['departure_time'] = 'now';
      params['traffic_model'] = 'best_guess';
    }
    final uri = Uri.parse(_baseUrl).replace(queryParameters: params);
    try {
      final response = await RetryUtils.withRetry(() async {
        final r = await http.get(uri);
        if (r.statusCode >= 500 || r.statusCode == 429) {
          throw Exception('HTTP ${r.statusCode}');
        }
        return r;
      });
      if (response.statusCode != 200) {
        final stale = _lastSuccessAltRoutesSnapshot[key];
        return stale != null ? List<DirectionsResult>.from(stale) : [];
      }
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final status = data['status'] as String?;
      if (status != 'OK') {
        if (_statusWorthStaleFallback(status)) {
          final stale = _lastSuccessAltRoutesSnapshot[key];
          if (stale != null) return List<DirectionsResult>.from(stale);
        }
        return [];
      }
      final routes = data['routes'] as List<dynamic>?;
      if (routes == null || routes.isEmpty) return [];

      final results = <DirectionsResult>[];
      for (final routeData in routes) {
        final route = routeData as Map<String, dynamic>;
        final points = _extractPolylineFromSteps(route) ?? _extractOverviewPolyline(route);
        if (points == null || points.isEmpty) continue;

        double distanceKm = 0;
        String distanceText = '-';
        int durationSeconds = 0;
        String durationText = '-';
        final legs = route['legs'] as List<dynamic>?;
        if (legs != null && legs.isNotEmpty) {
          final leg = legs.first as Map<String, dynamic>;
          final dist = leg['distance'] as Map<String, dynamic>?;
          final dur = leg['duration'] as Map<String, dynamic>?;
          final durInTraffic = leg['duration_in_traffic'] as Map<String, dynamic>?;
          if (dist != null) {
            distanceKm = ((dist['value'] as num?) ?? 0) / 1000;
            distanceText =
                (dist['text'] as String?) ??
                '${distanceKm.toStringAsFixed(1)} km';
          }
          if (dur != null) {
            durationSeconds = (dur['value'] as num?)?.toInt() ?? 0;
            durationText = (dur['text'] as String?) ?? '-';
          }
          if (trafficAware && durInTraffic != null) {
            durationSeconds = (durInTraffic['value'] as num?)?.toInt() ?? durationSeconds;
            durationText = (durInTraffic['text'] as String?) ?? durationText;
          }
        }

        final warnings = _parseWarnings(route);
        results.add(
          DirectionsResult(
            points: points,
            distanceKm: distanceKm,
            distanceText: distanceText,
            durationSeconds: durationSeconds,
            durationText: durationText,
            warnings: warnings,
          ),
        );
      }
      if (results.isNotEmpty) {
        _altRouteCache[key] = (
          results: results,
          expiredAt: DateTime.now().add(
            trafficAware ? _trafficCacheDuration : _altRouteCacheDuration,
          ),
        );
        _lastSuccessAltRoutesSnapshot[key] =
            List<DirectionsResult>.from(results);
        _trimOldestStringKeyMap(_lastSuccessAltRoutesSnapshot);
      }
      return results;
    } catch (_) {
      final stale = _lastSuccessAltRoutesSnapshot[key];
      return stale != null ? List<DirectionsResult>.from(stale) : [];
    }
  }

  /// Ambil alternatif rute dengan steps (untuk ganti rute saat navigasi).
  /// [trafficAware]: true = durasi berdasarkan lalu lintas.
  static Future<List<DirectionsResultWithSteps>> getAlternativeRoutesWithSteps({
    required double originLat,
    required double originLng,
    required double destLat,
    required double destLng,
    bool trafficAware = false,
  }) async {
    _evictExpiredCache();
    final key = _cacheKey(originLat, originLng, destLat, destLng, traffic: trafficAware);
    final cached = _altRouteWithStepsCache[key];
    if (cached != null && cached.expiredAt.isAfter(DateTime.now())) {
      return cached.results;
    }

    final params = <String, String>{
      'origin': '$originLat,$originLng',
      'destination': '$destLat,$destLng',
      'mode': 'driving',
      'alternatives': 'true',
      'key': MapsConfig.directionsApiKey,
    };
    if (trafficAware) {
      params['departure_time'] = 'now';
      params['traffic_model'] = 'best_guess';
    }
    final uri = Uri.parse(_baseUrl).replace(queryParameters: params);
    try {
      final response = await RetryUtils.withRetry(() async {
        final r = await http.get(uri);
        if (r.statusCode >= 500 || r.statusCode == 429) {
          throw Exception('HTTP ${r.statusCode}');
        }
        return r;
      });
      if (response.statusCode != 200) {
        final stale = _lastSuccessAltRoutesWithStepsSnapshot[key];
        return stale != null
            ? List<DirectionsResultWithSteps>.from(stale)
            : [];
      }
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final status = data['status'] as String?;
      if (status != 'OK') {
        if (_statusWorthStaleFallback(status)) {
          final stale = _lastSuccessAltRoutesWithStepsSnapshot[key];
          if (stale != null) {
            return List<DirectionsResultWithSteps>.from(stale);
          }
        }
        return [];
      }
      final routes = data['routes'] as List<dynamic>?;
      if (routes == null || routes.isEmpty) return [];

      final results = <DirectionsResultWithSteps>[];
      for (final routeData in routes) {
        final route = routeData as Map<String, dynamic>;
        final points = _extractPolylineFromSteps(route) ?? _extractOverviewPolyline(route);
        if (points == null || points.isEmpty) continue;

        double distanceKm = 0;
        String distanceText = '-';
        int durationSeconds = 0;
        String durationText = '-';
        final steps = <RouteStep>[];
        double cumMeters = 0;

        final legs = route['legs'] as List<dynamic>?;
        if (legs != null && legs.isNotEmpty) {
          final leg = legs.first as Map<String, dynamic>;
          final dist = leg['distance'] as Map<String, dynamic>?;
          final dur = leg['duration'] as Map<String, dynamic>?;
          final durInTraffic = leg['duration_in_traffic'] as Map<String, dynamic>?;
          if (dist != null) {
            distanceKm = ((dist['value'] as num?) ?? 0) / 1000;
            distanceText = (dist['text'] as String?) ?? '${distanceKm.toStringAsFixed(1)} km';
          }
          if (dur != null) {
            durationSeconds = (dur['value'] as num?)?.toInt() ?? 0;
            durationText = (dur['text'] as String?) ?? '-';
          }
          if (trafficAware && durInTraffic != null) {
            durationSeconds = (durInTraffic['value'] as num?)?.toInt() ?? durationSeconds;
            durationText = (durInTraffic['text'] as String?) ?? durationText;
          }
          final legSteps = leg['steps'] as List<dynamic>?;
          if (legSteps != null) {
            for (final s in legSteps) {
              final step = s as Map<String, dynamic>;
              final stepDist = step['distance'] as Map<String, dynamic>?;
              final stepDistM = (stepDist?['value'] as num?)?.toDouble() ?? 0;
              final stepDistText = (stepDist?['text'] as String?) ?? '-';
              final html = (step['html_instructions'] as String?) ?? '';
              final instruction = html.replaceAll(RegExp(r'<[^>]*>'), '').trim();
              final startM = cumMeters;
              cumMeters += stepDistM;
              steps.add(RouteStep(
                instruction: instruction.isEmpty ? 'Lanjutkan' : instruction,
                distanceText: stepDistText,
                distanceMeters: stepDistM,
                startDistanceMeters: startM,
                endDistanceMeters: cumMeters,
              ));
            }
          }
        }

        final warnings = _parseWarnings(route);
        final result = DirectionsResult(
          points: points,
          distanceKm: distanceKm,
          distanceText: distanceText,
          durationSeconds: durationSeconds,
          durationText: durationText,
          warnings: warnings,
        );
        final trafficSegments = legs != null && legs.isNotEmpty
            ? _trafficSegmentsFromLeg(legs.first as Map<String, dynamic>, points)
            : <RoutePolylineTrafficSegment>[];
        results.add(
          DirectionsResultWithSteps(
            result: result,
            steps: steps,
            trafficSegments: trafficSegments,
          ),
        );
      }
      if (results.isNotEmpty) {
        _altRouteWithStepsCache[key] = (
          results: results,
          expiredAt: DateTime.now().add(
            trafficAware ? _trafficCacheDuration : _altRouteCacheDuration,
          ),
        );
        _lastSuccessAltRoutesWithStepsSnapshot[key] =
            List<DirectionsResultWithSteps>.from(results);
        _trimOldestStringKeyMap(_lastSuccessAltRoutesWithStepsSnapshot);
      }
      return results;
    } catch (_) {
      final stale = _lastSuccessAltRoutesWithStepsSnapshot[key];
      return stale != null
          ? List<DirectionsResultWithSteps>.from(stale)
          : [];
    }
  }

  /// Ambil polyline saja (untuk backward compatibility).
  static Future<List<LatLng>?> getRoutePolyline({
    required double originLat,
    required double originLng,
    required double destLat,
    required double destLng,
  }) async {
    final result = await getRoute(
      originLat: originLat,
      originLng: originLng,
      destLat: destLat,
      destLng: destLng,
    );
    return result?.points;
  }

  /// Ambil polyline dari steps (mengikuti jalan) - lebih rapi dari overview.
  static List<LatLng>? _extractPolylineFromSteps(Map<String, dynamic> route) {
    final legs = route['legs'] as List<dynamic>?;
    if (legs == null || legs.isEmpty) return null;
    final allPoints = <LatLng>[];
    for (final legData in legs) {
      final leg = legData as Map<String, dynamic>;
      final steps = leg['steps'] as List<dynamic>?;
      if (steps == null || steps.isEmpty) continue;
      for (int i = 0; i < steps.length; i++) {
        final step = steps[i] as Map<String, dynamic>;
        final poly = step['polyline'] as Map<String, dynamic>?;
        final encoded = poly?['points'] as String?;
        if (encoded == null || encoded.isEmpty) continue;
        final stepPoints = _decodePolyline(encoded);
        if (stepPoints.isEmpty) continue;
        // Skip titik pertama step (kecuali step pertama) - sama dengan titik akhir step sebelumnya
        final startIdx = allPoints.isNotEmpty ? 1 : 0;
        for (int j = startIdx; j < stepPoints.length; j++) {
          allPoints.add(stepPoints[j]);
        }
      }
    }
    return allPoints.isEmpty ? null : allPoints;
  }

  /// Segmen warna lalu lintas sepanjang polyline (duration_in_traffic vs duration per step).
  static List<RoutePolylineTrafficSegment> _trafficSegmentsFromLeg(
    Map<String, dynamic> leg,
    List<LatLng> fullPoints,
  ) {
    final legSteps = leg['steps'] as List<dynamic>?;
    if (legSteps == null || legSteps.isEmpty || fullPoints.length < 2) {
      return const [];
    }
    double cumMeters = 0;
    final out = <RoutePolylineTrafficSegment>[];
    for (final s in legSteps) {
      final step = s as Map<String, dynamic>;
      final stepDist = step['distance'] as Map<String, dynamic>?;
      final stepDistM = (stepDist?['value'] as num?)?.toDouble() ?? 0;
      final dur = step['duration'] as Map<String, dynamic>?;
      final durSec = (dur?['value'] as num?)?.toDouble() ?? 0;
      final durTf = step['duration_in_traffic'] as Map<String, dynamic>?;
      final durTfSec = (durTf?['value'] as num?)?.toDouble();
      final startM = cumMeters;
      cumMeters += stepDistM;
      var ratio = 1.0;
      if (durSec >= 8 && durTfSec != null && durTfSec > 0) {
        ratio = (durTfSec / durSec).clamp(1.0, 2.6);
      }
      final slice =
          RouteUtils.slicePolylineByDistanceRange(fullPoints, startM, cumMeters);
      if (slice.length >= 2) {
        out.add(
          RoutePolylineTrafficSegment(
            points: slice,
            trafficRatio: ratio,
            startDistanceMeters: startM,
            endDistanceMeters: cumMeters,
          ),
        );
      }
    }
    return out;
  }

  /// Fallback: overview_polyline (versi disederhanakan).
  static List<LatLng>? _extractOverviewPolyline(Map<String, dynamic> route) {
    final overview = route['overview_polyline'] as Map<String, dynamic>?;
    final encoded = overview?['points'] as String?;
    if (encoded == null || encoded.isEmpty) return null;
    return _decodePolyline(encoded);
  }

  static List<LatLng> _decodePolyline(String encoded) {
    final List<LatLng> points = [];
    int index = 0;
    int lat = 0;
    int lng = 0;
    while (index < encoded.length) {
      int b;
      int shift = 0;
      int result = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      final dlat = (result & 1) != 0 ? ~(result >> 1) : (result >> 1);
      lat += dlat;
      shift = 0;
      result = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      final dlng = (result & 1) != 0 ? ~(result >> 1) : (result >> 1);
      lng += dlng;
      points.add(LatLng(lat / 1e5, lng / 1e5));
    }
    return points;
  }
}
