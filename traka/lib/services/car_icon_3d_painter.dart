import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

/// Gambar icon mobil 3D secara programatik untuk marker peta.
/// Gaya referensi: glossy, pseudo-3D dengan highlight, headlight, roof rails.
class CarIcon3dPainter {
  CarIcon3dPainter._();

  /// Warna Traka: merah ceri & hijau terang (ala referensi).
  static const Color _red = Color(0xFFE53935);
  static const Color _green = Color(0xFF43A047);

  /// Gambar mobil 3D dan return BitmapDescriptor.
  /// Orientasi: depan mobil = bawah (selatan), untuk rotasi bearing.
  static Future<BitmapDescriptor> drawCarIcon({
    required double size,
    required bool isRed,
  }) async {
    final color = isRed ? _red : _green;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final s = size;

    const padding = 8.0;
    canvas.save();
    canvas.translate(padding, padding);
    final d = s - padding * 2;

    // 1. Shadow elips (efek mengambang).
    final shadowPaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.2)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5);
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(d / 2, d / 2 + 5),
        width: d * 0.65,
        height: d * 0.2,
      ),
      shadowPaint,
    );

    // 2. Body mobil (rounded rect, sedikit SUV).
    final bodyRect = Rect.fromLTWH(d * 0.1, d * 0.18, d * 0.8, d * 0.52);
    final bodyPath = RRect.fromRectAndRadius(
      bodyRect,
      Radius.circular(d * 0.1),
    );

    // Base gradient (glossy, cahaya dari atas).
    final baseGradient = LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [
        Color.lerp(color, Colors.white, 0.4)!,
        color,
        Color.lerp(color, Colors.black, 0.25)!,
      ],
      stops: const [0.0, 0.4, 1.0],
    );
    canvas.drawRRect(bodyPath, Paint()..shader = baseGradient.createShader(bodyRect));

    // 3. Highlight glossy (hotspot di hood/atap).
    final highlightRect = Rect.fromLTWH(
      bodyRect.left + d * 0.15,
      bodyRect.top + d * 0.05,
      d * 0.35,
      d * 0.2,
    );
    final highlightGradient = RadialGradient(
      center: Alignment.topLeft,
      radius: 1.2,
      colors: [
        Colors.white.withValues(alpha: 0.6),
        Colors.white.withValues(alpha: 0.2),
        Colors.transparent,
      ],
      stops: const [0.0, 0.5, 1.0],
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(highlightRect, Radius.circular(d * 0.04)),
      Paint()..shader = highlightGradient.createShader(highlightRect),
    );

    // 4. Roof rails (garis silver di atap).
    final railPaint = Paint()
      ..color = const Color(0xFFE0E0E0)
      ..strokeWidth = d * 0.03
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    final railY1 = bodyRect.top + d * 0.15;
    final railY2 = bodyRect.top + d * 0.22;
    canvas.drawLine(Offset(bodyRect.left + d * 0.12, railY1), Offset(bodyRect.right - d * 0.12, railY1), railPaint);
    canvas.drawLine(Offset(bodyRect.left + d * 0.12, railY2), Offset(bodyRect.right - d * 0.12, railY2), railPaint);

    // 5. Kaca depan & belakang (hitam reflektif).
    final windowColor = const Color(0xFF1A1A1A);
    final frontWindow = RRect.fromRectAndRadius(
      Rect.fromLTWH(bodyRect.left + d * 0.1, bodyRect.top + d * 0.08, d * 0.22, bodyRect.height * 0.45),
      Radius.circular(d * 0.03),
    );
    final rearWindow = RRect.fromRectAndRadius(
      Rect.fromLTWH(bodyRect.right - d * 0.32, bodyRect.top + d * 0.08, d * 0.22, bodyRect.height * 0.45),
      Radius.circular(d * 0.03),
    );
    canvas.drawRRect(frontWindow, Paint()..color = windowColor);
    canvas.drawRRect(rearWindow, Paint()..color = windowColor);

    // 6. Headlights (glow biru-putih di depan).
    final headlightY = bodyRect.bottom - d * 0.08;
    final headlightGlow = Paint()
      ..color = const Color(0xFFB3E5FC).withValues(alpha: 0.8)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3);
    canvas.drawCircle(Offset(bodyRect.left + d * 0.25, headlightY), d * 0.06, headlightGlow);
    canvas.drawCircle(Offset(bodyRect.right - d * 0.25, headlightY), d * 0.06, headlightGlow);
    final headlightCore = Paint()..color = const Color(0xFFE1F5FE);
    canvas.drawCircle(Offset(bodyRect.left + d * 0.25, headlightY), d * 0.035, headlightCore);
    canvas.drawCircle(Offset(bodyRect.right - d * 0.25, headlightY), d * 0.035, headlightCore);

    // 7. Spion dengan highlight.
    final mirrorRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(bodyRect.left - d * 0.02, bodyRect.top + d * 0.1, d * 0.09, d * 0.12),
      Radius.circular(d * 0.02),
    );
    final mirrorGradient = LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [
        Color.lerp(color, Colors.white, 0.2)!,
        color,
      ],
    );
    canvas.drawRRect(mirrorRect, Paint()..shader = mirrorGradient.createShader(mirrorRect.outerRect));
    final mirrorRect2 = RRect.fromRectAndRadius(
      Rect.fromLTWH(bodyRect.right - d * 0.07, bodyRect.top + d * 0.1, d * 0.09, d * 0.12),
      Radius.circular(d * 0.02),
    );
    canvas.drawRRect(mirrorRect2, Paint()..shader = mirrorGradient.createShader(mirrorRect2.outerRect));

    canvas.restore();

    final picture = recorder.endRecording();
    final img = await picture.toImage(s.round(), s.round());
    final byteData = await img.toByteData(format: ui.ImageByteFormat.png);
    img.dispose();

    if (byteData == null) {
      return BitmapDescriptor.defaultMarkerWithHue(
        isRed ? BitmapDescriptor.hueRed : BitmapDescriptor.hueGreen,
      );
    }
    return BitmapDescriptor.bytes(byteData.buffer.asUint8List());
  }
}
