/// Konfigurasi asset marker driver (central config, mudah di-switch).
/// Asset dari assets/images/traka_map_icons/ (dari ChatGPT):
///
/// 🔴 idle → dot merah (pulse ready)
/// 🧭 bergerak → cone saja (`map_ultra_arrow_cone.png`); panah biru tidak dipakai.
class MarkerAssets {
  MarkerAssets._();

  static const String _base = 'assets/images/traka_map_icons';

  /// Idle: dot merah dengan pulse/ripple.
  static const String idle = '$_base/map_dot_red_smooth_v2.png';

  /// Opsi lama (pelan): tidak dipakai [forSpeed]; tetap ada jika ingin balik ke mode 3-tier.
  static const String movingBasic = '$_base/map_arrow_blue_smooth_v2.png';

  /// Bergerak: arrow + cone (satu ikon untuk semua kecepatan jalan).
  static const String movingPremium = '$_base/map_ultra_arrow_cone.png';

  /// Di bawah ini (km/j) → dot merah; di atas → cone.
  static const double idleMaxKmh = 2.0;

  /// Ambil asset berdasarkan kecepatan (km/jam).
  static String forSpeed(double speedKmh) {
    if (speedKmh < idleMaxKmh) return idle;
    return movingPremium;
  }

  /// Tier untuk cache key: 0=idle (dot), 2=cone (sama tier lama “premium”).
  static int speedTier(double speedKmh) {
    if (speedKmh < idleMaxKmh) return 0;
    return 2;
  }
}
