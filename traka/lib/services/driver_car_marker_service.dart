import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../config/marker_assets.dart';

/// Marker lokasi driver ala Grab: Dot (idle) + Arrow (moving).
/// Pakai MarkerAssets (central config) + adaptive berdasarkan speed.
class DriverCarMarkerService {
  DriverCarMarkerService._();

  static const double _iconSize = 42.0;
  static const double _labelHeight = 18.0;
  static const double _labelPadding = 4.0;
  static const double _totalWidth = 90.0;
  static const double _totalHeight = _iconSize + _labelHeight;

  /// Buat marker: dot (idle) atau arrow (moving) + label nama jalan.
  /// [speedKmh]: kecepatan km/jam untuk adaptive asset (idle/basic/premium).
  static Future<BitmapDescriptor> createDriverCarMarker({
    required bool isMoving,
    required String streetName,
    double speedKmh = 0,
  }) async {
    final assetPath = isMoving
        ? MarkerAssets.forSpeed(speedKmh)
        : MarkerAssets.idle;

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
            color: Color(0xFF212121),
            fontSize: 11,
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
    final color = isMoving ? const Color(0xFF2F80ED) : const Color(0xFFEB5757);
    if (isMoving) {
      final path = Path();
      final w = 24.0;
      final h = 28.0;
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
      canvas.drawCircle(Offset(cx, cy), 12, Paint()..color = color);
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
