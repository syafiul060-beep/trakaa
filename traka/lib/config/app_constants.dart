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

  /// Maksimal driver di map pencarian penumpang (setelah filter rute).
  static const int maxDriversOnPassengerSearchMap = 50;

  /// Durasi maksimal sesi menampilkan driver aktif di peta (menit) **sebelum** travel
  /// berstatus «agreed» (kesepakatan harga). Setelah itu tracking dihentikan (hemat baterai/API);
  /// penumpang bisa ketuk Cari / Driver sekitar lagi. Jika sudah ada kesepakatan harga,
  /// beranda diblokir penuh — aturan ini tidak menggantikan blokir tersebut.
  static const int passengerDriverSearchSessionMaxMinutes = 5;

  /// Interval interpolasi posisi multi-driver di map penumpang (ms).
  /// Sedikit lebih jarang mengurangi tekanan ke native map + hit-testing marker.
  static const int passengerMapInterpolationIntervalMs = 96;

  /// Eksponensial smoothing bearing icon mobil penumpang (0–1). Lebih kecil = lebih halus.
  static const double passengerMapBearingSmoothAlpha = 0.14;

  /// Package name untuk Google Play.
  static const String packageName = 'id.traka.app';

  /// Path dokumen matching OD + koridor (penumpang Cari travel). Lihat juga `RouteUtils`.
  static const String matchingOdCorridorDocRelative =
      'docs/MATCHING_OD_KORIDOR_PENUMPANG.md';

  /// Tracking berkala + driver aktif atau navigasi order: minta akurasi lokasi tinggi (navigasi in-app).
  static bool useHighAccuracyLocationForActiveDriverNavigation({
    required bool forTracking,
    required bool isDriverWorking,
    required bool hasNavigatingToOrder,
  }) =>
      forTracking && (isDriverWorking || hasNavigatingToOrder);
}
