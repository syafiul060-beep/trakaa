import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:sensors_plus/sensors_plus.dart';

/// Memetakan kemiringan fisik HP (gravitasi dari akselerometer) ke offset tilt kamera peta
/// saat navigasi — nuansa mirip Google Maps 3D: condong ke depan/belakang mengubah sudut pandang.
///
/// Hanya Android/iOS; web/desktop tidak memakai sensor.
class MapDeviceTiltService extends ChangeNotifier {
  MapDeviceTiltService._();
  static final MapDeviceTiltService instance = MapDeviceTiltService._();

  static bool get supportsPlatform =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  StreamSubscription<AccelerometerEvent>? _sub;
  Orientation _orientation = Orientation.portrait;
  bool _backgroundPaused = false;

  double _offsetDeg = 0;
  double _smooth = 0;

  /// Offset ditambahkan ke tilt dasar navigasi (derajat).
  double get offsetDegrees => _offsetDeg;

  void setOrientation(Orientation orientation) {
    if (_orientation == orientation) return;
    _orientation = orientation;
  }

  /// Matikan sampling saat app di background (hemat baterai). Sub di-cancel; resume lewat [startListening].
  void setBackgroundPaused(bool paused) {
    if (_backgroundPaused == paused) return;
    _backgroundPaused = paused;
    if (paused) {
      _sub?.cancel();
      _sub = null;
      final had = _offsetDeg != 0;
      _smooth = 0;
      _offsetDeg = 0;
      if (had) {
        notifyListeners();
      }
    }
  }

  bool get isBackgroundPaused => _backgroundPaused;

  void startListening() {
    if (!supportsPlatform || _backgroundPaused || _sub != null) return;
    try {
      _sub = accelerometerEventStream(
        samplingPeriod: SensorInterval.normalInterval,
      ).listen(_onAccel, onError: (_) {});
    } catch (_) {
      _sub = null;
    }
  }

  void stopListening() {
    _sub?.cancel();
    _sub = null;
    _smooth = 0;
    final had = _offsetDeg != 0;
    _offsetDeg = 0;
    if (had) {
      notifyListeners();
    }
  }

  void _onAccel(AccelerometerEvent e) {
    if (_backgroundPaused) return;
    final x = e.x;
    final y = e.y;
    final z = e.z;
    final mag = math.sqrt(x * x + y * y + z * z);
    if (mag < 4.0 || mag > 14.0) return;

    final xN = x / mag;
    final yN = y / mag;
    final zN = z / mag;

    // Portrait: nod maju/mundur → atan2(z, y). Landscape: sumbu pendek jadi x.
    final double pitch = _orientation == Orientation.portrait
        ? math.atan2(zN, yN)
        : math.atan2(zN, xN);

    // Skala empiris: ~0 rad ≈ tegak di pegangan; positif ≈ layar lebih «menghadap jalan».
    const neutral = 0.1;
    final rawDeg = ((pitch - neutral) / 0.55 * 14.0).clamp(-14.0, 18.0);
    // Lebih halus + ambang lebih besar → kurangi «denyut» di mobil/holder.
    const alpha = 0.09;
    _smooth += (rawDeg - _smooth) * alpha;
    final next = _smooth.clamp(-12.0, 16.0);
    if ((next - _offsetDeg).abs() > 0.52) {
      _offsetDeg = next;
      notifyListeners();
    }
  }
}
