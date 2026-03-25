import 'dart:async';
import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:http_certificate_pinning/http_certificate_pinning.dart';

import '../config/traka_api_config.dart';
import '../utils/retry_utils.dart';

/// Hasil [createPassengerOrderViaApi]: id order atau fallback ke Firestore lokal.
typedef CreateOrderApiResult = ({String? orderId, bool fallBackToFirestore});

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

  /// POST /api/realtime/ws-ticket — tiket HMAC untuk Socket.IO worker (Tahap 4).
  /// Null jika API tidak mengonfigurasi secret atau user belum login.
  static Future<String?> fetchRealtimeMapWsTicket() async {
    if (!_enabled) return null;
    try {
      final res = await _httpPost(
        Uri.parse('$_base/api/realtime/ws-ticket'),
        headers: await _authHeaders(),
      );
      if (res.statusCode == 503) {
        if (kDebugMode) {
          debugPrint(
            'TrakaApiService.fetchRealtimeMapWsTicket: server ticket not configured (503)',
          );
        }
        return null;
      }
      if (res.statusCode != 200) return null;
      final map = jsonDecode(res.body);
      if (map is! Map<String, dynamic>) return null;
      final t = map['ticket'];
      if (t is! String) return null;
      final trimmed = t.trim();
      return trimmed.isEmpty ? null : trimmed;
    } catch (e) {
      if (kDebugMode) debugPrint('TrakaApiService.fetchRealtimeMapWsTicket: $e');
      return null;
    }
  }

  /// PATCH /api/driver/status - Partial update (Tahap 4.1: currentPassengerCount).
  static Future<bool> patchDriverStatus({
    required int currentPassengerCount,
  }) async {
    if (!_enabled) return false;
    try {
      return await RetryUtils.withRetry(() async {
        final res = await _httpPatch(
          Uri.parse('$_base/api/driver/status'),
          headers: await _authHeaders(),
          body: _jsonEncode({'currentPassengerCount': currentPassengerCount}),
        );
        if (res.statusCode >= 500 || res.statusCode == 429) {
          throw Exception('HTTP ${res.statusCode}');
        }
        return res.statusCode == 200;
      }, maxAttempts: 3, baseDelayMs: 400);
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

  /// POST /api/orders — buat order (penumpang). Dual-write di server; butuh hybrid + [TrakaApiConfig.createOrderViaApi].
  static Future<CreateOrderApiResult> createPassengerOrderViaApi(
    Map<String, dynamic> body,
  ) async {
    if (!TrakaApiConfig.shouldCreateOrderViaApi) {
      return (orderId: null, fallBackToFirestore: true);
    }
    try {
      final res = await _httpPost(
        Uri.parse('$_base/api/orders'),
        headers: await _authHeaders(),
        body: _jsonEncode(body),
      );
      if (res.statusCode == 201) {
        final m = _jsonDecode(res.body) as Map<String, dynamic>?;
        final id = m?['id'] as String?;
        return (orderId: id, fallBackToFirestore: false);
      }
      if (res.statusCode == 409 ||
          res.statusCode == 403 ||
          res.statusCode == 400) {
        return (orderId: null, fallBackToFirestore: false);
      }
      if (kDebugMode) {
        debugPrint(
          'TrakaApiService.createPassengerOrderViaApi: ${res.statusCode} ${res.body}',
        );
      }
      return (orderId: null, fallBackToFirestore: true);
    } catch (e) {
      if (kDebugMode) debugPrint('TrakaApiService.createPassengerOrderViaApi: $e');
      return (orderId: null, fallBackToFirestore: true);
    }
  }

  /// GET /api/match/drivers – driver terdekat dari titik pickup (#9, Tahap 2).
  /// Tidak perlu auth. Returns [{ uid, distance, ...driverStatus }].
  static Future<List<Map<String, dynamic>>> getMatchDrivers({
    required double lat,
    required double lng,
    double? destLat,
    double? destLng,
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
        if (destLat != null) 'destLat': destLat.toString(),
        if (destLng != null) 'destLng': destLng.toString(),
        if (city != null && city.isNotEmpty) 'city': city,
        'radius': radiusKm.toString(),
        'limit': limit.toString(),
        if (minCapacity != null && minCapacity > 0) 'minCapacity': minCapacity.toString(),
      };
      final uri = Uri.parse('$_base/api/match/drivers').replace(queryParameters: query);
      return await RetryUtils.withRetry(() async {
        final res = await _httpGet(uri);
        if (res.statusCode >= 500 || res.statusCode == 429) {
          throw Exception('HTTP ${res.statusCode}');
        }
        if (res.statusCode != 200) return <Map<String, dynamic>>[];
        final data = _jsonDecode(res.body) as Map<String, dynamic>?;
        final list = data?['drivers'] as List<dynamic>?;
        if (list == null) return <Map<String, dynamic>>[];
        return list
            .whereType<Map<String, dynamic>>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
      }, maxAttempts: 3, baseDelayMs: 500);
    } catch (e) {
      if (kDebugMode) debugPrint('TrakaApiService.getMatchDrivers: $e');
      return [];
    }
  }

  /// GET /api/driver/status - Daftar semua driver aktif (paginasi hingga habis).
  static Future<List<Map<String, dynamic>>> getDriverStatusList() async {
    if (!_enabled) return [];
    final byUid = <String, Map<String, dynamic>>{};
    var cursor = 0;
    const limit = 100;
    const maxPages = 40;
    try {
      for (var page = 0; page < maxPages; page++) {
        final uri = Uri.parse('$_base/api/driver/status').replace(
          queryParameters: {
            'limit': '$limit',
            'cursor': '$cursor',
          },
        );
        final res = await RetryUtils.withRetry(() async {
          final r = await _httpGet(uri);
          if (r.statusCode >= 500 || r.statusCode == 429) {
            throw Exception('HTTP ${r.statusCode}');
          }
          return r;
        });
        if (res.statusCode != 200) break;
        final data = _jsonDecode(res.body) as Map<String, dynamic>?;
        final list = data?['drivers'] as List<dynamic>?;
        if (list == null || list.isEmpty) break;
        for (final e in list.whereType<Map<String, dynamic>>()) {
          final m = Map<String, dynamic>.from(e);
          final uid = (m['uid'] ?? m['driverUid']) as String? ?? '';
          if (uid.isNotEmpty) byUid[uid] = m;
        }
        final nextRaw = data?['nextCursor'];
        if (nextRaw == null) break;
        final next =
            nextRaw is int ? nextRaw : int.tryParse(nextRaw.toString());
        if (next == null || next == 0 || next == cursor) break;
        cursor = next;
      }
      return byUid.values.toList();
    } catch (e) {
      if (kDebugMode) debugPrint('TrakaApiService.getDriverStatusList: $e');
      return byUid.values.toList();
    }
  }

  /// GET …/api/orders/:orderId/driver-payment-methods
  static Future<List<Map<String, dynamic>>> getOrderDriverPaymentMethods(
    String orderId,
  ) async {
    if (!_enabled) return [];
    try {
      final res = await _httpGet(
        Uri.parse('$_base/api/orders/$orderId/driver-payment-methods'),
        headers: await _authHeaders(),
      );
      if (res.statusCode != 200) return [];
      final data = _jsonDecode(res.body) as Map<String, dynamic>?;
      final list = data?['methods'] as List<dynamic>?;
      if (list == null) return [];
      return list
          .whereType<Map<String, dynamic>>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    } catch (e) {
      if (kDebugMode) {
        debugPrint('TrakaApiService.getOrderDriverPaymentMethods: $e');
      }
      return [];
    }
  }

  /// GET …/api/driver/payment-methods (driver login).
  static Future<List<Map<String, dynamic>>> listMyPaymentMethods() async {
    if (!_enabled) return [];
    try {
      final res = await _httpGet(
        Uri.parse('$_base/api/driver/payment-methods'),
        headers: await _authHeaders(),
      );
      if (res.statusCode != 200) return [];
      final data = _jsonDecode(res.body) as Map<String, dynamic>?;
      final list = data?['methods'] as List<dynamic>?;
      if (list == null) return [];
      return list
          .whereType<Map<String, dynamic>>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    } catch (e) {
      if (kDebugMode) debugPrint('TrakaApiService.listMyPaymentMethods: $e');
      return [];
    }
  }

  static Future<({bool ok, String? error, Map<String, dynamic>? data})>
      createDriverPaymentMethod(Map<String, dynamic> body) async {
    if (!_enabled) {
      return (ok: false, error: 'API nonaktif', data: null);
    }
    try {
      final res = await _httpPost(
        Uri.parse('$_base/api/driver/payment-methods'),
        headers: await _authHeaders(),
        body: _jsonEncode(body),
      );
      final data = _jsonDecode(res.body) as Map<String, dynamic>?;
      if (res.statusCode == 201) {
        return (ok: true, error: null, data: data);
      }
      return (
        ok: false,
        error: data?['error'] as String? ?? 'HTTP ${res.statusCode}',
        data: data,
      );
    } catch (e) {
      return (ok: false, error: e.toString(), data: null);
    }
  }

  static Future<({bool ok, String? error})> deleteDriverPaymentMethod(
    String id,
  ) async {
    if (!_enabled) return (ok: false, error: 'API nonaktif');
    try {
      final res = await _httpDelete(
        Uri.parse('$_base/api/driver/payment-methods/$id'),
        headers: await _authHeaders(),
      );
      if (res.statusCode == 200) return (ok: true, error: null);
      final data = _jsonDecode(res.body) as Map<String, dynamic>?;
      return (
        ok: false,
        error: data?['error'] as String? ?? 'HTTP ${res.statusCode}',
      );
    } catch (e) {
      return (ok: false, error: e.toString());
    }
  }

  /// Stream status driver via polling (setiap 4 detik).
  static Stream<Map<String, dynamic>?> streamDriverStatus(String driverUid) async* {
    if (!_enabled) return;

    yield await getDriverStatus(driverUid);
    await for (final _ in Stream.periodic(const Duration(seconds: 3))) {
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
