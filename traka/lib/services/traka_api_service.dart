import 'dart:async';
import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:http_certificate_pinning/http_certificate_pinning.dart';

import '../config/traka_api_config.dart';
import '../utils/retry_utils.dart';

/// HTTP client untuk Traka Backend API.
/// Digunakan untuk driver_status (Redis) saat hybrid aktif.
/// Tahap 6: Certificate pinning opsional via TRAKA_API_CERT_SHA256.
class TrakaApiService {
  TrakaApiService._();

  static String get _base => TrakaApiConfig.apiBaseUrl;
  static bool get _enabled => TrakaApiConfig.isApiEnabled;

  static SecureHttpClient? _pinnedClient;
  static SecureHttpClient get _secureClient {
    _pinnedClient ??= SecureHttpClient.build([
      TrakaApiConfig.certificateSha256Fingerprint.trim(),
    ]);
    return _pinnedClient!;
  }

  static Future<http.Response> _httpGet(Uri uri, {Map<String, String>? headers}) async {
    if (TrakaApiConfig.isCertificatePinningEnabled) {
      return await _secureClient.get(uri, headers: headers);
    }
    return await http.get(uri, headers: headers);
  }

  static Future<http.Response> _httpPost(Uri uri, {Map<String, String>? headers, Object? body}) async {
    if (TrakaApiConfig.isCertificatePinningEnabled) {
      return await _secureClient.post(uri, headers: headers, body: body);
    }
    return await http.post(uri, headers: headers, body: body);
  }

  static Future<http.Response> _httpDelete(Uri uri, {Map<String, String>? headers}) async {
    if (TrakaApiConfig.isCertificatePinningEnabled) {
      return await _secureClient.delete(uri, headers: headers);
    }
    return await http.delete(uri, headers: headers);
  }

  static Future<http.Response> _httpPatch(Uri uri, {Map<String, String>? headers, Object? body}) async {
    if (TrakaApiConfig.isCertificatePinningEnabled) {
      return await _secureClient.patch(uri, headers: headers, body: body);
    }
    return await http.patch(uri, headers: headers, body: body);
  }

