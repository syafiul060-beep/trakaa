import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';

import 'low_ram_warning_service.dart';

/// Max dimensi gambar untuk OCR (standar).
const int _maxOcrDimension = 1200;

/// Max dimensi untuk HP RAM rendah (< 4 GB) — kurangi memori & percepat.
const int _maxOcrDimensionLowRam = 800;

/// Binarisasi sederhana: teks hitam di background terang (cocok KTP/SIM).
img.Image _binarize(img.Image im, {int threshold = 128}) {
  final out = img.Image(width: im.width, height: im.height);
  for (var y = 0; y < im.height; y++) {
    for (var x = 0; x < im.width; x++) {
      final p = im.getPixel(x, y);
      final lum = (p.r.toInt() + p.g.toInt() + p.b.toInt()) ~/ 3;
      final v = lum > threshold ? 255 : 0;
      out.setPixelRgb(x, y, v, v, v);
    }
  }
  return out;
}

/// Top-level untuk compute (isolate). Preprocess gambar agar tidak block UI.
/// args: [imagePath, tempDirPath, lowRam]
List<String> _preprocessOcrVariantsInIsolate(List<Object> args) {
  final imagePath = args[0] as String;
  final tempDirPath = args[1] as String;
  final lowRam = args.length > 2 && args[2] == true;
  const contrastLevel = 130.0;
  const contrastLevelHigh = 155.0;
  const sharpenWeight = 2.0;
  final maxDim = lowRam ? _maxOcrDimensionLowRam : _maxOcrDimension;

  try {
    final bytes = File(imagePath).readAsBytesSync();
    var decoded = img.decodeImage(bytes);
    if (decoded == null) return [imagePath];

    // Resize jika terlalu besar (hemat memori di HP RAM rendah)
    if (decoded.width > maxDim || decoded.height > maxDim) {
      if (decoded.width >= decoded.height) {
        decoded = img.copyResize(decoded, width: maxDim);
      } else {
        decoded = img.copyResize(decoded, height: maxDim);
      }
    }

    final save = (img.Image im, String suffix) {
      final outPath = '$tempDirPath/ocr_${suffix}_${DateTime.now().millisecondsSinceEpoch}.jpg';
      File(outPath).writeAsBytesSync(img.encodeJpg(im, quality: lowRam ? 85 : 90));
      return outPath;
    };

    // HP RAM rendah: 1 varian saja. Standar: 4 varian untuk KTP/SIM buram.
    final results = <String>[save(img.Image.from(decoded), 'orig')];
    if (!lowRam) {
      var base = img.grayscale(img.Image.from(decoded));
      base = img.contrast(base, contrast: contrastLevel);
      base = img.normalize(base, min: 0, max: 255);
      results.add(save(base, 'base'));

      // Sharpening: tepi teks lebih tajam (buram → lebih terbaca)
      var sharp = img.grayscale(img.Image.from(decoded));
      sharp = img.contrast(sharp, contrast: contrastLevel);
      sharp = img.smooth(sharp, weight: sharpenWeight);
      sharp = img.normalize(sharp, min: 0, max: 255);
      results.add(save(sharp, 'sharp'));

      // Kontras tinggi: teks pudar/aus lebih terbaca
      var high = img.grayscale(img.Image.from(decoded));
      high = img.contrast(high, contrast: contrastLevelHigh);
      high = img.normalize(high, min: 0, max: 255);
      results.add(save(high, 'high'));

      // Binarisasi: teks hitam-putih jelas (laminasi/silau)
      var bin = img.grayscale(img.Image.from(decoded));
      bin = img.contrast(bin, contrast: contrastLevel);
      bin = img.normalize(bin, min: 0, max: 255);
      bin = _binarize(bin, threshold: 128);
      results.add(save(bin, 'bin'));
    }

    return results;
  } catch (_) {
    return [imagePath];
  }
}

/// Preprocessing gambar untuk meningkatkan akurasi OCR.
/// Teknik: grayscale, contrast enhancement, sharpening, normalisasi.
class OcrPreprocessService {
  /// Kontras standar (130% = teks lebih tajam dari background).
  static const double _contrastLevel = 130;

  /// Kontras lebih tinggi untuk foto kurang kontras.
  static const double _contrastLevelHigh = 150;

  /// Weight untuk sharpening (smooth dengan weight > 1 = lebih tajam).
  static const double _sharpenWeight = 2.0;

