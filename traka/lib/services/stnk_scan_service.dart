import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image_picker/image_picker.dart';

import '../utils/safe_navigation_utils.dart';
import '../utils/stnk_plate_extraction.dart';
import 'ocr_preprocess_service.dart';

/// Service untuk scan STNK/plat kendaraan via OCR.
/// Foto TIDAK disimpan ke server - hanya dipakai untuk ekstraksi teks.
/// Menggunakan preprocessing gambar + multi-attempt untuk akurasi lebih baik.
class StnkScanService {
  static final ImagePicker _picker = ImagePicker();

  /// Ambil foto dari kamera atau galeri, ekstrak nomor plat via OCR.
  /// Return nomor plat jika ditemukan; null jika gagal/tidak ditemukan.
  /// [context] opsional: jika disediakan, tampilkan loading "Membaca STNK..." saat proses OCR.
  static Future<String?> scanPlatFromCamera({BuildContext? context}) async {
    final XFile? image = await _picker.pickImage(
      source: ImageSource.camera,
      imageQuality: 100, // Kualitas maksimal untuk akurasi OCR
    );
    if (image == null) return null;
    final f = File(image.path);
    if (!f.existsSync() || f.lengthSync() == 0) return null;
    if (context != null && !context.mounted) return null;
    return _processWithLoading(image.path, context, 'Membaca STNK...');
  }

  static Future<String?> scanPlatFromGallery({BuildContext? context}) async {
    final XFile? image = await _picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 100, // Kualitas maksimal untuk akurasi OCR
    );
    if (image == null) return null;
    final f = File(image.path);
    if (!f.existsSync() || f.lengthSync() == 0) return null;
    if (context != null && !context.mounted) return null;
    return _processWithLoading(image.path, context, 'Membaca STNK...');
  }

  static Future<String?> _processWithLoading(
    String path,
    BuildContext? ctx,
    String loadingText,
  ) async {
    if (ctx != null && ctx.mounted) {
      await Future<void>.delayed(const Duration(milliseconds: 150));
      if (!ctx.mounted) return null;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (ctx.mounted) {
          showDialog<void>(
        context: ctx,
        barrierDismissible: false,
        builder: (c) => AlertDialog(
          backgroundColor: Theme.of(c).colorScheme.surface,
          content: Row(
            children: [
              CircularProgressIndicator(color: Theme.of(c).colorScheme.primary),
              const SizedBox(width: 16),
              Text(loadingText, style: TextStyle(color: Theme.of(c).colorScheme.onSurface)),
            ],
          ),
        ),
      );
        }
      });
    }
    await Future<void>.delayed(const Duration(milliseconds: 100));
    try {
      final result = await _processImage(path);
      if (ctx != null && ctx.mounted) {
        safePop(ctx);
      }
      return result;
    } catch (_) {
      if (ctx != null && ctx.mounted) {
        safePop(ctx);
      }
      return null;
    }
  }

  static Future<String?> _processImage(String path) async {
    try {
      if (!File(path).existsSync()) return null;
      final variants = await OcrPreprocessService.getOcrVariants(path);
      if (variants.isEmpty) return null;
      final voteCount = <String, int>{};

      for (final variantPath in variants) {
        await Future<void>.delayed(Duration.zero); // Yield ke UI
        final result = await _runOcrOnImage(variantPath);
        if (result != null && result.length >= 5) {
          final key = StnkPlateExtraction.normalizePlateKey(result);
          voteCount[key] = (voteCount[key] ?? 0) + 1;
        }
      }

      if (voteCount.isEmpty) return null;
      return voteCount.entries
          .reduce((a, b) => a.value >= b.value ? a : b)
          .key;
    } catch (_) {
      return null;
    }
  }

  /// Jalankan OCR pada satu gambar dan ekstrak plat (skor per baris + gabungan).
  static Future<String?> _runOcrOnImage(String path) async {
    final textRecognizer = TextRecognizer(script: TextRecognitionScript.latin);
    try {
      if (!File(path).existsSync()) return null;
      final inputImage = InputImage.fromFilePath(path);
      final recognizedText = await textRecognizer.processImage(inputImage);

      final all = <ScoredPlate>[];

      for (final block in recognizedText.blocks) {
        for (final line in block.lines) {
          final t = line.text;
          if (StnkPlateExtraction.isLineIgnoredForPlate(t)) continue;
          all.addAll(StnkPlateExtraction.extractScored(t, lineContext: t));
        }
      }

      var best = StnkPlateExtraction.pickBest(all);
      best ??= StnkPlateExtraction.pickBest(
        StnkPlateExtraction.extractScored(recognizedText.text),
      );
      return best;
    } catch (_) {
      return null;
    } finally {
      unawaited(textRecognizer.close());
    }
  }
}
