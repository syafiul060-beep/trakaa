import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';

import '../config/traka_lottie_assets.dart';
import '../theme/app_theme.dart';

/// Gaya trek di belakang busur animasi.
enum TrakaLoadingVariant {
  /// Scaffold / kartu terang — trek dari warna primer (halus).
  onLightSurface,
  /// Scrim gelap (overlay login, OCR) — trek putih transparan.
  onDimmedBackdrop,
}

/// Indikator muat bermerek Traka: busur gradien berputar + pusat (bawaan: kepala rangkong 3D
/// dengan kedip; atau aset desainer lewat [centerWidget]).
///
/// **Lottie:** paket `lottie` sudah ada; file default [TrakaLottieAssets.rangkongLoader]
/// (placeholder — ganti dengan animasi rangkong dari desainer). Pakai
/// `TrakaLoadingIndicator.lottie(...)` atau [centerWidget]: `Lottie.asset(...)`.
/// Widget pusat berada di **stack & transform yang sama** (napas, anggukan, mengambang).
/// **Kedip mata** (`Timer`) hanya jika mode vektor bawaan ([centerWidget] null & tanpa `.lottie`).
///
/// Dipakai menggantikan [CircularProgressIndicator] di overlay dan layar muat penuh.
class TrakaLoadingIndicator extends StatefulWidget {
  const TrakaLoadingIndicator({
    super.key,
    this.size = 48,
    this.strokeWidth,
    this.variant = TrakaLoadingVariant.onLightSurface,
    this.primary,
    this.secondary,
    this.centerWidget,
  });

  final double size;
  final double? strokeWidth;
  final TrakaLoadingVariant variant;
  final Color? primary;
  final Color? secondary;

  /// Ganti kepala vektor [CustomPainter] dengan widget dari desainer (Lottie, Rive, dll.).
  final Widget? centerWidget;

  /// Pusat loader pakai [Lottie.asset] (file default bisa diganti animasi rangkong dari desainer).
  factory TrakaLoadingIndicator.lottie({
    Key? key,
    double size = 48,
    double? strokeWidth,
    TrakaLoadingVariant variant = TrakaLoadingVariant.onLightSurface,
    Color? primary,
    Color? secondary,
    String assetPath = TrakaLottieAssets.rangkongLoader,
    String? package,
    bool repeat = true,
    bool animate = true,
  }) {
    return TrakaLoadingIndicator(
      key: key,
      size: size,
      strokeWidth: strokeWidth,
      variant: variant,
      primary: primary,
      secondary: secondary,
      centerWidget: Lottie.asset(
        assetPath,
        package: package,
        repeat: repeat,
        animate: animate,
        fit: BoxFit.contain,
      ),
    );
  }

  @override
  State<TrakaLoadingIndicator> createState() => _TrakaLoadingIndicatorState();
}

