import 'dart:collection';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:image/image.dart' as img;

import 'car_icon_3d_painter.dart';
import 'map_style_service.dart';
import '../theme/responsive.dart';

/// Hasil load icon mobil (`traka_car_icons_premium/car_red.png`, `car_green.png`).
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

/// Tiga ikon map penumpang premium: hijau (tersedia), merah (penuh), biru (rekomendasi / trip aktif).
///
/// [assetFrontFacesNorth]: true = depan mobil ke **atas** di PNG. false = depan ke **bawah**
/// (sama aset premium PNG umum) — sinkron dengan
/// [CarIconService.markerRotationDegrees].
class PremiumPassengerCarIconSet {
  const PremiumPassengerCarIconSet({
    required this.green,
    required this.red,
    required this.blue,
    this.assetFrontFacesNorth = false,
  });

  final BitmapDescriptor green;
  final BitmapDescriptor red;
  final BitmapDescriptor blue;
  final bool assetFrontFacesNorth;
}

/// Service terpusat untuk load icon mobil dari [traka_car_icons_premium] saja.
///
/// **Penumpang:** cari driver, pelacakan, kirim barang. Pakai AppConstants.penumpangIsMovingThresholdSeconds.
/// **Driver:** overlay/tampilan sendiri, logika isMoving terpisah (_hasMovedAfterStart, dll).
/// Asset dipakai bersama; logika tampilan berbeda.
///
/// Aset PNG: depan ke bawah di file; diputar 180° di pipeline; marker rotation = bearing + 180.
class CarIconService {
  CarIconService._();

  static const String _driverCarRed =
      'assets/images/traka_car_icons_premium/car_red.png';
  static const String _driverCarGreen =
      'assets/images/traka_car_icons_premium/car_green.png';

  static CarIconResult? _cachedResult;
  static double? _cachedBaseSize;
  static double? _cachedPadding;
  static bool? _cachedIncludeImages;
  static bool? _cachedUse3D;
  static double? _cachedDpr;
  static int? _cachedProcessingVersion;
  static bool? _cachedForPassenger;
  /// -1 = bukan mode penumpang; selain itu = [passengerMapZoomBucket].
  static int? _cachedMapZoomKey;
  /// Bump saat ubah logika transparansi agar cache lama tidak dipakai.
  static const int _processingVersion = 12;

