// Script: resize icon di assets/images/traka_car_icons_premium (satu folder; dipakai CarIconService).
// Run: dart run tools/sync_car_icons.dart
import 'dart:io';

import 'package:image/image.dart' as img;

void main() async {
  final premiumDir = Directory('assets/images/traka_car_icons_premium');
  if (!await premiumDir.exists()) {
    stdout.writeln('Folder ${premiumDir.path} tidak ditemukan');
    exit(1);
  }

  const size1x = 96;

  for (final name in ['car_red.png', 'car_green.png', 'car_blue.png']) {
    final src = File('${premiumDir.path}/$name');
    if (!await src.exists()) {
      stdout.writeln('Skip: $name tidak ada');
      continue;
    }

    final bytes = await src.readAsBytes();
    final decoded = img.decodeImage(bytes);
    if (decoded == null) {
      stdout.writeln('Gagal decode: $name');
      continue;
    }

    final resized = img.copyResize(
      decoded,
      width: size1x,
      height: size1x,
      interpolation: img.Interpolation.cubic,
    );
    await src.writeAsBytes(img.encodePng(resized));
    stdout.writeln('OK: traka_car_icons_premium/$name ke ${size1x}x$size1x');
  }
  stdout.writeln('Selesai.');
}
