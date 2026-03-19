import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

/// Overlay marker driver dengan animasi: morph dot→arrow, pulse idle.
/// Pakai overlay Flutter (bukan Marker) agar bisa animasi halus.
class DriverMarkerOverlay extends StatefulWidget {
  const DriverMarkerOverlay({
    super.key,
    required this.position,
    required this.heading,
    required this.isMoving,
    required this.streetName,
    required this.mapController,
    required this.visible,
  });

  final LatLng? position;
  final double heading;
  final bool isMoving;
  final String streetName;
  final GoogleMapController? mapController;
  final bool visible;

  @override
  State<DriverMarkerOverlay> createState() => _DriverMarkerOverlayState();
}

class _DriverMarkerOverlayState extends State<DriverMarkerOverlay>
    with SingleTickerProviderStateMixin {
  double? _screenX;
  double? _screenY;
  Timer? _updateTimer;
  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat(reverse: true);
    _startUpdateLoop();
    WidgetsBinding.instance.addPostFrameCallback((_) => _updateScreenPosition());
  }

  void _startUpdateLoop() {
    _updateTimer?.cancel();
    if (!widget.visible) return;
    _updateTimer = Timer.periodic(const Duration(milliseconds: 50), (_) {
      if (mounted && widget.visible) _updateScreenPosition();
    });
  }

  Future<void> _updateScreenPosition() async {
    if (!widget.visible ||
        widget.position == null ||
        widget.mapController == null ||
        !mounted) {
      return;
    }
    try {
      final coord = await widget.mapController!
          .getScreenCoordinate(widget.position!);
      if (mounted &&
          (_screenX != coord.x.toDouble() || _screenY != coord.y.toDouble())) {
        setState(() {
          _screenX = coord.x.toDouble();
          _screenY = coord.y.toDouble();
        });
      }
    } catch (_) {}
  }

  @override
  void didUpdateWidget(DriverMarkerOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.visible != widget.visible) {
      if (widget.visible) {
        _startUpdateLoop();
      } else {
        _updateTimer?.cancel();
      }
    }
    if (oldWidget.position != widget.position) {
      _updateScreenPosition();
    }
  }

  @override
  void dispose() {
    _updateTimer?.cancel();
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.visible ||
        widget.position == null ||
        _screenX == null ||
        _screenY == null) {
      return const SizedBox.shrink();
    }

    const markerSize = 56.0;
    final left = _screenX! - markerSize / 2;
    final top = _screenY! - markerSize / 2;

    return Positioned(
      left: left,
      top: top,
      child: IgnorePointer(
        child: SizedBox(
          width: markerSize,
          height: markerSize,
          child: Transform.rotate(
            angle: widget.heading * math.pi / 180,
            child: SmoothDriverMarker(
              isMoving: widget.isMoving,
              streetName: widget.streetName,
              pulseController: _pulseController,
            ),
          ),
        ),
      ),
    );
  }
}

/// Visual: dot (pulse) atau arrow dengan morph.
class SmoothDriverMarker extends StatelessWidget {
  const SmoothDriverMarker({
    super.key,
    required this.isMoving,
    required this.streetName,
    required this.pulseController,
  });

  final bool isMoving;
  final String streetName;
  final AnimationController pulseController;

  static const Color _movingColor = Color(0xFF2F80ED);
  static const Color _idleColor = Color(0xFFEB5757);

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          switchInCurve: Curves.easeInOut,
          switchOutCurve: Curves.easeInOut,
          child: isMoving ? _buildArrow() : _buildDot(),
        ),
        if (streetName.trim().isNotEmpty) ...[
          const SizedBox(height: 2),
          Text(
            streetName.length > 14 ? '${streetName.substring(0, 13)}…' : streetName,
            style: const TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: Color(0xFF212121),
              shadows: [
                Shadow(color: Colors.white, blurRadius: 2),
                Shadow(color: Colors.white, blurRadius: 4),
              ],
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
          ),
        ],
      ],
    );
  }

  Widget _buildDot() {
    return ScaleTransition(
      scale: Tween<double>(begin: 1.0, end: 1.15).animate(
        CurvedAnimation(parent: pulseController, curve: Curves.easeInOut),
      ),
      child: Container(
        key: const ValueKey('dot'),
        width: 16,
        height: 16,
        decoration: BoxDecoration(
          color: _idleColor,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: _idleColor.withValues(alpha: 0.4),
              blurRadius: 8,
              spreadRadius: 1,
            ),
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.2),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildArrow() {
    return Container(
      key: const ValueKey('arrow'),
      width: 24,
      height: 40,
      decoration: BoxDecoration(
        boxShadow: [
          BoxShadow(
            color: _movingColor.withValues(alpha: 0.3),
            blurRadius: 6,
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.2),
            blurRadius: 5,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: CustomPaint(
        painter: _ArrowShapePainter(color: _movingColor),
        size: const Size(24, 40),
      ),
    );
  }
}

/// Panah rounded biru + heading cone (ujung atas = arah).
class _ArrowShapePainter extends CustomPainter {
  _ArrowShapePainter({required this.color});
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    const coneH = 12.0;
    final arrowTop = coneH;
    final arrowH = h - coneH;

    // Heading cone (segitiga transparan di depan panah)
    final conePath = Path()
      ..moveTo(w / 2, 0)
      ..lineTo(0, coneH)
      ..lineTo(w, coneH)
      ..close();
    canvas.drawPath(
      conePath,
      Paint()..color = color.withValues(alpha: 0.12),
    );

    // Arrow body (dari coneH ke h)
    final path = Path();
    path.moveTo(w / 2, arrowTop);
    path.lineTo(w * 0.85, arrowTop + arrowH * 0.55);
    path.quadraticBezierTo(
      w,
      arrowTop + arrowH * 0.7,
      w * 0.75,
      arrowTop + arrowH,
    );
    path.lineTo(w * 0.25, arrowTop + arrowH);
    path.quadraticBezierTo(
      0,
      arrowTop + arrowH * 0.7,
      w * 0.15,
      arrowTop + arrowH * 0.55,
    );
    path.close();
    canvas.drawPath(path, Paint()..color = color);
  }

  @override
  bool shouldRepaint(covariant _ArrowShapePainter oldDelegate) =>
      oldDelegate.color != color;
}