  /// Putar 180° tanpa interpolasi — salin piksel apa adanya (hindari artefak hitam dari [copyRotate]).
  static img.Image _rotate180Copy(img.Image src) {
    final w = src.width;
    final h = src.height;
    final dst = img.Image(width: w, height: h, numChannels: 4);
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        dst.setPixel(x, y, src.getPixel(w - 1 - x, h - 1 - y));
      }
    }
    return dst;
  }

  static PremiumPassengerCarIconSet? _premiumCached;
  static double? _premiumCachedBaseSize;
  static double? _premiumCachedPadding;
  static double? _premiumCachedDpr;
  static int? _premiumCachedLogicVersion;
  static int? _premiumCachedMapZoomKey;
  /// Bump saat ubah pipeline premium (transparansi / rotasi / skala zoom).
  static const int _premiumProcessingVersion = 11;

  /// Bucket zoom (langkah 0.5) untuk cache bitmap — hindari rebuild tiap frame kamera.
  static int passengerMapZoomBucket(double zoom) {
    if (!zoom.isFinite) {
      return (MapStyleService.defaultZoom * 2).round();
    }
    return (zoom * 2).round().clamp(10, 42);
  }

  /// Skala lebar decode ikon penumpang vs zoom peta (referensi 15). Lebih kecil default,
  /// membesar saat zoom in, mengecil saat zoom out.
  static double passengerIconPixelScale(double mapZoom) {
    const ref = 15.0;
    final z = mapZoom.isFinite ? mapZoom : ref;
    const visualShrink = 0.86;
    return ((0.74 + (z - ref) * 0.068).clamp(0.52, 1.32)) * visualShrink;
  }

  /// Load icon mobil merah & hijau.
  /// [forPassenger]: true = transparansi agresif (hilangkan kotak hitam di map penumpang).
  ///                 false = untuk driver, tidak diubah.
  /// [use3DStyle]: true = gambar 3D programatik (gaya Traka), false = dari asset.
  ///
  /// [context]: untuk MediaQuery.devicePixelRatio dan Responsive (opsional).
  /// [baseSize]: ukuran dasar px (50–80). Lacak: 62, Penumpang: 50.
  /// [padding]: padding canvas agar icon tidak terpotong saat rotasi (0 = tanpa padding).
  /// [includeRawImages]: true = kembalikan redImage/greenImage untuk komposit nama.
  /// [mapZoom]: zoom peta Google Maps; dipakai jika [forPassenger] untuk skala bitmap.
  static Future<CarIconResult> loadCarIcons({
    required BuildContext context,
    double baseSize = 60,
    double padding = 12,
    bool includeRawImages = false,
    bool use3DStyle = false,
    bool forPassenger = false,
    double mapZoom = MapStyleService.defaultZoom,
  }) async {
    final dpr = MediaQuery.of(context).devicePixelRatio;
    final zoomKey = forPassenger ? passengerMapZoomBucket(mapZoom) : -1;

    // Cache hit: parameter sama + versi processing + forPassenger + bucket zoom penumpang
    if (_cachedResult != null &&
        _cachedBaseSize == baseSize &&
        _cachedPadding == padding &&
        _cachedIncludeImages == includeRawImages &&
        _cachedUse3D == use3DStyle &&
        _cachedDpr == dpr &&
        _cachedProcessingVersion == _processingVersion &&
        _cachedForPassenger == forPassenger &&
        _cachedMapZoomKey == zoomKey) {
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
        _cachedProcessingVersion = _processingVersion;
        _cachedForPassenger = forPassenger;
        _cachedMapZoomKey = zoomKey;
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
        final zScale = forPassenger ? passengerIconPixelScale(mapZoom) : 1.0;
        decodeWidth = (size * dpr * zScale).round().clamp(
              forPassenger ? 16 : 32,
              forPassenger ? 46 : 56,
            );
      } catch (_) {
        final zScale = forPassenger ? passengerIconPixelScale(mapZoom) : 1.0;
        decodeWidth = (baseSize * dpr * zScale).round().clamp(
              forPassenger ? 16 : 32,
              forPassenger ? 46 : 56,
            );
      }

      for (final entry in [
        (_driverCarRed, true),
        (_driverCarGreen, false),
      ]) {
        final path = entry.$1;
        final isRed = entry.$2;
        final ByteData data;
        try {
          data = await rootBundle.load(path);
        } catch (_) {
          if (kDebugMode) debugPrint('[CarIconService] load fail: $path');
          continue;
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
        // Rotasi 180°: legacy depan ke bawah di file → bitmap untuk marker (bearing + 180).
        img.Image rotated = _rotate180Copy(withAlpha);
        img.Image processed = img.copyResize(rotated, width: decodeWidth);
        final expandPad = forPassenger
            ? padding.round().clamp(0, 2)
            : padding.round();
        if (expandPad > 0) {
          processed = img.copyExpandCanvas(
            processed,
            padding: expandPad,
            position: img.ExpandCanvasPosition.center,
            backgroundColor: img.ColorRgba8(0, 0, 0, 0),
          );
        }
        processed = _makeBackgroundTransparent(processed, forPassenger: forPassenger);

        BitmapDescriptor? descriptor;
        if (forPassenger) {
          descriptor = await _descriptorFromProcessedImagePassenger(processed);
        } else {
          final pngBytes = img.encodePng(processed);
          if (pngBytes.isNotEmpty) {
            descriptor = BitmapDescriptor.bytes(pngBytes);
          }
        }
        if (descriptor != null) {
          if (isRed) {
            redDesc = descriptor;
          } else {
            greenDesc = descriptor;
          }
        }

        final pngBytes = img.encodePng(processed);
        if (includeRawImages && pngBytes.isNotEmpty) {
          final codec = await ui.instantiateImageCodec(pngBytes);
          final frame = await codec.getNextFrame();
          if (isRed) {
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
      _cachedMapZoomKey = zoomKey;

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
          forPassenger: forPassenger,
          mapZoom: mapZoom,
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
          _cachedForPassenger = forPassenger;
          _cachedMapZoomKey = zoomKey;
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
          _driverCarRed,
          mipmaps: false,
        );
        greenDesc = await BitmapDescriptor.fromAssetImage(
          config,
          _driverCarGreen,
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
      _cachedMapZoomKey = zoomKey;
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
    double mapZoom = MapStyleService.defaultZoom,
  }) async {
    try {
      final size = Responsive.of(context).iconSize(baseSize).round().clamp(14, 56);
      final zScale = forPassenger ? passengerIconPixelScale(mapZoom) : 1.0;
      final decodeWidth = (size * dpr * zScale).round().clamp(
            forPassenger ? 19 : 32,
            forPassenger ? 54 : 56,
          );
      BitmapDescriptor? redDesc;
      BitmapDescriptor? greenDesc;
      for (final entry in [
        (_driverCarRed, true),
        (_driverCarGreen, false),
      ]) {
        final path = entry.$1;
        final isRed = entry.$2;
        final data = await rootBundle.load(path);
        final decoded = img.decodeImage(data.buffer.asUint8List());
        if (decoded == null) continue;
        img.Image withAlpha = decoded.numChannels >= 4
            ? decoded
            : decoded.convert(numChannels: 4);
        withAlpha.backgroundColor = img.ColorRgba8(0, 0, 0, 0);
        withAlpha = _makeBackgroundTransparent(withAlpha, forPassenger: forPassenger);
        img.Image rotated = _rotate180Copy(withAlpha);
        img.Image processed = img.copyResize(rotated, width: decodeWidth);
        final expandPad = forPassenger
            ? padding.round().clamp(0, 2)
            : padding.round();
        if (expandPad > 0) {
          processed = img.copyExpandCanvas(
            processed,
            padding: expandPad,
            position: img.ExpandCanvasPosition.center,
            backgroundColor: img.ColorRgba8(0, 0, 0, 0),
          );
        }
        processed = _makeBackgroundTransparent(processed, forPassenger: forPassenger);
        final BitmapDescriptor descriptor;
        if (forPassenger) {
          descriptor = await _descriptorFromProcessedImagePassenger(processed);
        } else {
          final pngBytes = img.encodePng(processed);
          if (pngBytes.isEmpty) continue;
          descriptor = BitmapDescriptor.bytes(pngBytes);
        }
        if (isRed) {
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

  /// PNG untuk marker penumpang: encode + round-trip lewat codec Flutter (bukan decodeImageFromPixels,
  /// yang di beberapa build memperbesar artefak). Gabung dengan [flat:false] di Android pada widget Marker.
  static Future<BitmapDescriptor> _descriptorFromProcessedImagePassenger(
    img.Image processed,
  ) async {
    final pngBytes = img.encodePng(processed);
    if (pngBytes.isEmpty) {
      return BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueBlue);
    }
    return _bytesDescriptorForMap(Uint8List.fromList(pngBytes));
  }

  static Future<BitmapDescriptor> _bytesDescriptorForMap(Uint8List pngBytes) async {
    try {
      final codec = await ui.instantiateImageCodec(pngBytes);
      final frame = await codec.getNextFrame();
      final uiImage = frame.image;
      final bd = await uiImage.toByteData(format: ui.ImageByteFormat.png);
      uiImage.dispose();
      if (bd != null && bd.lengthInBytes > 0) {
        return BitmapDescriptor.bytes(bd.buffer.asUint8List());
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[CarIconService] descriptor round-trip: $e');
    }
    return BitmapDescriptor.bytes(pngBytes);
  }

  /// Piksel cat mobil / aksen berwarna — tidak boleh dilalui flood (memutus jembatan latar ↔ atap putih).
  static bool _passengerCarPaintBarrier(
    int r,
    int g,
    int b,
    int a,
    int chroma,
    int maxC,
  ) {
    if (a < 200) return false;
    final isBlueBody = b > 88 && b >= r + 18 && b >= g + 12;
    final isRedBody = r > 88 && r >= g + 18 && r >= b + 12;
    final isGreenBody = g > 88 && g >= r + 12 && g >= b + 12;
    if (isBlueBody || isRedBody || isGreenBody) return true;
    if (chroma >= 42 && maxC >= 92) return true;
    return false;
  }

  /// Hanya piksel yang boleh dilalui flood dari tepi gambar (latar, bukan isi mobil).
  /// Putih atap #FFF lolos sebagai "connector" hanya jika ada rantai serupa ke border;
  /// di aset Traka rantai itu terputus oleh pilar abu / badan warna (min RGB < ~248).
  static bool _passengerEdgeFloodConnector(
    int r,
    int g,
    int b,
    int a,
    int chroma,
    int maxC,
  ) {
    if (a < 128) return true;
    if (r < 100 && g < 100 && b < 100) return true;
    if (chroma < 45 && maxC < 135) return true;
    final low = r < g ? (r < b ? r : b) : (g < b ? g : b);
    if (low >= 248 && chroma <= 22) return true;
    return false;
  }

  /// Penumpang: hapus hanya piksel **terhubung ke tepi** melalui [ _passengerEdgeFloodConnector ].
  /// Menghindari chromakey global yang membuat atap putih ikut transparan.
  static img.Image _makePassengerBackgroundTransparent(img.Image image) {
    final w = image.width;
    final h = image.height;
    final transparent = img.ColorRgba8(0, 0, 0, 0);
    final visited = List<bool>.filled(w * h, false);
    int idx(int x, int y) => y * w + x;

    bool consider(int x, int y) {
      final p = image.getPixel(x, y);
      final r = p.r.toInt();
      final g = p.g.toInt();
      final b = p.b.toInt();
      final a = p.a.toInt();
      final maxC = r > g ? (r > b ? r : b) : (g > b ? g : b);
      final minC = r < g ? (r < b ? r : b) : (g < b ? g : b);
      final chroma = maxC - minC;
      if (_passengerCarPaintBarrier(r, g, b, a, chroma, maxC)) return false;
      return _passengerEdgeFloodConnector(r, g, b, a, chroma, maxC);
    }

    final q = Queue<int>();
    void enqueue(int x, int y) {
      if (x < 0 || x >= w || y < 0 || y >= h) return;
      final i = idx(x, y);
      if (visited[i]) return;
      if (!consider(x, y)) return;
      visited[i] = true;
      q.add(i);
    }

    for (var x = 0; x < w; x++) {
      enqueue(x, 0);
      enqueue(x, h - 1);
    }
    for (var y = 0; y < h; y++) {
      enqueue(0, y);
      enqueue(w - 1, y);
    }

    while (q.isNotEmpty) {
      final i = q.removeFirst();
      final x = i % w;
      final y = i ~/ w;
      image.setPixel(x, y, transparent);
      enqueue(x + 1, y);
      enqueue(x - 1, y);
      enqueue(x, y + 1);
      enqueue(x, y - 1);
    }
    return image;
  }

  /// Buat background transparan. [forPassenger] true = flood dari tepi (premium + legacy penumpang).
  /// Driver (false) = konservatif, mobil tetap solid.
  static img.Image _makeBackgroundTransparent(img.Image image, {bool forPassenger = false}) {
    final transparent = img.ColorRgba8(0, 0, 0, 0);
    if (forPassenger) {
      return _makePassengerBackgroundTransparent(image);
    }
    for (int y = 0; y < image.height; y++) {
      for (int x = 0; x < image.width; x++) {
        final p = image.getPixel(x, y);
        final r = p.r.toInt();
        final g = p.g.toInt();
        final b = p.b.toInt();
        final a = p.a.toInt();
        final maxC = r > g ? (r > b ? r : b) : (g > b ? g : b);
        final minC = r < g ? (r < b ? r : b) : (g < b ? g : b);

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
    return image;
  }

  /// Rotasi [Marker] Google Maps: bearing 0 = utara.
  /// [premiumAssetFrontUp] true: rotation = bearing. false: bearing + 180 (legacy & premium PNG saat ini).
  static double markerRotationDegrees(double bearing, {required bool premiumAssetFrontUp}) {
    double b = bearing.isFinite ? bearing : 0.0;
    b = ((b % 360) + 360) % 360;
    if (!premiumAssetFrontUp) {
      b = (b + 180) % 360;
    }
    return b;
  }

  /// Load ikon premium penumpang (`traka_car_icons_premium/car_{green,red,blue}.png`).
  /// Gagal parsial → null (pemanggil pakai [loadCarIcons]).
  static Future<PremiumPassengerCarIconSet?> loadPremiumPassengerCarIcons({
    required BuildContext context,
    double baseSize = 60,
    double padding = 12,
    double mapZoom = MapStyleService.defaultZoom,
  }) async {
    final dpr = MediaQuery.of(context).devicePixelRatio;
    final zoomKey = passengerMapZoomBucket(mapZoom);
    if (_premiumCached != null &&
        _premiumCachedBaseSize == baseSize &&
        _premiumCachedPadding == padding &&
        _premiumCachedDpr == dpr &&
        _premiumCachedLogicVersion == _premiumProcessingVersion &&
        _premiumCachedMapZoomKey == zoomKey) {
      return _premiumCached;
    }

    try {
      int decodeWidth;
      try {
        final size = Responsive.of(context).iconSize(baseSize).round().clamp(14, 56);
        final zScale = passengerIconPixelScale(mapZoom);
        decodeWidth = (size * dpr * zScale).round().clamp(18, 52);
      } catch (_) {
        decodeWidth = (baseSize * dpr * passengerIconPixelScale(mapZoom))
            .round()
            .clamp(18, 52);
      }

      BitmapDescriptor? greenDesc;
      BitmapDescriptor? redDesc;
      BitmapDescriptor? blueDesc;

      for (final name in ['car_green.png', 'car_red.png', 'car_blue.png']) {
        final path = 'assets/images/traka_car_icons_premium/$name';
        final data = await rootBundle.load(path);
        final decoded = img.decodeImage(data.buffer.asUint8List());
        if (decoded == null) continue;

        img.Image withAlpha = decoded.numChannels >= 4
            ? decoded
            : decoded.convert(numChannels: 4);
        withAlpha.backgroundColor = img.ColorRgba8(0, 0, 0, 0);
        withAlpha = _makeBackgroundTransparent(withAlpha, forPassenger: true);
        // Aset premium: depan mobil = bawah gambar. Tanpa copyRotate.
        var processed = img.copyResize(withAlpha, width: decodeWidth);
        // Jangan copyExpandCanvas untuk premium: area transparan besar + flat marker di Android
        // sering tampil sebagai kotak hitam (semakin besar padding → semakin besar kotak).
        processed = _makeBackgroundTransparent(processed, forPassenger: true);
        try {
          final trimmed = img.trim(processed, mode: img.TrimMode.transparent);
          if (trimmed.width > 0 && trimmed.height > 0) processed = trimmed;
        } catch (_) {}
        final descriptor = await _descriptorFromProcessedImagePassenger(processed);
        if (name.contains('green')) {
          greenDesc = descriptor;
        } else if (name.contains('red')) {
          redDesc = descriptor;
        } else {
          blueDesc = descriptor;
        }
      }

      if (greenDesc == null || redDesc == null || blueDesc == null) {
        return null;
      }

      final set = PremiumPassengerCarIconSet(
        green: greenDesc,
        red: redDesc,
        blue: blueDesc,
      );
      _premiumCached = set;
      _premiumCachedBaseSize = baseSize;
      _premiumCachedPadding = padding;
      _premiumCachedDpr = dpr;
      _premiumCachedLogicVersion = _premiumProcessingVersion;
      _premiumCachedMapZoomKey = zoomKey;
      return set;
    } catch (e) {
      if (kDebugMode) debugPrint('[CarIconService] premium icons: $e');
      return null;
    }
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
    _cachedMapZoomKey = null;
    _premiumCached = null;
    _premiumCachedBaseSize = null;
    _premiumCachedPadding = null;
    _premiumCachedDpr = null;
    _premiumCachedLogicVersion = null;
    _premiumCachedMapZoomKey = null;
  }
}