  static Future<String?> _getIdToken() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return null;
    try {
      return await user.getIdToken();
    } catch (_) {
      return null;
    }
  }

  static Future<Map<String, String>> _authHeaders() async {
    final token = await _getIdToken();
    final headers = <String, String>{
      'Content-Type': 'application/json',
    };
    if (token != null) {
      headers['Authorization'] = 'Bearer $token';
    }
    return headers;
  }

  /// POST /api/driver/location - Update lokasi driver.
  static Future<bool> postDriverLocation(Map<String, dynamic> body) async {
    if (!_enabled) return false;
    try {
      return await RetryUtils.withRetry(() async {
        final res = await _httpPost(
          Uri.parse('$_base/api/driver/location'),
          headers: await _authHeaders(),
          body: _jsonEncode(body),
        );
        if (res.statusCode >= 500 || res.statusCode == 429) {
          throw Exception('HTTP ${res.statusCode}');
        }
        return res.statusCode == 200;
      });
    } catch (e) {
      if (kDebugMode) debugPrint('TrakaApiService.postDriverLocation: $e');
      return false;
    }
  }

  /// PATCH /api/driver/status - Partial update (Tahap 4.1: currentPassengerCount).
  static Future<bool> patchDriverStatus({
    required int currentPassengerCount,
  }) async {
    if (!_enabled) return false;
    try {
      final res = await _httpPatch(
        Uri.parse('$_base/api/driver/status'),
        headers: await _authHeaders(),
        body: _jsonEncode({'currentPassengerCount': currentPassengerCount}),
      );
      if (res.statusCode >= 500 || res.statusCode == 429) {
        throw Exception('HTTP ${res.statusCode}');
      }
      return res.statusCode == 200;
    } catch (e) {
      if (kDebugMode) debugPrint('TrakaApiService.patchDriverStatus: $e');
      return false;
    }
  }

  /// DELETE /api/driver/status - Hapus status driver.
  static Future<bool> deleteDriverStatus() async {
    if (!_enabled) return false;
    try {
      return await RetryUtils.withRetry(() async {
        final res = await _httpDelete(
          Uri.parse('$_base/api/driver/status'),
          headers: await _authHeaders(),
        );
        if (res.statusCode >= 500 || res.statusCode == 429) {
          throw Exception('HTTP ${res.statusCode}');
        }
        return res.statusCode == 200;
      });
    } catch (e) {
      if (kDebugMode) debugPrint('TrakaApiService.deleteDriverStatus: $e');
      return false;
    }
  }

  /// GET /api/driver/:uid/status - Ambil status driver tunggal.
  static Future<Map<String, dynamic>?> getDriverStatus(String uid) async {
    if (!_enabled) return null;
    try {
      final res = await RetryUtils.withRetry(() async {
        final r = await _httpGet(
          Uri.parse('$_base/api/driver/$uid/status'),
        );
        if (r.statusCode >= 500 || r.statusCode == 429) {
          throw Exception('HTTP ${r.statusCode}');
        }
        return r;
      });
      if (res.statusCode != 200) return null;
      return _jsonDecode(res.body) as Map<String, dynamic>?;
    } catch (e) {
      if (kDebugMode) debugPrint('TrakaApiService.getDriverStatus: $e');
      return null;
    }
  }

  /// GET /api/match/drivers – driver terdekat dari titik pickup (#9, Tahap 2).
  /// Tidak perlu auth. Returns [{ uid, distance, ...driverStatus }].
  static Future<List<Map<String, dynamic>>> getMatchDrivers({
    required double lat,
    required double lng,
    String? city,
    double radiusKm = 5,
    int limit = 30,
    int? minCapacity,
  }) async {
    if (!_enabled) return [];
    try {
      final query = <String, String>{
        'lat': lat.toString(),
        'lng': lng.toString(),
        if (city != null && city.isNotEmpty) 'city': city,
        'radius': radiusKm.toString(),
        'limit': limit.toString(),
        if (minCapacity != null && minCapacity > 0) 'minCapacity': minCapacity.toString(),
      };
      final uri = Uri.parse('$_base/api/match/drivers').replace(queryParameters: query);
      final res = await _httpGet(uri);
      if (res.statusCode != 200) return [];
      final data = _jsonDecode(res.body) as Map<String, dynamic>?;
      final list = data?['drivers'] as List<dynamic>?;
      if (list == null) return [];
      return list
          .whereType<Map<String, dynamic>>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    } catch (e) {
      if (kDebugMode) debugPrint('TrakaApiService.getMatchDrivers: $e');
      return [];
    }
  }

  /// GET /api/driver/status - Daftar semua driver aktif.
  static Future<List<Map<String, dynamic>>> getDriverStatusList() async {
    if (!_enabled) return [];
    try {
      final res = await RetryUtils.withRetry(() async {
        final r = await _httpGet(
          Uri.parse('$_base/api/driver/status'),
        );
        if (r.statusCode >= 500 || r.statusCode == 429) {
          throw Exception('HTTP ${r.statusCode}');
        }
        return r;
      });
      if (res.statusCode != 200) return [];
      final data = _jsonDecode(res.body) as Map<String, dynamic>?;
      final list = data?['drivers'] as List<dynamic>?;
      if (list == null) return [];
      return list
          .whereType<Map<String, dynamic>>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    } catch (e) {
      if (kDebugMode) debugPrint('TrakaApiService.getDriverStatusList: $e');
      return [];
    }
  }

  /// Stream status driver via polling (setiap 4 detik).
  static Stream<Map<String, dynamic>?> streamDriverStatus(String driverUid) async* {
    if (!_enabled) return;

    yield await getDriverStatus(driverUid);
    await for (final _ in Stream.periodic(const Duration(seconds: 4))) {
      yield await getDriverStatus(driverUid);
    }
  }

  static String _jsonEncode(Map<String, dynamic> obj) {
    return jsonEncode(obj);
  }

  static dynamic _jsonDecode(String str) {
    try {
      return jsonDecode(str);
    } catch (_) {
      return null;
    }
  }
}
