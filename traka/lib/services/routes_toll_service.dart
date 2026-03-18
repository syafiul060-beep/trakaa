import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/maps_config.dart';
import '../utils/retry_utils.dart';

/// Fetch estimasi biaya tol dari Google Routes API.
/// Directions API tidak menyediakan info tol; perlu Routes API.
class RoutesTollService {
  RoutesTollService._();

  static const String _baseUrl =
      'https://routes.googleapis.com/directions/v2:computeRoutes';

  /// Ambil estimasi biaya tol untuk rute origin → destination.
  /// Returns null jika tidak ada tol atau API gagal.
  static Future<String?> getTollEstimate({
    required double originLat,
    required double originLng,
    required double destLat,
    required double destLng,
  }) async {
    final body = {
      'origin': {
        'location': {'latLng': {'latitude': originLat, 'longitude': originLng}},
      },
      'destination': {
        'location': {'latLng': {'latitude': destLat, 'longitude': destLng}},
      },
      'travelMode': 'DRIVE',
      'extraComputations': ['TOLLS'],
      'routeModifiers': {
        'vehicleInfo': {'emissionType': 'GASOLINE'},
      },
    };

    try {
      final response = await RetryUtils.withRetry(() async {
        final r = await http.post(
          Uri.parse(_baseUrl),
          headers: {
            'Content-Type': 'application/json',
            'X-Goog-Api-Key': MapsConfig.directionsApiKey,
            'X-Goog-FieldMask': 'routes.travelAdvisory.tollInfo',
          },
          body: jsonEncode(body),
        );
        if (r.statusCode >= 500 || r.statusCode == 429) {
          throw Exception('HTTP ${r.statusCode}');
        }
        return r;
      });

      if (response.statusCode != 200) return null;
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final routes = data['routes'] as List<dynamic>?;
      if (routes == null || routes.isEmpty) return null;

      final route = routes.first as Map<String, dynamic>;
      final advisory = route['travelAdvisory'] as Map<String, dynamic>?;
      final tollInfo = advisory?['tollInfo'] as Map<String, dynamic>?;
      if (tollInfo == null) return null;

      final prices = tollInfo['estimatedPrice'] as List<dynamic>?;
      if (prices == null || prices.isEmpty) return null;

      final price = prices.first as Map<String, dynamic>;
      final currency = price['currencyCode'] as String? ?? 'IDR';
      final units = (price['units'] as num?)?.toInt() ?? 0;
      final nanos = (price['nanos'] as num?)?.toInt() ?? 0;
      final total = units + nanos / 1e9;

      if (currency == 'IDR') {
        final rp = total.round();
        return 'Tol ~Rp ${rp.toString().replaceAllMapped(
              RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
              (m) => '${m[1]}.',
            )}';
      }
      return 'Tol ~$currency ${total.toStringAsFixed(2)}';
    } catch (_) {
      return null;
    }
  }
}
