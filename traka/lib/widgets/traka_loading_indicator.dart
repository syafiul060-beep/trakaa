import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Gaya trek di belakang busur animasi.
enum TrakaLoadingVariant {
  /// Scaffold / kartu terang — trek dari warna primer (halus).
  onLightSurface,
  /// Scrim gelap (overlay login, OCR) — trek putih transparan.
  onDimmedBackdrop,
}

/// Indikator muat bermerek Traka: busur gradien biru → teal berputar (tanpa kotak putih).
///
/// Dipakai menggantikan [CircularProgressIndicator] di overlay dan layar muat penuh.
class TrakaLoadingIndicator extends StatefulWidget {
  const TrakaLoadingIndicator({
    super.key,
    this.size = 40,
    this.strokeWidth,
    this.variant = TrakaLoadingVariant.onLightSurface,
    this.primary,
    this.secondary,
  });

  final double size;
  final double? strokeWidth;
  final TrakaLoadingVariant variant;
  final Color? primary;
  final Color? secondary;

  @override
  State<TrakaLoadingIndicator> createState() => _TrakaLoadingIndicatorState();
}

class _TrakaLoadingIndicatorState extends State<TrakaLoadingIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1050),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primary = widget.primary ?? theme.colorScheme.primary;
    final secondary = widget.secondary ?? theme.colorScheme.secondary;
    final track = widget.variant == TrakaLoadingVariant.onDimmedBackdrop
        ? Colors.white.withValues(alpha: 0.22)
        : primary.withValues(alpha: 0.14);
    final sw = widget.strokeWidth ??
        (widget.size * 0.11).clamp(2.0, 5.0).toDouble();

    return RepaintBoundary(
      child: SizedBox(
        width: widget.size,
        height: widget.size,
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, child) {
            return CustomPaint(
              painter: _TrakaArcPainter(
                rotation: _controller.value,
                primary: primary,
                secondary: secondary,
                trackColor: track,
                strokeWidth: sw,
              ),
            );
          },
        ),
      ),
    );
  }
}

class _TrakaArcPainter extends CustomPainter {
  _TrakaArcPainter({
    required this.rotation,
    required this.primary,
    required this.secondary,
    required this.trackColor,
    required this.strokeWidth,
  });

  final double rotation;
  final Color primary;
  final Color secondary;
  final Color trackColor;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.shortestSide - strokeWidth) / 2;

    final trackPaint = Paint()
      ..color = trackColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;
    canvas.drawCircle(center, radius, trackPaint);

    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(rotation * 2 * math.pi);
    canvas.translate(-center.dx, -center.dy);

    final rect = Rect.fromCircle(center: center, radius: radius);
    final arcPaint = Paint()
      ..shader = SweepGradient(
        startAngle: -math.pi / 2,
        endAngle: math.pi * 3 / 2,
        colors: [
          primary.withValues(alpha: 0.2),
          primary,
          secondary,
          primary.withValues(alpha: 0.35),
        ],
        stops: const [0.0, 0.38, 0.62, 1.0],
      ).createShader(rect)
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    final inset = strokeWidth / 2;
    final arcRect = rect.deflate(inset);
    canvas.drawArc(
      arcRect,
      -math.pi / 2,
      math.pi * 1.68,
      false,
      arcPaint,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _TrakaArcPainter oldDelegate) {
    return oldDelegate.rotation != rotation ||
        oldDelegate.strokeWidth != strokeWidth ||
        oldDelegate.primary != primary ||
        oldDelegate.secondary != secondary ||
        oldDelegate.trackColor != trackColor;
  }
}

/// Konten vertikal standar: loader + teks opsional (untuk overlay gelap).
class TrakaLoadingMessageColumn extends StatelessWidget {
  const TrakaLoadingMessageColumn({
    super.key,
    required this.message,
    this.subMessage,
    this.footer,
    this.indicatorSize = 48,
  });

  final String message;
  final String? subMessage;
  final Widget? footer;
  final double indicatorSize;

  @override
  Widget build(BuildContext context) {
    final subStyle = Theme.of(context).textTheme.bodySmall?.copyWith(
          color: Colors.white.withValues(alpha: 0.78),
          height: 1.35,
        );
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        TrakaLoadingIndicator(
          size: indicatorSize,
          variant: TrakaLoadingVariant.onDimmedBackdrop,
          primary: AppTheme.primaryLight,
          secondary: AppTheme.secondary,
        ),
        const SizedBox(height: 20),
        Text(
          message,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.95),
            fontSize: 16,
            fontWeight: FontWeight.w600,
            height: 1.3,
            shadows: const [
              Shadow(
                color: Colors.black38,
                blurRadius: 8,
                offset: Offset(0, 1),
              ),
            ],
          ),
        ),
        if (subMessage != null && subMessage!.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            subMessage!,
            textAlign: TextAlign.center,
            style: subStyle,
          ),
        ],
        if (footer != null) ...[
          const SizedBox(height: 8),
          footer!,
        ],
      ],
    );
  }
}

/// Di tengah layar (scaffold/list) — ganti `Center(child: CircularProgressIndicator())`.
Widget trakaPageLoadingCenter({double size = 48}) => Center(
      child: TrakaLoadingIndicator(
        size: size,
        variant: TrakaLoadingVariant.onLightSurface,
      ),
    );

/// Latar gelap (viewer hitam, kamera, tombol primer) — busur putih / biru muda.
Widget trakaLoadingOnDarkSurface({
  double size = 40,
  Color primary = Colors.white,
  Color? secondary,
}) =>
    TrakaLoadingIndicator(
      size: size,
      variant: TrakaLoadingVariant.onDimmedBackdrop,
      primary: primary,
      secondary: secondary ?? AppTheme.primaryLight,
    );
