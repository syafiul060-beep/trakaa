import 'package:flutter/material.dart';

import 'app_theme.dart';

/// Token & helper supaya sheet/modal mengikuti tema terpusat (bukan angka tersebar).
class TrakaUiHelpers {
  TrakaUiHelpers._();

  /// Bentuk sheet bawah: pakai [Theme.of(context).bottomSheetTheme.shape] jika ada.
  static ShapeBorder modalSheetShape(BuildContext context) {
    final fromTheme = Theme.of(context).bottomSheetTheme.shape;
    if (fromTheme != null) return fromTheme;
    return const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(
        top: Radius.circular(AppTheme.radiusLg),
      ),
    );
  }

  /// Judul dialog/sheet — selaras [DialogTheme.titleTextStyle].
  static TextStyle? dialogTitleStyle(BuildContext context) =>
      Theme.of(context).dialogTheme.titleTextStyle;

  /// Padding konten sheet standar (scrollable area).
  static EdgeInsets sheetBodyPadding(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    final h = 16.0 + (w > 400 ? 4.0 : 0.0);
    return EdgeInsets.fromLTRB(h, AppTheme.spacingMd, h, AppTheme.spacingMd);
  }
}
