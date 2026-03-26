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

  /// Banner beranda driver: saran arahkan jemput jika jarak ke titik jemput ≤ ini (meter).
  static const double driverPickupNearbyHintMaxMeters = 700;
  /// Setelah «Abaikan», saran bisa muncul lagi bila driver menjauh ≥ ini dari titik jemput lalu mendekat.
  static const double driverPickupNearbyHintReshowMeters = 1400;

  /// Maksimal driver di map pencarian penumpang (setelah filter rute).
  static const int maxDriversOnPassengerSearchMap = 50;

  /// Maks fetch Directions (Google) untuk polyline di peta beranda penumpang per sesi cari.
  /// Driver di atas batas ini tetap punya marker + posisi; tanpa polyline (hemat quota + CPU).
  static const int maxDriverDirectionsFetchesPassengerMap = 8;

  /// Durasi maksimal sesi menampilkan driver aktif di peta (menit) **sebelum** travel
  /// berstatus «agreed» (kesepakatan harga). Setelah itu tracking dihentikan (hemat baterai/API);
  /// penumpang bisa ketuk Cari / Driver sekitar lagi. Jika sudah ada kesepakatan harga,
  /// beranda diblokir penuh — aturan ini tidak menggantikan blokir tersebut.
  static const int passengerDriverSearchSessionMaxMinutes = 5;

  /// Sesi pencarian lebih lama untuk OD jarak jauh (waktu hubungi driver).
  static const int passengerDriverSearchSessionMinutesLongTrip = 10;
  static const int passengerDriverSearchSessionMinutesVeryLongTrip = 15;

  /// Menit sesi pencarian dari jarak asal–tujuan penumpang (meter). Null = gunakan [passengerDriverSearchSessionMaxMinutes].
  static int passengerDriverSearchSessionMinutesForOd(double? odMeters) {
    if (odMeters == null || odMeters < 80000) {
      return passengerDriverSearchSessionMaxMinutes;
    }
    if (odMeters < 160000) return passengerDriverSearchSessionMinutesLongTrip;
    return passengerDriverSearchSessionMinutesVeryLongTrip;
  }

  /// OD ≥ ini (meter): pencarian «searah» **tidak** memfilter «driver harus belum lewat titik jemput»
  /// (travel jauh: driver bisa di depan di jalur utama; koordinasi via chat).
  static const double passengerOdMetersRelaxDriverBeforePickupFilter = 80000;

  /// Interval interpolasi posisi multi-driver di map penumpang (ms).
  /// Timer interpolasi **dijeda** saat tab bukan beranda (Tahap 2). Naikkan bertahap (mis. 100→120) hanya setelah uji di perangkat lemah.
  static const int passengerMapInterpolationIntervalMs = 100;

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
