/// Konstanta aplikasi Traka - hindari magic numbers/strings.
class AppConstants {
  AppConstants._();

  /// Tarif per km default (Rp) jika tidak ada di Firestore app_config/settings.
  static const int defaultTarifPerKm = 50;

  /// Cache extent untuk ListView (px) - optimasi performa.
  static const double listViewCacheExtent = 200;

  /// Limit pagination default.
  static const int defaultPageSize = 20;

  /// Timeout network request (detik).
  static const int networkTimeoutSeconds = 30;

  /// Threshold isMoving penumpang (detik): update lokasi driver dalam X detik = bergerak.
  /// Driver update 1-2 detik saat jalan; 8 detik memberi buffer untuk latency.
  static const int penumpangIsMovingThresholdSeconds = 8;

  /// Package name untuk Google Play.
  static const String packageName = 'id.traka.app';
}
