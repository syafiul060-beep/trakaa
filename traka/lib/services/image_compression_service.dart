import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:path_provider/path_provider.dart';

/// Kompresi gambar sebelum upload ke Firebase Storage.
class ImageCompressionService {
  /// Kompresi file dari path. Mengembalikan path file terkompresi atau path asli jika gagal.
  static Future<String> compressForUpload(String filePath) async {
    final file = File(filePath);
    final result = await compressFile(file);
    return result?.path ?? filePath;
  }

  /// Kompresi file gambar. Mengembalikan path file terkompresi atau null jika gagal.
  /// [maxWidth] default 1920, [quality] 0-100 default 85.
  static Future<File?> compressFile(
    File file, {
    int maxWidth = 1920,
    int quality = 85,
  }) async {
    try {
      final dir = await getTemporaryDirectory();
      final targetPath =
          '${dir.path}/traka_compressed_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final result = await FlutterImageCompress.compressAndGetFile(
        file.absolute.path,
        targetPath,
        quality: quality,
        minWidth: maxWidth,
        minHeight: maxWidth,
      );
      return result != null ? File(result.path) : null;
    } catch (e, st) {
      if (kDebugMode) debugPrint('ImageCompressionService.compressFile: $e\n$st');
      return null;
    }
  }

  /// Kompresi bytes (dari image picker). Mengembalikan bytes terkompresi.
  static Future<List<int>?> compressBytes(
    List<int> bytes, {
    int maxWidth = 1920,
    int quality = 85,
  }) async {
    try {
      return await FlutterImageCompress.compressWithList(
        Uint8List.fromList(bytes),
        minWidth: maxWidth,
        minHeight: maxWidth,
        quality: quality,
      );
    } catch (e, st) {
      if (kDebugMode) debugPrint('ImageCompressionService.compressBytes: $e\n$st');
      return null;
    }
  }
}
