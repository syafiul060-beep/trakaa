import 'package:geocoding/geocoding.dart' as geo;

export 'package:geocoding/geocoding.dart' show Location, Placemark;

/// Service terpusat untuk geocoding (alamat ↔ koordinat).
/// Menggantikan panggilan langsung ke [geo.locationFromAddress] dan [geo.placemarkFromCoordinates].
/// Persiapan untuk Tahap 2 Geocoding (Google Geocoding API fallback).
class GeocodingService {
  GeocodingService._();

  /// Alamat → koordinat. Tambah ", Indonesia" jika [appendIndonesia] true (default).
  static Future<List<geo.Location>> locationFromAddress(
    String address, {
    bool appendIndonesia = true,
  }) async {
    final query = address.trim();
    if (query.isEmpty) return [];
    final fullQuery = appendIndonesia ? '$query, Indonesia' : query;
    return geo.locationFromAddress(fullQuery);
  }

  /// Koordinat → alamat (placemarks).
  static Future<List<geo.Placemark>> placemarkFromCoordinates(
    double latitude,
    double longitude,
  ) {
    return geo.placemarkFromCoordinates(latitude, longitude);
  }

  /// Alamat → koordinat tanpa suffix ", Indonesia".
  static Future<List<geo.Location>> locationFromAddressRaw(String address) {
    return geo.locationFromAddress(address.trim());
  }
}
