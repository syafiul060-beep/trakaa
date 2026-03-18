import 'dart:convert';

import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;

import '../config/maps_config.dart';
import '../utils/retry_utils.dart';

/// Cache untuk hasil Directions API (hemat biaya API).
final Map<String, ({DirectionsResult result, DateTime expiredAt})> _routeCache = {};
final Map<String, ({DirectionsResultWithSteps data, DateTime expiredAt})> _routeWithStepsCache = {};
final Map<String, ({List<DirectionsResult> results, DateTime expiredAt})> _altRouteCache = {};
final Map<String, ({List<DirectionsResultWithSteps> results, DateTime expiredAt})> _altRouteWithStepsCache = {};
const Duration _cacheDuration = Duration(hours: 1);

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

String _cacheKey(double oLat, double oLng, double dLat, double dLng) =>
    '${oLat.toStringAsFixed(4)}_${oLng.toStringAsFixed(4)}_${dLat.toStringAsFixed(4)}_${dLng.toStringAsFixed(4)}';

void _evictExpiredCache() {
  final now = DateTime.now();
  _routeCache.removeWhere((_, v) => v.expiredAt.isBefore(now));
  _routeWithStepsCache.removeWhere((_, v) => v.expiredAt.isBefore(now));
  _altRouteCache.removeWhere((_, v) => v.expiredAt.isBefore(now));
  _altRouteWithStepsCache.removeWhere((_, v) => v.expiredAt.isBefore(now));
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

  const DirectionsResultWithSteps({
    required this.result,
    required this.steps,
  });
}

/// Mendapatkan rute (polyline) dari Google Directions API.
class DirectionsService {
  static const String _baseUrl =
      'https://maps.googleapis.com/maps/api/directions/json';

  /// Ambil rute lengkap (polyline + jarak + waktu) dari origin ke destination.
  /// Hasil di-cache 1 jam per origin-destination (hemat API).
  static Future<DirectionsResult?> getRoute({
    required double originLat,
    required double originLng,
    required double destLat,
    required double destLng,
  }) async {
    _evictExpiredCache();
    final key = _cacheKey(originLat, originLng, destLat, destLng);
    final cached = _routeCache[key];
    if (cached != null && cached.expiredAt.isAfter(DateTime.now())) {
      return cached.result;
    }

    final uri = Uri.parse(_baseUrl).replace(
      queryParameters: {
        'origin': '$originLat,$originLng',
        'destination': '$destLat,$destLng',
        'mode': 'driving',
        'key': MapsConfig.directionsApiKey,
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
      if (response.statusCode != 200) return null;
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final status = data['status'] as String?;
      if (status != 'OK') return null;
      final routes = data['routes'] as List<dynamic>?;
      if (routes == null || routes.isEmpty) return null;
      final route = routes.first as Map<String, dynamic>;
      final points = _extractPolylineFromSteps(route) ?? _extractOverviewPolyline(route);
      if (points == null || points.isEmpty) return null;

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
      return result;
    } catch (_) {
      return null;
    }
  }

  /// Ambil rute lengkap dengan steps untuk turn-by-turn.
  static Future<DirectionsResultWithSteps?> getRouteWithSteps({
    required double originLat,
    required double originLng,
    required double destLat,
    required double destLng,
  }) async {
    _evictExpiredCache();
    final key = _cacheKey(originLat, originLng, destLat, destLng);
    final cached = _routeWithStepsCache[key];
    if (cached != null && cached.expiredAt.isAfter(DateTime.now())) {
      return cached.data;
    }

    final uri = Uri.parse(_baseUrl).replace(
      queryParameters: {
        'origin': '$originLat,$originLng',
        'destination': '$destLat,$destLng',
        'mode': 'driving',
        'key': MapsConfig.directionsApiKey,
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
      if (response.statusCode != 200) return null;
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final status = data['status'] as String?;
      if (status != 'OK') return null;
      final routes = data['routes'] as List<dynamic>?;
      if (routes == null || routes.isEmpty) return null;
      final route = routes.first as Map<String, dynamic>;
      final points = _extractPolylineFromSteps(route) ?? _extractOverviewPolyline(route);
      if (points == null || points.isEmpty) return null;

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
      final withSteps = DirectionsResultWithSteps(result: result, steps: steps);
      _routeWithStepsCache[key] = (data: withSteps, expiredAt: DateTime.now().add(_cacheDuration));
      return withSteps;
    } catch (_) {
      return null;
    }
  }

  /// Ambil semua alternatif rute dari origin ke destination.
  /// Hasil di-cache 1 jam per origin-destination (hemat API).
  static Future<List<DirectionsResult>> getAlternativeRoutes({
    required double originLat,
    required double originLng,
    required double destLat,
    required double destLng,
  }) async {
    _evictExpiredCache();
    final key = _cacheKey(originLat, originLng, destLat, destLng);
    final cached = _altRouteCache[key];
    if (cached != null && cached.expiredAt.isAfter(DateTime.now())) {
      return cached.results;
    }

    final uri = Uri.parse(_baseUrl).replace(
      queryParameters: {
        'origin': '$originLat,$originLng',
        'destination': '$destLat,$destLng',
        'mode': 'driving',
        'alternatives': 'true', // Request alternatif rute
        'key': MapsConfig.directionsApiKey,
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
      if (response.statusCode != 200) return [];
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final status = data['status'] as String?;
      if (status != 'OK') return [];
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
        _altRouteCache[key] = (results: results, expiredAt: DateTime.now().add(_cacheDuration));
      }
      return results;
    } catch (_) {
      return [];
    }
  }

  /// Ambil alternatif rute dengan steps (untuk ganti rute saat navigasi).
  static Future<List<DirectionsResultWithSteps>> getAlternativeRoutesWithSteps({
    required double originLat,
    required double originLng,
    required double destLat,
    required double destLng,
  }) async {
    _evictExpiredCache();
    final key = _cacheKey(originLat, originLng, destLat, destLng);
    final cached = _altRouteWithStepsCache[key];
    if (cached != null && cached.expiredAt.isAfter(DateTime.now())) {
      return cached.results;
    }

    final uri = Uri.parse(_baseUrl).replace(
      queryParameters: {
        'origin': '$originLat,$originLng',
        'destination': '$destLat,$destLng',
        'mode': 'driving',
        'alternatives': 'true',
        'key': MapsConfig.directionsApiKey,
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
      if (response.statusCode != 200) return [];
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final status = data['status'] as String?;
      if (status != 'OK') return [];
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
          if (dist != null) {
            distanceKm = ((dist['value'] as num?) ?? 0) / 1000;
            distanceText = (dist['text'] as String?) ?? '${distanceKm.toStringAsFixed(1)} km';
          }
          if (dur != null) {
            durationSeconds = (dur['value'] as num?)?.toInt() ?? 0;
            durationText = (dur['text'] as String?) ?? '-';
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
        results.add(DirectionsResultWithSteps(result: result, steps: steps));
      }
      if (results.isNotEmpty) {
        _altRouteWithStepsCache[key] = (results: results, expiredAt: DateTime.now().add(_cacheDuration));
      }
      return results;
    } catch (_) {
      return [];
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
