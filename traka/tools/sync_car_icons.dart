// Script: sesuaikan ukuran icon mobil per folder (1x, 2.0x, 3.0x).
// Masing-masing folder punya ukuran berbeda untuk layar berbeda.
// Run: dart run tools/sync_car_icons.dart
import 'dart:io';

import 'package:image/image.dart' as img;

void main() async {
  final baseDir = Directory('assets/images');
  if (!await baseDir.exists()) {
    print('Folder assets/images tidak ditemukan');
    exit(1);
  }

  // Ukuran standar per density (masing-masing beda, bukan copy mentah):
  // 1x   = 96x96   → layar biasa (fallback)
  // 2.0x = 192x192 → layar retina (kebanyakan HP)
  // 3.0x = 288x288 → layar high-DPI (flagship)
  const size1x = 96;
  const size2x = 192;
  const size3x = 288;

  for (final name in ['car_merah.png', 'car_hijau.png']) {
    final src = File('${baseDir.path}/$name');
    if (!await src.exists()) {
      print('Skip: $name tidak ada');
      continue;
    }

    final bytes = await src.readAsBytes();
    final decoded = img.decodeImage(bytes);
    if (decoded == null) {
      print('Gagal decode: $name');
      continue;
    }

    // 1x: resize ke 96x96 (assets/images/ - fallback layar biasa)
    final resized1 = img.copyResize(decoded, width: size1x, height: size1x,
        interpolation: img.Interpolation.cubic);
    await src.writeAsBytes(img.encodePng(resized1));
    print('OK: $name → 1x (${size1x}x$size1x)');

    // 2.0x: resize ke 192x192 (ukuran sesuai density, bukan copy mentah)
    final dir2 = Directory('${baseDir.path}/2.0x');
    await dir2.create(recursive: true);
    final resized2 = img.copyResize(decoded, width: size2x, height: size2x,
        interpolation: img.Interpolation.cubic);
    await File('${dir2.path}/$name').writeAsBytes(img.encodePng(resized2));
    print('OK: 2.0x/$name (${size2x}x$size2x)');

    // 3.0x: resize ke 288x288 (ukuran sesuai density, bukan copy mentah)
    final dir3 = Directory('${baseDir.path}/3.0x');
    await dir3.create(recursive: true);
    final resized3 = img.copyResize(decoded, width: size3x, height: size3x,
        interpolation: img.Interpolation.cubic);
    await File('${dir3.path}/$name').writeAsBytes(img.encodePng(resized3));
    print('OK: 3.0x/$name (${size3x}x$size3x)');
  }
  print('Selesai. Masing-masing folder punya ukuran sesuai fungsinya.');
}
