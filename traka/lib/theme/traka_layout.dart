import 'package:flutter/material.dart';

import 'app_theme.dart';

/// Token jarak, radius, dan motion agar layar terasa konsisten (Material 3).
abstract final class TrakaLayout {
  TrakaLayout._();

  static BorderRadius brMicro = BorderRadius.circular(6);
  static BorderRadius brXs = BorderRadius.circular(AppTheme.radiusXs);
  static BorderRadius brSm = BorderRadius.circular(AppTheme.radiusSm);
  static BorderRadius brMd = BorderRadius.circular(AppTheme.radiusMd);
  static BorderRadius brLg = BorderRadius.circular(AppTheme.radiusLg);

  static const EdgeInsets padScreenH = EdgeInsets.symmetric(
    horizontal: AppTheme.spacingMd,
  );
  static const EdgeInsets padCard = EdgeInsets.all(AppTheme.spacingMd);
  static const EdgeInsets padSection = EdgeInsets.symmetric(
    vertical: AppTheme.spacingSm,
  );

  /// Transisi terang ↔ gelap di [MaterialApp].
  static const Duration themeSwitchDuration = Duration(milliseconds: 350);
  static const Curve themeSwitchCurve = Curves.easeOutCubic;

  /// Sheet / dialog ringan.
  static const Duration sheetEnterDuration = Duration(milliseconds: 280);
  static const Curve sheetEnterCurve = Curves.easeOutCubic;
}

/// Warna teks/ikon di atas latar [accent] pekat (banner, chip navigasi).
Color trakaOnAccentForeground(Color accent) {
  return ThemeData.estimateBrightnessForColor(accent) == Brightness.dark
      ? Colors.white
      : AppTheme.onBrightAccentForeground;
}
