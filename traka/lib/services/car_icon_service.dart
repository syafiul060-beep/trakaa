import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:image/image.dart' as img;

import 'car_icon_3d_painter.dart';
import '../theme/responsive.dart';

/// Hasil load icon mobil (car_merah.png, car_hijau.png).
/// [red], [green]: BitmapDescriptor untuk marker map.
/// [redImage], [greenImage]: ui.Image mentah untuk komposit (mis. nama di atas icon).
class CarIconResult {
  const CarIconResult({
    required this.red,
    required this.green,
    this.redImage,
    this.greenImage,
  });

  final BitmapDescriptor red;
  final BitmapDescriptor green;
  final ui.Image? redImage;
  final ui.Image? greenImage;
}

/// Service terpusat untuk load icon mobil (car_merah.png, car_hijau.png).
///
/// **Penumpang:** cari driver, pelacakan, kirim barang. Pakai AppConstants.penumpangIsMovingThresholdSeconds.
/// **Driver:** overlay/tampilan sendiri, logika isMoving terpisah (_hasMovedAfterStart, dll).
/// Asset dipakai bersama; logika tampilan berbeda.
///
/// Asset: mobil menghadap ke bawah (selatan). Rotasi: (bearing + 180) % 360.
/// Lihat docs/ASSET_ICON_MOBIL.md.
class CarIconService {
  CarIconService._();

  static CarIconResult? _cachedResult;
  static double? _cachedBaseSize;
  static double? _cachedPadding;
  static bool? _cachedIncludeImages;
  static bool? _cachedUse3D;
  static double? _cachedDpr;
  static int? _cachedProcessingVersion;
  static bool? _cachedForPassenger;
  /// Bump saat ubah logika transparansi agar cache lama tidak dipakai.
  static const int _processingVersion = 4;

