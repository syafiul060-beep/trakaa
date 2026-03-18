import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Overlay lokasi driver: titik biru (diam) atau segitiga biru dalam oval putih (bergerak).
/// Icon tetap di bawah tengah; peta bergerak menurun (jalan lurus) atau berputar (belok).
class DriverLocationOverlayWidget extends StatelessWidget {
  const DriverLocationOverlayWidget({
    super.key,
    required this.bearing,
    required this.isMoving,
    this.dotSize = 28,
    this.triangleSize = 56,
  });

  /// Bearing dalam derajat (0 = utara, 90 = timur). Dipakai untuk rotasi segitiga saat bergerak.
  final double bearing;
  /// true = bergerak (segitiga), false = diam (titik biru).
  final bool isMoving;
  /// Ukuran titik biru (diam).
  final double dotSize;
  /// Ukuran oval + segitiga (bergerak).
  final double triangleSize;

  static const Color _blue = Color(0xFF4285F4);

  @override
  Widget build(BuildContext context) {
    if (isMoving) {
      return _buildTriangleInOval();
    } else {
      return _buildBlueDot();
    }
  }

  Widget _buildBlueDot() {
    return Container(
      width: dotSize,
      height: dotSize,
      decoration: BoxDecoration(
        color: _blue,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.2),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
    );
  }

  Widget _buildTriangleInOval() {
    return Transform.rotate(
      angle: (bearing * math.pi / 180),
      child: Container(
        width: triangleSize,
        height: triangleSize * 0.7,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(triangleSize / 2),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.15),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Center(
          child: CustomPaint(
            size: Size(triangleSize * 0.5, triangleSize * 0.4),
            painter: _TrianglePainter(color: _blue),
          ),
        ),
      ),
    );
  }
}

class _TrianglePainter extends CustomPainter {
  _TrianglePainter({required this.color});
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    // Segitiga mengarah ke atas (ujung di atas)
    final path = Path()
      ..moveTo(size.width / 2, 0)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
