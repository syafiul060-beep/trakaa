import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;

/// Service untuk membuat BitmapDescriptor marker dengan foto profil + pita nama.
/// Dipakai di Lacak Barang (pin pengirim/penerima) dan Lacak Driver (pin penumpang).
class MarkerIconService {
  MarkerIconService._();

  /// Buat marker icon: lingkaran foto profil + pita nama di atas.
  /// [photoUrl]: URL foto (Firebase Storage). Null = lingkaran warna solid.
  /// [name]: Teks di pita (max ~12 char).
  /// [ribbonColor]: Warna pita nama (orange untuk pengirim/penerima, biru untuk penumpang).
  static Future<BitmapDescriptor> createProfilePhotoMarker({
    required String name,
    String? photoUrl,
    Color ribbonColor = Colors.orange,
    Color fallbackCircleColor = Colors.orange,
  }) async {
    const double w = 80.0;
    const double h = 100.0;
    const double nameHeight = 26.0;
    const double borderWidth = 2.0;
    const double circleRadius = 34.0;
    final double circleCenterY = nameHeight + circleRadius;

    ui.Image? photoImage;
    if (photoUrl != null && photoUrl.trim().isNotEmpty) {
      try {
        photoImage = await _decodeImageFromUrl(photoUrl);
      } catch (_) {}
    }

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);

    final circleCenter = Offset(w / 2, circleCenterY);
    final circleRect = Rect.fromCircle(
      center: circleCenter,
      radius: circleRadius,
    );
    final borderPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = borderWidth;
    canvas.drawCircle(circleCenter, circleRadius, borderPaint);
    if (photoImage != null) {
      canvas.save();
      canvas.clipPath(Path()..addOval(circleRect));
      paintImage(
        canvas: canvas,
        rect: circleRect,
        image: photoImage,
        fit: BoxFit.cover,
      );
      canvas.restore();
    } else {
      canvas.drawCircle(
        circleCenter,
        circleRadius,
        Paint()..color = fallbackCircleColor,
      );
    }

    final nameRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, 0, w, nameHeight),
      const Radius.circular(10),
    );
    canvas.drawRRect(nameRect, Paint()..color = ribbonColor);
    final displayName = name.trim().isEmpty ? 'Lokasi' : name;
    final textPainter = TextPainter(
      text: TextSpan(
        text: displayName.length > 12
            ? '${displayName.substring(0, 11)}…'
            : displayName,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: '…',
    );
    textPainter.layout(maxWidth: w - 8);
    textPainter.paint(canvas, Offset(4, (nameHeight - textPainter.height) / 2));

    final picture = recorder.endRecording();
    final image = await picture.toImage(w.toInt(), h.toInt());
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    final bytes = byteData!.buffer.asUint8List();
    return BitmapDescriptor.bytes(bytes);
  }

  static Future<ui.Image> _decodeImageFromUrl(String url) async {
    final response = await http.get(Uri.parse(url));
    if (response.statusCode != 200) throw Exception('Failed to load image');
    final bytes = Uint8List.view(response.bodyBytes.buffer);
    final completer = Completer<ui.Image>();
    ui.decodeImageFromList(bytes, (ui.Image img) {
      completer.complete(img);
    });
    return completer.future;
  }
}