class _TrakaLoadingIndicatorState extends State<TrakaLoadingIndicator>
    with TickerProviderStateMixin {
  late final AnimationController _spinController;
  late final AnimationController _blinkController;
  Timer? _blinkTimer;

  @override
  void initState() {
    super.initState();
    _spinController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1050),
    )..repeat();
    _blinkController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 140),
    );
    if (widget.centerWidget == null) {
      _scheduleNextBlink();
    }
  }

  @override
  void didUpdateWidget(TrakaLoadingIndicator oldWidget) {
    super.didUpdateWidget(oldWidget);
    final wasVector = oldWidget.centerWidget == null;
    final nowVector = widget.centerWidget == null;
    if (wasVector && !nowVector) {
      _blinkTimer?.cancel();
      _blinkController.value = 0;
    } else if (!wasVector && nowVector) {
      _scheduleNextBlink();
    }
  }

  void _scheduleNextBlink() {
    if (widget.centerWidget != null) return;
    _blinkTimer?.cancel();
    _blinkTimer = Timer(
      Duration(milliseconds: 2200 + math.Random().nextInt(2000)),
      () {
        if (!mounted) return;
        _blinkController.forward(from: 0).whenComplete(() {
          if (mounted) _blinkController.reverse();
        });
        _scheduleNextBlink();
      },
    );
  }

  @override
  void dispose() {
    _blinkTimer?.cancel();
    _blinkController.dispose();
    _spinController.dispose();
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

    // Hanya kepala — area gambar agak besar agar casque & paruh terbaca jelas.
    final inner = (widget.size * 0.54).clamp(20.0, widget.size * 0.62);

    final listenable = widget.centerWidget == null
        ? Listenable.merge([_spinController, _blinkController])
        : _spinController;

    return RepaintBoundary(
      child: SizedBox(
        width: widget.size,
        height: widget.size,
        child: AnimatedBuilder(
          animation: listenable,
          builder: (context, child) {
            final t = _spinController.value * 2 * math.pi;
            final pulse = 1.0 + 0.05 * math.sin(t);
            final headTilt = 0.07 * math.sin(t * 0.62);
            final bobY = 1.2 * math.sin(t * 0.88);
            final useVectorBird = widget.centerWidget == null;
            final eyeOpen = useVectorBird
                ? 1.0 -
                    Curves.easeInOut.transform(_blinkController.value)
                : 1.0;

            final Widget centerContent = useVectorBird
                ? CustomPaint(
                    size: Size(inner, inner),
                    painter: _RangkongBirdPainter(eyeOpen: eyeOpen),
                  )
                : SizedBox(
                    width: inner,
                    height: inner,
                    child: FittedBox(
                      fit: BoxFit.contain,
                      alignment: Alignment.center,
                      child: widget.centerWidget!,
                    ),
                  );

            return Stack(
              alignment: Alignment.center,
              clipBehavior: Clip.none,
              children: [
                CustomPaint(
                  size: Size(widget.size, widget.size),
                  painter: _TrakaArcPainter(
                    rotation: _spinController.value,
                    primary: primary,
                    secondary: secondary,
                    trackColor: track,
                    strokeWidth: sw,
                  ),
                ),
                Transform.translate(
                  offset: Offset(0, bobY),
                  child: Transform.rotate(
                    angle: headTilt,
                    child: Transform.scale(
                      scale: pulse,
                      child: centerContent,
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// Hanya **kepala** burung rangkong (julang): gaya **kartun 3D** — bentuk rounded, gradien
/// cahaya, highlight, bayangan lembut. [eyeOpen] 1 = mata terbuka penuh, 0 = kedip.
class _RangkongBirdPainter extends CustomPainter {
  _RangkongBirdPainter({this.eyeOpen = 1.0})
      : assert(eyeOpen >= 0 && eyeOpen <= 1);

  final double eyeOpen;

  static const _casqueHi = Color(0xFFFFF3E0);
  static const _casqueMid = Color(0xFFFFCC80);
  static const _beakLight = Color(0xFFFF9100);
  static const _beakDeep = Color(0xFFE65100);
  static const _beakTip = Color(0xFFB71C1C);
  static const _loreHi = Color(0xFFFFAB91);
  static const _loreShadow = Color(0xFFBF360C);

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final bounds = Rect.fromLTWH(0, 0, w, h);

    // Bayangan lembut di bawah (kedalaman kartun)
    final sh = Rect.fromCenter(
      center: Offset(0.48 * w, 0.92 * h),
      width: 0.62 * w,
      height: 0.14 * h,
    );
    canvas.drawOval(
      sh,
      Paint()
        ..shader = RadialGradient(
          colors: [
            Colors.black.withValues(alpha: 0.2),
            Colors.transparent,
          ],
        ).createShader(sh),
    );

    // — Kepala bulu: bola 3D (tanpa tubuh) —
    final headCx = 0.36 * w;
    final headCy = 0.50 * h;
    final headR = 0.32 * math.min(w, h);
    final headRect = Rect.fromCircle(
      center: Offset(headCx, headCy),
      radius: headR,
    );
    canvas.drawCircle(
      Offset(headCx, headCy),
      headR,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.55, -0.6),
          radius: 1.05,
          colors: const [
            Color(0xFF4A4A58),
            Color(0xFF25252E),
            Color(0xFF0E0E14),
          ],
          stops: const [0.0, 0.58, 1.0],
        ).createShader(headRect),
    );
    // Highlight bulu (kilau kartun)
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset((headCx - headR * 0.38), (headCy - headR * 0.42)),
        width: headR * 0.45,
        height: headR * 0.28,
      ),
      Paint()..color = Colors.white.withValues(alpha: 0.14),
    );

    // — Casque: volumetrik, terpisah dari kepala agar terbaca “tanduk” —
    final casque = Path()
      ..moveTo(0.26 * w, 0.38 * h)
      ..cubicTo(
        0.32 * w,
        0.06 * h,
        0.68 * w,
        0.02 * h,
        0.74 * w,
        0.20 * h,
      )
      ..cubicTo(
        0.78 * w,
        0.32 * h,
        0.68 * w,
        0.40 * h,
        0.52 * w,
        0.42 * h,
      )
      ..cubicTo(
        0.40 * w,
        0.44 * h,
        0.26 * w,
        0.48 * h,
        0.26 * w,
        0.38 * h,
      )
      ..close();
    canvas.drawPath(
      casque,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            _casqueHi,
            _casqueMid,
            _beakLight.withValues(alpha: 0.95),
          ],
        ).createShader(bounds),
    );
    canvas.drawPath(
      casque,
      Paint()
        ..color = const Color(0xFF3E2723).withValues(alpha: 0.2)
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(0.4, w * 0.012),
    );
    // Kilau casque
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(0.50 * w, 0.16 * h),
        width: 0.20 * w,
        height: 0.10 * h,
      ),
      Paint()..color = Colors.white.withValues(alpha: 0.35),
    );

    // — Paruh besar (upper + lower satu bentuk, gradien “bulat” 3D) —
    final beak = Path()
      ..moveTo(0.42 * w, 0.36 * h)
      ..cubicTo(
        0.48 * w,
        0.32 * h,
        0.58 * w,
        0.34 * h,
        0.62 * w,
        0.40 * h,
      )
      ..lineTo(0.97 * w, 0.44 * h)
      ..cubicTo(
        0.99 * w,
        0.48 * h,
        0.98 * w,
        0.56 * h,
        0.90 * w,
        0.60 * h,
      )
      ..lineTo(0.58 * w, 0.62 * h)
      ..cubicTo(
        0.46 * w,
        0.62 * h,
        0.36 * w,
        0.52 * h,
        0.38 * w,
        0.42 * h,
      )
      ..cubicTo(
        0.39 * w,
        0.38 * h,
        0.40 * w,
        0.36 * h,
        0.42 * w,
        0.36 * h,
      )
      ..close();

    canvas.drawPath(
      beak,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            _beakLight,
            _beakDeep,
            _beakTip,
          ],
          stops: const [0.0, 0.55, 1.0],
        ).createShader(bounds),
    );

    // Pantulan terang di paruh (3D kartun)
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(0.72 * w, 0.44 * h),
        width: 0.34 * w,
        height: 0.12 * h,
      ),
      Paint()..color = Colors.white.withValues(alpha: 0.25),
    );
    // Bayangan bawah paruh
    canvas.drawPath(
      Path()
        ..moveTo(0.55 * w, 0.58 * h)
        ..quadraticBezierTo(0.78 * w, 0.62 * h, 0.90 * w, 0.56 * h),
      Paint()
        ..color = Colors.black.withValues(alpha: 0.18)
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(0.35, w * 0.025),
    );

    // Buka mulut / garis rahang
    canvas.drawPath(
      Path()
        ..moveTo(0.58 * w, 0.48 * h)
        ..quadraticBezierTo(0.80 * w, 0.50 * h, 0.95 * w, 0.48 * h),
      Paint()
        ..color = Colors.black.withValues(alpha: 0.25)
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(0.35, w * 0.015),
    );

    // — Bola mata & lore: glossy + kedip (squash vertikal) —
    final eyeCx = 0.26 * w;
    final eyeCy = 0.46 * h;
    final loreR = 0.095 * w;
    final open = eyeOpen.clamp(0.0, 1.0);
    final squash = 0.12 + 0.88 * open;

    canvas.save();
    canvas.translate(eyeCx, eyeCy);
    canvas.scale(1.0, squash);
    canvas.translate(-eyeCx, -eyeCy);

    final loreRect = Rect.fromCircle(
      center: Offset(eyeCx, eyeCy),
      radius: loreR,
    );
    canvas.drawCircle(
      Offset(eyeCx, eyeCy),
      loreR,
      Paint()
        ..shader = RadialGradient(
          colors: [_loreHi, _loreShadow],
        ).createShader(loreRect),
    );
    if (open > 0.08) {
      final eyeR = 0.055 * w;
      final eyeRect = Rect.fromCircle(
        center: Offset(eyeCx - 0.01 * w, eyeCy - 0.01 * h),
        radius: eyeR,
      );
      canvas.drawCircle(
        Offset(eyeCx - 0.01 * w, eyeCy - 0.01 * h),
        eyeR,
        Paint()
          ..shader = RadialGradient(
            center: const Alignment(-0.4, -0.45),
            colors: [
              Colors.white,
              const Color(0xFFE0E0E0),
            ],
          ).createShader(eyeRect),
      );
      canvas.drawCircle(
        Offset(eyeCx + 0.008 * w, eyeCy + 0.008 * h),
        0.026 * w,
        Paint()..color = const Color(0xFF1A1A1A),
      );
      if (open > 0.45) {
        canvas.drawCircle(
          Offset(eyeCx - 0.022 * w, eyeCy - 0.022 * h),
          0.015 * w,
          Paint()..color = Colors.white.withValues(alpha: 0.95),
        );
      }
    }
    canvas.restore();

    if (open < 0.55) {
      final lid = Path()
        ..moveTo(eyeCx - loreR * 1.05, eyeCy)
        ..quadraticBezierTo(
          eyeCx,
          eyeCy - loreR * 0.35,
          eyeCx + loreR * 1.05,
          eyeCy,
        );
      canvas.drawPath(
        lid,
        Paint()
          ..color = const Color(0xFF2C2C35)
          ..style = PaintingStyle.stroke
          ..strokeWidth = math.max(1.2, w * 0.045)
          ..strokeCap = StrokeCap.round,
      );
    }

    // Kontur paruh saja (agar garis tidak memotong bentuk paruh)
    canvas.drawPath(
      beak,
      Paint()
        ..color = const Color(0xFF4E342E).withValues(alpha: 0.35)
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(0.35, w * 0.014),
    );
  }

  @override
  bool shouldRepaint(covariant _RangkongBirdPainter oldDelegate) =>
      oldDelegate.eyeOpen != eyeOpen;
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
Widget trakaPageLoadingCenter({double size = 56}) => Center(
      child: TrakaLoadingIndicator(
        size: size,
        variant: TrakaLoadingVariant.onLightSurface,
      ),
    );

/// Latar gelap (viewer hitam, kamera, tombol primer) — busur putih / biru muda.
Widget trakaLoadingOnDarkSurface({
  double size = 48,
  Color primary = Colors.white,
  Color? secondary,
}) =>
    TrakaLoadingIndicator(
      size: size,
      variant: TrakaLoadingVariant.onDimmedBackdrop,
      primary: primary,
      secondary: secondary ?? AppTheme.primaryLight,
    );
