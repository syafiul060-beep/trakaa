import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../theme/app_theme.dart';

/// Service untuk icon lokasi: titik biru merek (halus, bukan raster [image] bergerigi).
class DriverLocationIconService {
  DriverLocationIconService._();

  static BitmapDescriptor? _cachedBlueDot;
  static int? _cachedSize;
  /// Naikkan jika format berubah (bust cache).
  static const int _bitmapVersion = 5;
  static int? _cachedBitmapVersion;

  /// Titik untuk posisi di peta: cincin putih + isi [AppTheme.primary], tepi anti-alias.
  /// [sizePx] lebar/tinggi bitmap output (device px); lebih kecil = marker lebih kecil di peta.
  static Future<BitmapDescriptor> loadBlueDotDescriptor({
    int sizePx = 36,
  }) async {
    if (_cachedBlueDot != null &&
        _cachedSize == sizePx &&
        _cachedBitmapVersion == _bitmapVersion) {
      return _cachedBlueDot!;
    }

    try {
      final d = sizePx.clamp(24, 64);
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      final c = d / 2.0;
      // Ruang setengah piksel agar anti-alias tidak terpotong di tepi bitmap.
      final outerR = c - 0.75;
      final borderW = (d * 0.11).clamp(1.5, 2.75);
      final innerR = (outerR - borderW).clamp(2.0, outerR - 0.5);

      final whitePaint = Paint()
        ..isAntiAlias = true
        ..filterQuality = FilterQuality.high
        ..color = Colors.white
        ..style = PaintingStyle.fill;
      final bluePaint = Paint()
        ..isAntiAlias = true
        ..filterQuality = FilterQuality.high
        ..color = AppTheme.primary
        ..style = PaintingStyle.fill;

      canvas.drawCircle(Offset(c, c), outerR, whitePaint);
      canvas.drawCircle(Offset(c, c), innerR, bluePaint);

      final picture = recorder.endRecording();
      final image = await picture.toImage(d, d);
      final byteData =
          await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) {
        return BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure);
      }
      final descriptor = BitmapDescriptor.bytes(byteData.buffer.asUint8List());
      _cachedBlueDot = descriptor;
      _cachedSize = sizePx;
      _cachedBitmapVersion = _bitmapVersion;
      return descriptor;
    } catch (_) {
      return BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure);
    }
  }

  static void clearCache() {
    _cachedBlueDot = null;
    _cachedSize = null;
    _cachedBitmapVersion = null;
  }
}
