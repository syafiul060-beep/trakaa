/// Konfigurasi Google Maps & Directions API.
/// Aktifkan "Directions API" di Google Cloud Console untuk rute perjalanan.
///
/// API key WAJIB di-set saat build: --dart-define=MAPS_API_KEY=xxx
/// Contoh: flutter build apk --dart-define=MAPS_API_KEY=AIzaSy...
class MapsConfig {
  MapsConfig._();

  /// API key untuk Google Directions API (sama dengan Maps SDK).
  /// Baca dari --dart-define=MAPS_API_KEY. WAJIB di-set saat build production.
  static String get directionsApiKey =>
      const String.fromEnvironment('MAPS_API_KEY', defaultValue: '');
}
