import 'package:google_maps_flutter/google_maps_flutter.dart';

/// Mengatur follow kamera agar selaras dengan marker interpolasi (Grab-style).
///
/// Masalah klasik: `animateCamera` dipanggil tiap tick (~120 ms) dengan durasi panjang
/// sehingga banyak animasi bersamaan → kamera "nyusul" atau "ketinggalan" dari marker.
/// Engine ini:
/// - throttle interval (~480 ms) agar satu tween tidak bertumpuk
/// - durasi tween dibatasi sedikit di bawah interval agar halus tanpa overlap
/// - [resetThrottle] saat user tap fokus / resume tracking
class CameraFollowEngine {
  GoogleMapController? _controller;

  DateTime? _lastScheduledAt;

  /// Minimal jeda antar pemanggilan `animateCamera` (ms).
  /// Sedikit lebih renggang agar satu tween bisa lebih panjang → pergerakan kamera terasa halus.
  static const int minIntervalMs = 480;

  /// Durasi animasi maksimum — harus < [minIntervalMs] agar tidak bertumpuk.
  static const int maxAnimationMs = 430;

  void attach(GoogleMapController? controller) {
    _controller = controller;
  }

  void resetThrottle() {
    _lastScheduledAt = null;
  }

  /// Membatasi durasi yang dipilih screen (proporsional jarak/bearing).
  static Duration clampDuration(Duration preferred) {
    final ms = preferred.inMilliseconds.clamp(200, maxAnimationMs);
    return Duration(milliseconds: ms);
  }

  /// Jalankan animasi kamera jika lolos throttle. [force] untuk fokus / rotasi layar.
  bool tryAnimateCamera(
    CameraUpdate update, {
    Duration? duration,
    bool force = false,
  }) {
    final c = _controller;
    if (c == null) return false;

    if (!force) {
      final now = DateTime.now();
      if (_lastScheduledAt != null &&
          now.difference(_lastScheduledAt!).inMilliseconds < minIntervalMs) {
        return false;
      }
      _lastScheduledAt = now;
    } else {
      _lastScheduledAt = DateTime.now();
    }

    final dur = clampDuration(
      duration ?? const Duration(milliseconds: 300),
    );

    try {
      c.animateCamera(update, duration: dur);
    } catch (_) {}
    return true;
  }
}
