import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../config/marker_assets.dart';
import '../theme/app_theme.dart';

/// Marker lokasi driver: dot (diam) + cone (bergerak).
/// Pakai MarkerAssets (central config) + kecepatan untuk dot vs cone.
class DriverCarMarkerService {
  DriverCarMarkerService._();

  /// Naikkan saat ubah ukuran layout agar cache marker di driver_screen tidak pakai bitmap lama.
  static const int layoutVersion = 7;

  /// Ukuran icon dot/arrow di peta (travel jauh / zoom tinggi tetap terbaca).
  static const double _iconSize = 92.0;
  static const double _labelHeight = 24.0;
  static const double _labelPadding = 4.0;
  static const double _totalWidth = 148.0;
  static const double _totalHeight = _iconSize + _labelHeight;

  /// Elips bayangan di "tanah" (gaya Google Maps) — di bawah kaki panah / dot.
  static void _paintGroundShadow(
    Canvas canvas, {
    required double centerX,
    required double centerY,
    required double iconSize,
    required bool isMoving,
  }) {
    final shadowY = centerY + iconSize * (isMoving ? 0.34 : 0.20);
    final baseW = iconSize * (isMoving ? 0.72 : 0.52);
    final baseH = iconSize * (isMoving ? 0.26 : 0.22);
    final layers = <(double scale, double a)>[
      (1.12, 0.065),
      (1.0, 0.10),
      (0.82, 0.15),
    ];
    for (final L in layers) {
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset(centerX, shadowY),
          width: baseW * L.$1,
          height: baseH * L.$1,
        ),
        Paint()..color = Color.fromRGBO(18, 22, 28, L.$2),
      );
    }
  }

  /// Panah asset saja (beranda non-aktif) + bayangan; tanpa label jalan.
  static Future<BitmapDescriptor> createArrowAssetWithShadow({
    String assetPath = MarkerAssets.movingBasic,
    double canvasSize = 96,
  }) async {
    ui.Image? iconImage;
    try {
      final data = await rootBundle.load(assetPath);
      iconImage = await _decodeImage(data.buffer.asUint8List());
    } catch (_) {}

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final cx = canvasSize / 2;
    final cy = canvasSize / 2;
    final iconDraw = canvasSize * 0.82;

    if (iconImage != null) {
      _paintGroundShadow(
        canvas,
        centerX: cx,
        centerY: cy,
        iconSize: iconDraw,
        isMoving: true,
      );
      final rect = Rect.fromCenter(
        center: Offset(cx, cy),
        width: iconDraw,
        height: iconDraw,
      );
      paintImage(
        canvas: canvas,
        rect: rect,
        image: iconImage,
        fit: BoxFit.contain,
      );
    } else {
      _paintGroundShadow(
        canvas,
        centerX: cx,
        centerY: cy,
        iconSize: 48,
        isMoving: true,
      );
      _drawFallback(canvas, cx, cy, true);
    }

    final picture = recorder.endRecording();
    final image =
        await picture.toImage(canvasSize.round(), canvasSize.round());
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    return BitmapDescriptor.bytes(byteData!.buffer.asUint8List());
  }

  /// Buat marker: dot (idle) atau arrow (moving) + label nama jalan.
  /// [speedKmh]: kecepatan km/jam untuk adaptive asset (idle/basic/premium).
  static Future<BitmapDescriptor> createDriverCarMarker({
    required bool isMoving,
    required String streetName,
    double speedKmh = 0,
  }) async {
    // Jangan pakai [MarkerAssets.forSpeed] saat bergerak: di Android [Position.speed]
    // sering 0 → forSpeed mengembalikan titik merah padahal driver sudah jalan.
    final assetPath =
        isMoving ? MarkerAssets.movingPremium : MarkerAssets.idle;

    ui.Image? iconImage;
    try {
      final data = await rootBundle.load(assetPath);
      final bytes = data.buffer.asUint8List();
      iconImage = await _decodeImage(bytes);
    } catch (_) {}

    final hasStreetName = streetName.trim().isNotEmpty;

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);

    final centerX = _totalWidth / 2;
    final centerY = _iconSize / 2;

    if (iconImage != null) {
      _paintGroundShadow(
        canvas,
        centerX: centerX,
        centerY: centerY,
        iconSize: _iconSize,
        isMoving: isMoving,
      );
      final rect = Rect.fromCenter(
        center: Offset(centerX, centerY),
        width: _iconSize,
        height: _iconSize,
      );
      paintImage(
        canvas: canvas,
        rect: rect,
        image: iconImage,
        fit: BoxFit.contain,
      );
    } else {
      _paintGroundShadow(
        canvas,
        centerX: centerX,
        centerY: centerY,
        iconSize: _iconSize,
        isMoving: isMoving,
      );
      _drawFallback(canvas, centerX, centerY, isMoving);
    }

    // Label nama jalan
    if (hasStreetName) {
      final displayName =
          streetName.length > 16 ? '${streetName.substring(0, 15)}…' : streetName;
      final textPainter = TextPainter(
        text: TextSpan(
          text: displayName,
          style: const TextStyle(
            color: AppTheme.onSurface,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
        textDirection: TextDirection.ltr,
        maxLines: 1,
        ellipsis: '…',
      );
      textPainter.layout(maxWidth: _totalWidth - _labelPadding * 4);
      textPainter.paint(
        canvas,
        Offset(
          _labelPadding * 2,
          _iconSize + (_labelHeight - textPainter.height) / 2,
        ),
      );
    }

    final picture = recorder.endRecording();
    final image = await picture.toImage(_totalWidth.round(), _totalHeight.round());
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    final bytes = byteData!.buffer.asUint8List();
    return BitmapDescriptor.bytes(bytes);
  }

  static void _drawFallback(Canvas canvas, double cx, double cy, bool isMoving) {
    final color =
        isMoving ? AppTheme.primary : const Color(0xFFEB5757);
    if (isMoving) {
      final path = Path();
      final w = 41.0;
      final h = 48.0;
      final left = cx - w / 2;
      final top = cy - h / 2;
      path.moveTo(cx, top);
      path.lineTo(left + w * 0.85, top + h * 0.55);
      path.quadraticBezierTo(left + w, top + h * 0.7, left + w * 0.75, top + h);
      path.lineTo(left + w * 0.25, top + h);
      path.quadraticBezierTo(left, top + h * 0.7, left + w * 0.15, top + h * 0.55);
      path.close();
      canvas.drawPath(path, Paint()..color = color);
    } else {
      canvas.drawCircle(Offset(cx, cy), 21, Paint()..color = color);
    }
  }

  static Future<ui.Image> _decodeImage(Uint8List bytes) async {
    final completer = Completer<ui.Image>();
    ui.decodeImageFromList(bytes, (ui.Image img) {
      completer.complete(img);
    });
    return completer.future;
  }

}
