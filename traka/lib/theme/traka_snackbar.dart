import 'package:flutter/material.dart';

import 'app_theme.dart';

/// SnackBar mengikuti [ColorScheme] (termasuk dark mode). Gantikan
/// `Colors.red` / `Colors.green` / `Colors.orange` pada [SnackBar].
abstract final class TrakaSnackBar {
  static SnackBar error(
    BuildContext context,
    Widget content, {
    Duration duration = const Duration(seconds: 4),
    SnackBarAction? action,
    SnackBarBehavior behavior = SnackBarBehavior.floating,
    EdgeInsetsGeometry? margin,
  }) {
    final cs = Theme.of(context).colorScheme;
    final base =
        Theme.of(context).textTheme.bodyMedium ?? const TextStyle(fontSize: 14);
    return SnackBar(
      content: DefaultTextStyle.merge(
        style: base.copyWith(color: cs.onError),
        child: IconTheme.merge(
          data: IconThemeData(color: cs.onError, size: 20),
          child: content,
        ),
      ),
      backgroundColor: cs.error,
      behavior: behavior,
      margin: margin,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppTheme.radiusSm),
      ),
      duration: duration,
      action: action,
    );
  }

  /// Sukses / konfirmasi positif — [ColorScheme.secondary] (teal Traka).
  static SnackBar success(
    BuildContext context,
    Widget content, {
    Duration duration = const Duration(seconds: 4),
    SnackBarAction? action,
    SnackBarBehavior behavior = SnackBarBehavior.floating,
    EdgeInsetsGeometry? margin,
  }) {
    final cs = Theme.of(context).colorScheme;
    final base =
        Theme.of(context).textTheme.bodyMedium ?? const TextStyle(fontSize: 14);
    return SnackBar(
      content: DefaultTextStyle.merge(
        style: base.copyWith(color: cs.onSecondary),
        child: IconTheme.merge(
          data: IconThemeData(color: cs.onSecondary, size: 20),
          child: content,
        ),
      ),
      backgroundColor: cs.secondary,
      behavior: behavior,
      margin: margin,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppTheme.radiusSm),
      ),
      duration: duration,
      action: action,
    );
  }

  /// Peringatan / perhatian — [ColorScheme.primary] (amber merek).
  static SnackBar warning(
    BuildContext context,
    Widget content, {
    Duration duration = const Duration(seconds: 4),
    SnackBarAction? action,
    SnackBarBehavior behavior = SnackBarBehavior.floating,
    EdgeInsetsGeometry? margin,
  }) {
    final cs = Theme.of(context).colorScheme;
    final base =
        Theme.of(context).textTheme.bodyMedium ?? const TextStyle(fontSize: 14);
    return SnackBar(
      content: DefaultTextStyle.merge(
        style: base.copyWith(color: cs.onPrimary),
        child: IconTheme.merge(
          data: IconThemeData(color: cs.onPrimary, size: 20),
          child: content,
        ),
      ),
      backgroundColor: cs.primary,
      behavior: behavior,
      margin: margin,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppTheme.radiusSm),
      ),
      duration: duration,
      action: action,
    );
  }

  /// Netral — mengikuti [SnackBarTheme] (inverseSurface / teks bawaan tema).
  static SnackBar info(
    BuildContext context,
    Widget content, {
    Duration duration = const Duration(seconds: 4),
    SnackBarAction? action,
    SnackBarBehavior behavior = SnackBarBehavior.floating,
    EdgeInsetsGeometry? margin,
  }) {
    final theme = Theme.of(context);
    final base = theme.textTheme.bodyMedium ?? const TextStyle(fontSize: 14);
    final fg =
        theme.snackBarTheme.contentTextStyle?.color ??
        theme.colorScheme.onInverseSurface;
    return SnackBar(
      content: DefaultTextStyle.merge(
        style: base.copyWith(color: fg),
        child: content,
      ),
      behavior: behavior,
      margin: margin,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppTheme.radiusSm),
      ),
      duration: duration,
      action: action,
    );
  }
}
