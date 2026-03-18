import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:image/image.dart' as img;

/// Service untuk icon lokasi driver: titik biru (marker di peta).
class DriverLocationIconService {
  DriverLocationIconService._();

  static BitmapDescriptor? _cachedBlueDot;
  static int? _cachedSize;

  /// Titik biru besar untuk posisi driver saat diam (rute dipilih, belum mulai).
  /// [sizePx] ukuran diameter dalam pixel (default 48).
  static Future<BitmapDescriptor> loadBlueDotDescriptor({
    int sizePx = 48,
  }) async {
    if (_cachedBlueDot != null && _cachedSize == sizePx) {
      return _cachedBlueDot!;
    }

    try {
      final image = img.Image(width: sizePx, height: sizePx);
      final center = sizePx ~/ 2;
      final radius = center - 2;
      final blue = img.ColorRgba8(66, 133, 244, 255); // #4285F4

      img.fillCircle(image, x: center, y: center, radius: radius, color: blue);

      final pngBytes = img.encodePng(image);
      if (pngBytes.isEmpty) {
        return BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure);
      }

      final descriptor = BitmapDescriptor.bytes(pngBytes);
      _cachedBlueDot = descriptor;
      _cachedSize = sizePx;
      return descriptor;
    } catch (_) {
      return BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure);
    }
  }

  static void clearCache() {
    _cachedBlueDot = null;
    _cachedSize = null;
  }
}
