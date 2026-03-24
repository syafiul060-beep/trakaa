import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../theme/app_theme.dart';

/// Lingkaran glow berdenyut di atas peta, mengikuti posisi layar driver rekomendasi.
/// Pakai [getScreenCoordinate] + timer singkat agar tetap sinkron saat kamera/posisi berubah.
class RecommendedDriverGlowOverlay extends StatefulWidget {
  const RecommendedDriverGlowOverlay({
    super.key,
    required this.mapController,
    required this.position,
    required this.visible,
  });

  final GoogleMapController? mapController;
  final LatLng? position;
  final bool visible;

  @override
  State<RecommendedDriverGlowOverlay> createState() =>
      _RecommendedDriverGlowOverlayState();
}

class _RecommendedDriverGlowOverlayState extends State<RecommendedDriverGlowOverlay>
    with SingleTickerProviderStateMixin {
  double? _screenX;
  double? _screenY;
  Timer? _tick;
  late AnimationController _pulse;

  static const double _outerSize = 88;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);
    _scheduleLoop();
    WidgetsBinding.instance.addPostFrameCallback((_) => _syncScreen());
  }

  void _scheduleLoop() {
    _tick?.cancel();
    if (!widget.visible) return;
    // ~7 fps cukup untuk glow; 60ms × getScreenCoordinate membebani UI saat banyak overlay.
    _tick = Timer.periodic(const Duration(milliseconds: 120), (_) => _syncScreen());
  }

  Future<void> _syncScreen() async {
    if (!widget.visible ||
        widget.position == null ||
        widget.mapController == null ||
        !mounted) {
      return;
    }
    try {
      final c = await widget.mapController!.getScreenCoordinate(widget.position!);
      final nx = c.x.toDouble();
      final ny = c.y.toDouble();
      if (!mounted) return;
      if (_screenX != nx || _screenY != ny) {
        setState(() {
          _screenX = nx;
          _screenY = ny;
        });
      }
    } catch (_) {}
  }

  @override
  void didUpdateWidget(covariant RecommendedDriverGlowOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.visible != widget.visible) {
      if (widget.visible) {
        _scheduleLoop();
        _syncScreen();
      } else {
        _tick?.cancel();
        _screenX = null;
        _screenY = null;
      }
    }
    if (oldWidget.position != widget.position ||
        oldWidget.mapController != widget.mapController) {
      _syncScreen();
    }
  }

  @override
  void dispose() {
    _tick?.cancel();
    _pulse.dispose();
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

    final left = _screenX! - _outerSize / 2;
    final top = _screenY! - _outerSize / 2;
    final base = AppTheme.primary;

    return Positioned(
      left: left,
      top: top,
      child: IgnorePointer(
        child: AnimatedBuilder(
          animation: _pulse,
          builder: (context, _) {
            final t = Curves.easeInOut.transform(_pulse.value);
            final scale = 0.82 + t * 0.28;
            final opacity = 0.12 + t * 0.2;
            return SizedBox(
              width: _outerSize,
              height: _outerSize,
              child: Center(
                child: Transform.scale(
                  scale: scale,
                  child: Container(
                    width: _outerSize * 0.72,
                    height: _outerSize * 0.72,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: base.withValues(alpha: opacity),
                      boxShadow: [
                        BoxShadow(
                          color: base.withValues(alpha: opacity * 1.2),
                          blurRadius: 18,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
