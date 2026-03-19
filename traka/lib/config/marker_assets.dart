/// Konfigurasi asset marker driver (central config, mudah di-switch).
/// Asset dari assets/images/traka_map_icons/ (dari ChatGPT):
///
/// 🔴 idle → dot merah (pulse ready)
/// 🔵 movingBasic → arrow biru (pelan)
/// 🧭 movingPremium → arrow + cone (cepat, premium)
class MarkerAssets {
  MarkerAssets._();

  static const String _base = 'assets/images/traka_map_icons';

  /// Idle: dot merah dengan pulse/ripple.
  static const String idle = '$_base/map_dot_red_smooth_v2.png';

  /// Moving basic: arrow biru (untuk kecepatan rendah).
  static const String movingBasic = '$_base/map_arrow_blue_smooth_v2.png';

  /// Moving premium: arrow + cone (untuk kecepatan tinggi).
  static const String movingPremium = '$_base/map_ultra_arrow_cone.png';

  /// Ambil asset berdasarkan kecepatan (km/jam).
  /// speed < 2 → idle
  /// speed < 10 → basic
  /// speed >= 10 → premium
  static String forSpeed(double speedKmh) {
    if (speedKmh < 2) return idle;
    if (speedKmh < 10) return movingBasic;
    return movingPremium;
  }

  /// Tier untuk cache key: 0=idle, 1=basic, 2=premium.
  static int speedTier(double speedKmh) {
    if (speedKmh < 2) return 0;
    if (speedKmh < 10) return 1;
    return 2;
  }
}