  /// Load icon mobil merah & hijau.
  /// [forPassenger]: true = transparansi agresif (hilangkan kotak hitam di map penumpang).
  ///                 false = untuk driver, tidak diubah.
  /// [use3DStyle]: true = gambar 3D programatik (gaya Traka), false = dari asset.
  ///
  /// [context]: untuk MediaQuery.devicePixelRatio dan Responsive (opsional).
  /// [baseSize]: ukuran dasar px (50–80). Lacak: 62, Penumpang: 50.
  /// [padding]: padding canvas agar icon tidak terpotong saat rotasi (0 = tanpa padding).
  /// [includeRawImages]: true = kembalikan redImage/greenImage untuk komposit nama.
  static Future<CarIconResult> loadCarIcons({
    required BuildContext context,
    double baseSize = 60,
    double padding = 12,
    bool includeRawImages = false,
    bool use3DStyle = false,
    bool forPassenger = false,
  }) async {
    final dpr = MediaQuery.of(context).devicePixelRatio;

    // Cache hit: parameter sama + versi processing + forPassenger
    if (_cachedResult != null &&
        _cachedBaseSize == baseSize &&
        _cachedPadding == padding &&
        _cachedIncludeImages == includeRawImages &&
        _cachedUse3D == use3DStyle &&
        _cachedDpr == dpr &&
        _cachedProcessingVersion == _processingVersion &&
        _cachedForPassenger == forPassenger) {
      return _cachedResult!;
    }

    BitmapDescriptor redDesc = BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed);
    BitmapDescriptor greenDesc = BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen);
    ui.Image? redImg;
    ui.Image? greenImg;

    // Mode 3D: gambar programatik (gaya Traka).
    if (use3DStyle) {
      try {
        final size = ((baseSize * dpr).round().toDouble()).clamp(96.0, 256.0).toDouble();
        redDesc = await CarIcon3dPainter.drawCarIcon(size: size, isRed: true);
        greenDesc = await CarIcon3dPainter.drawCarIcon(size: size, isRed: false);
        final result = CarIconResult(red: redDesc, green: greenDesc);
        _cachedResult = result;
        _cachedBaseSize = baseSize;
        _cachedPadding = padding;
        _cachedIncludeImages = includeRawImages;
        _cachedUse3D = use3DStyle;
        _cachedDpr = dpr;
        return result;
      } catch (e) {
        if (kDebugMode) debugPrint('[CarIconService] 3D icon gagal: $e');
        // Fallback ke asset
      }
    }

    // Coba load via package:image (resize + padding untuk retina)
    try {
      int decodeWidth;
      try {
        final size = Responsive.of(context).iconSize(baseSize).round().clamp(14, 56);
        decodeWidth = (size * dpr).round().clamp(32, 56);
      } catch (_) {
        decodeWidth = (baseSize * dpr).round().clamp(32, 56);
      }

      // Pilih variant resolusi (1x, 2.0x, 3.0x) untuk retina
      final scale = dpr >= 2.5 ? 3 : (dpr >= 1.5 ? 2 : 1);
      String pathFor(String name) =>
          scale > 1 ? 'assets/images/$scale.0x/$name' : 'assets/images/$name';

      for (final name in ['car_merah.png', 'car_hijau.png']) {
        var path = pathFor(name);
        ByteData data;
        try {
          data = await rootBundle.load(path);
        } catch (_) {
          path = 'assets/images/$name';
          data = await rootBundle.load(path);
        }
        final bytes = data.buffer.asUint8List();
        final decoded = img.decodeImage(bytes);
        if (decoded == null) {
          if (kDebugMode) debugPrint('[CarIconService] decodeImage null: $path');
          continue;
        }

        // Pastikan RGBA agar padding transparan (bukan hitam)
        img.Image withAlpha = decoded.numChannels >= 4
            ? decoded
            : decoded.convert(numChannels: 4);
        withAlpha.backgroundColor = img.ColorRgba8(0, 0, 0, 0);
        // Bersihkan background (penumpang: agresif hilangkan kotak hitam; driver: tidak diubah)
        withAlpha = _makeBackgroundTransparent(withAlpha, forPassenger: forPassenger);
        // Rotasi 180°: asset depan di atas → depan di bawah (sesuai bearing).
        img.Image rotated = img.copyRotate(withAlpha, angle: 180);
        img.Image processed = img.copyResize(rotated, width: decodeWidth);
        if (padding > 0) {
          processed = img.copyExpandCanvas(
            processed,
            padding: padding.round(),
            position: img.ExpandCanvasPosition.center,
            backgroundColor: img.ColorRgba8(0, 0, 0, 0),
          );
        }
        processed = _makeBackgroundTransparent(processed, forPassenger: forPassenger);

        final pngBytes = img.encodePng(processed);
        if (pngBytes.isNotEmpty) {
          final descriptor = BitmapDescriptor.bytes(pngBytes);
          if (path.contains('car_merah')) {
            redDesc = descriptor;
          } else {
            greenDesc = descriptor;
          }
        }

        if (includeRawImages && pngBytes.isNotEmpty) {
          final codec = await ui.instantiateImageCodec(pngBytes);
          final frame = await codec.getNextFrame();
          if (path.contains('car_merah')) {
            redImg = frame.image;
          } else {
            greenImg = frame.image;
          }
        }
      }

      final result = CarIconResult(
        red: redDesc,
        green: greenDesc,
        redImage: includeRawImages ? redImg : null,
        greenImage: includeRawImages ? greenImg : null,
      );

      _cachedResult = result;
      _cachedBaseSize = baseSize;
      _cachedPadding = padding;
      _cachedIncludeImages = includeRawImages;
      _cachedUse3D = use3DStyle;
      _cachedDpr = dpr;
      _cachedProcessingVersion = _processingVersion;
      _cachedForPassenger = forPassenger;

      return result;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[CarIconService] package:image gagal: $e');
        debugPrint('[CarIconService] Fallback ke fromAssetImage');
      }

      // Fallback: proses dengan package:image (tetap transparan) atau fromAssetImage
      try {
        final fallbackResult = await _loadAndProcessAssetIcons(
          context: context,
          baseSize: baseSize,
          padding: padding,
          dpr: dpr,
        );
        if (fallbackResult != null) {
          final result = CarIconResult(
            red: fallbackResult.red,
            green: fallbackResult.green,
          );
          _cachedResult = result;
          _cachedBaseSize = baseSize;
          _cachedPadding = padding;
          _cachedIncludeImages = includeRawImages;
          _cachedUse3D = use3DStyle;
          _cachedDpr = dpr;
          _cachedProcessingVersion = _processingVersion;
          return result;
        }
      } catch (_) {}

      // Last resort: fromAssetImage (bisa ada kotak hitam jika asset punya background)
      try {
        const size = 40.0;
        final config = ImageConfiguration(
          devicePixelRatio: dpr,
          size: Size(size, size),
        );
        redDesc = await BitmapDescriptor.fromAssetImage(
          config,
          'assets/images/car_merah.png',
          mipmaps: false,
        );
        greenDesc = await BitmapDescriptor.fromAssetImage(
          config,
          'assets/images/car_hijau.png',
          mipmaps: false,
        );
      } catch (_) {}

      final result = CarIconResult(red: redDesc, green: greenDesc);
      _cachedResult = result;
      _cachedBaseSize = baseSize;
      _cachedPadding = padding;
      _cachedIncludeImages = includeRawImages;
      _cachedUse3D = use3DStyle;
      _cachedDpr = dpr;
      _cachedProcessingVersion = _processingVersion;
      _cachedForPassenger = forPassenger;
      return result;
    }
  }

  /// Fallback: load asset, proses transparansi, return BitmapDescriptor.bytes.
  static Future<CarIconResult?> _loadAndProcessAssetIcons({
    required BuildContext context,
    required double baseSize,
    required double padding,
    required double dpr,
    bool forPassenger = false,
  }) async {
    try {
      final size = Responsive.of(context).iconSize(baseSize).round().clamp(14, 56);
      final decodeWidth = (size * dpr).round().clamp(32, 56);
      BitmapDescriptor? redDesc;
      BitmapDescriptor? greenDesc;
      for (final name in ['car_merah.png', 'car_hijau.png']) {
        final data = await rootBundle.load('assets/images/$name');
        final decoded = img.decodeImage(data.buffer.asUint8List());
        if (decoded == null) continue;
        img.Image withAlpha = decoded.numChannels >= 4
            ? decoded
            : decoded.convert(numChannels: 4);
        withAlpha.backgroundColor = img.ColorRgba8(0, 0, 0, 0);
        withAlpha = _makeBackgroundTransparent(withAlpha, forPassenger: forPassenger);
        img.Image rotated = img.copyRotate(withAlpha, angle: 180);
        img.Image processed = img.copyResize(rotated, width: decodeWidth);
        if (padding > 0) {
          processed = img.copyExpandCanvas(
            processed,
            padding: padding.round(),
            position: img.ExpandCanvasPosition.center,
            backgroundColor: img.ColorRgba8(0, 0, 0, 0),
          );
        }
        processed = _makeBackgroundTransparent(processed, forPassenger: forPassenger);
        final pngBytes = img.encodePng(processed);
        if (pngBytes.isEmpty) continue;
        final descriptor = BitmapDescriptor.bytes(pngBytes);
        if (name.contains('car_merah')) {
          redDesc = descriptor;
        } else {
          greenDesc = descriptor;
        }
      }
      if (redDesc != null && greenDesc != null) {
        return CarIconResult(red: redDesc, green: greenDesc);
      }
    } catch (_) {}
    return null;
  }

  /// Buat background transparan. [forPassenger] true = agresif hilangkan kotak hitam.
  /// Driver (false) = konservatif, mobil tetap solid.
  static img.Image _makeBackgroundTransparent(img.Image image, {bool forPassenger = false}) {
    final transparent = img.ColorRgba8(0, 0, 0, 0);
    for (int y = 0; y < image.height; y++) {
      for (int x = 0; x < image.width; x++) {
        final p = image.getPixel(x, y);
        final r = p.r.toInt();
        final g = p.g.toInt();
        final b = p.b.toInt();
        final a = p.a.toInt();
        final maxC = r > g ? (r > b ? r : b) : (g > b ? g : b);
        final minC = r < g ? (r < b ? r : b) : (g < b ? g : b);

        if (forPassenger) {
          // Penumpang: agresif hilangkan kotak hitam (background hitam/abu gelap)
          final isWhite = r > 220 && g > 220 && b > 220;
          final isBlackOrDark = r < 100 && g < 100 && b < 100;
          final isNeutralGray = (maxC - minC) < 50 && maxC < 150;
          final isTransparentInSource = a < 128;
          final isCarBody = r > 80 || g > 80;
          if (!isCarBody && (isWhite || isBlackOrDark || isNeutralGray || isTransparentInSource)) {
            image.setPixel(x, y, transparent);
          }
        } else {
          // Driver: konservatif, jangan ubah
          final isWhite = r > 245 && g > 245 && b > 245;
          final isNeutralDark = r < 55 && g < 55 && b < 55 && (maxC - minC) < 20;
          final isTransparentInSource = a < 128;
          final isCarBody = r > 100 || g > 100;
          if (!isCarBody && (isWhite || isNeutralDark || isTransparentInSource)) {
            image.setPixel(x, y, transparent);
          }
        }
      }
    }
    return image;
  }

  /// Bersihkan cache (mis. saat tema berubah atau tes).
  static void clearCache() {
    _cachedResult = null;
    _cachedBaseSize = null;
    _cachedPadding = null;
    _cachedIncludeImages = null;
    _cachedUse3D = null;
    _cachedDpr = null;
    _cachedProcessingVersion = null;
    _cachedForPassenger = null;
  }
}

