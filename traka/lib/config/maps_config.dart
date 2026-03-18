/// Konfigurasi Google Maps & Directions API.
/// Aktifkan "Directions API" di Google Cloud Console untuk rute perjalanan.
///
/// API key: gunakan --dart-define=MAPS_API_KEY=xxx saat build untuk production.
/// Contoh: flutter build apk --dart-define=MAPS_API_KEY=AIzaSy...
class MapsConfig {
  MapsConfig._();

  static const String _defaultMapsKey =
      'AIzaSyAZ8nJZwU7lrxsDN1MZTbUCJaApUwY6b4M';

  /// API key untuk Google Directions API (sama dengan Maps SDK).
  /// Baca dari --dart-define=MAPS_API_KEY, fallback ke default (aplikasi Traka).
  static String get directionsApiKey =>
      const String.fromEnvironment('MAPS_API_KEY', defaultValue: _defaultMapsKey);
}