  /// Preprocess gambar untuk OCR: grayscale + contrast + normalize.
  /// Return path file temp yang sudah dipreprocess, atau null jika gagal.
  static Future<String?> preprocessForOcr(String imagePath) async {
    return _savePreprocessed(imagePath, (image) {
      image = img.grayscale(image);
      image = img.contrast(image, contrast: _contrastLevel);
      image = img.normalize(image, min: 0, max: 255);
      return image;
    }, 'base');
  }

  /// Preprocess dengan kontras lebih tinggi.
  static Future<String?> preprocessForOcrContrastHigh(String imagePath) async {
    return _savePreprocessed(imagePath, (image) {
      image = img.grayscale(image);
      image = img.contrast(image, contrast: _contrastLevelHigh);
      image = img.normalize(image, min: 0, max: 255);
      return image;
    }, 'contrast');
  }

  /// Preprocess dengan sharpening (tepi teks lebih tajam).
  static Future<String?> preprocessForOcrSharpened(String imagePath) async {
    return _savePreprocessed(imagePath, (image) {
      image = img.grayscale(image);
      image = img.contrast(image, contrast: _contrastLevel);
      image = img.smooth(image, weight: _sharpenWeight);
      image = img.normalize(image, min: 0, max: 255);
      return image;
    }, 'sharp');
  }

  static Future<String?> _savePreprocessed(
    String imagePath,
    img.Image Function(img.Image) process,
    String suffix,
  ) async {
    try {
      final bytes = await File(imagePath).readAsBytes();
      var image = img.decodeImage(bytes);
      if (image == null) return null;
      image = img.Image.from(image);
      image = process(image);
      final dir = await getTemporaryDirectory();
      final outPath =
          '${dir.path}/ocr_${suffix}_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final outFile = File(outPath);
      await outFile.writeAsBytes(img.encodeJpg(image, quality: 95));
      return outPath;
    } catch (_) {
      return null;
    }
  }

  /// Buat beberapa varian preprocess untuk dicoba OCR.
  /// [imagePath] = path gambar asli.
  /// [lowRam] = null = deteksi otomatis dari RAM perangkat.
  static Future<List<String>> getOcrVariants(String imagePath, {bool? lowRam}) async {
    final dir = await getTemporaryDirectory();
    bool useLowRam;
    if (lowRam != null) {
      useLowRam = lowRam;
    } else {
      if (_cachedRamMb == null) _cachedRamMb = await LowRamWarningService.getDeviceRamMb();
      useLowRam = (_cachedRamMb ?? 9999) < 4096;
    }
    return compute(
      _preprocessOcrVariantsInIsolate,
      [imagePath, dir.path, useLowRam],
    );
  }

  /// Jalankan OCR pada beberapa varian gambar (original + preprocessed).
  /// Return list teks hasil OCR, urutan: original dulu, lalu preprocessed.
  /// Berguna untuk SIM/KTP: coba ekstrak dari tiap teks, ambil yang pertama valid.
  /// Preprocessing di isolate; OCR di main dengan yield agar UI tetap responsif.
  /// Timeout 45 detik agar tidak loading tanpa batas.
  static Future<List<String>> runOcrVariants(String imagePath) async {
    return _runOcrVariantsImpl(imagePath).timeout(
      const Duration(seconds: 45),
      onTimeout: () => throw TimeoutException(
        'Proses membaca dokumen terlalu lama. Silakan coba foto ulang dengan pencahayaan yang lebih baik.',
      ),
    );
  }

  static int? _cachedRamMb;

  static Future<List<String>> _runOcrVariantsImpl(String imagePath) async {
    final file = File(imagePath);
    if (!file.existsSync()) {
      throw Exception('File foto tidak ditemukan. Silakan ambil foto ulang.');
    }
    if (file.lengthSync() == 0) {
      throw Exception('File foto kosong atau rusak. Silakan ambil foto ulang.');
    }
    // HP RAM < 4 GB: 1 varian, ukuran 800px — kurangi memori & percepat
    final variants = await getOcrVariants(imagePath);
    if (variants.isEmpty) {
      throw Exception('Gagal memproses foto. Silakan ambil foto ulang dengan pencahayaan yang lebih baik.');
    }
    final results = <String>[];
    final textRecognizer = TextRecognizer(script: TextRecognitionScript.latin);

    try {
      for (final path in variants) {
        await Future<void>.delayed(Duration.zero); // Yield ke UI
        try {
          final inputImage = InputImage.fromFilePath(path);
          final recognized = await textRecognizer.processImage(inputImage);
          if (recognized.text.trim().isNotEmpty) {
            results.add(recognized.text);
          }
        } catch (_) {}
      }
    } finally {
      await textRecognizer.close();
    }

    return results;
  }
}
