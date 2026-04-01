import 'package:flutter/material.dart';

import 'app_theme.dart';

/// Gaya kontrol mengambang di atas peta (Grab/Gojek-style): gradien halus, kilap atas, bayangan dalam.
abstract final class TrakaMapControlChrome {
  TrakaMapControlChrome._();

  static const double fabSize = 52;
  static const double fabRadius = 18;
  static const BorderRadius fabBorderRadius =
      BorderRadius.all(Radius.circular(fabRadius));

  static const EdgeInsets fabPadding = EdgeInsets.all(12);
  static const double iconSize = 26;
  /// Ikon jemput/antar di peta driver — sedikit lebih besar dari FAB standar.
  static const double stopShortcutIconSize = 30;

  /// Lapisan “kilap” di bagian atas FAB (glass-lite).
  static Widget fabTopGloss(
    BuildContext context, {
    double heightFactor = 0.42,
    double extent = fabSize,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final peak = isDark ? 0.12 : 0.24;
    return Positioned(
      left: 0,
      right: 0,
      top: 0,
      height: extent * heightFactor,
      child: IgnorePointer(
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.white.withValues(alpha: peak),
                Colors.white.withValues(alpha: 0),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Kilap untuk kolom zoom (tinggi 2× FAB).
  static Widget zoomStackTopGloss(BuildContext context) {
    return fabTopGloss(context, heightFactor: 0.22);
  }

  /// Garis hilite tipis di tepi atas (kedalaman fisik ringan).
  static Widget fabSpecularRim(BuildContext context) {
    final a = Theme.of(context).brightness == Brightness.dark ? 0.14 : 0.38;
    return Positioned(
      left: 10,
      right: 10,
      top: 5,
      height: 1,
      child: IgnorePointer(
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(1),
            gradient: LinearGradient(
              colors: [
                Colors.white.withValues(alpha: 0),
                Colors.white.withValues(alpha: a),
                Colors.white.withValues(alpha: 0),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static List<BoxShadow> floatingShadows(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final a = isDark ? 0.52 : 0.16;
    final b = isDark ? 0.32 : 0.1;
    final tint = AppTheme.primary.withValues(alpha: isDark ? 0.08 : 0.06);
    return [
      BoxShadow(
        color: Color.alphaBlend(tint, Colors.black.withValues(alpha: a)),
        blurRadius: 22,
        offset: const Offset(0, 10),
        spreadRadius: -3,
      ),
      BoxShadow(
        color: Colors.black.withValues(alpha: b),
        blurRadius: 10,
        offset: const Offset(0, 4),
      ),
    ];
  }

  static Color fabSurface(ColorScheme cs) {
    return cs.brightness == Brightness.dark
        ? cs.surfaceContainerHigh
        : Colors.white;
  }

  static Color fabBorder(ColorScheme cs) {
    return cs.outline
        .withValues(alpha: cs.brightness == Brightness.dark ? 0.38 : 0.14);
  }

  static LinearGradient fabFaceGradient(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final base = fabSurface(cs);
    final isDark = cs.brightness == Brightness.dark;
    final hi = Color.alphaBlend(
      Colors.white.withValues(alpha: isDark ? 0.07 : 0.22),
      base,
    );
    final lo = Color.alphaBlend(
      Colors.black.withValues(alpha: isDark ? 0.16 : 0.045),
      base,
    );
    return LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [hi, lo],
    );
  }

  static LinearGradient fabFaceGradientActive(
    BuildContext context,
    Color accent, {
    double mix = 0.13,
  }) {
    final cs = Theme.of(context).colorScheme;
    final base = fabSurface(cs);
    final tinted = Color.alphaBlend(accent.withValues(alpha: mix), base);
    final hi = Color.alphaBlend(
      Colors.white.withValues(
        alpha: cs.brightness == Brightness.dark ? 0.08 : 0.18,
      ),
      tinted,
    );
    final lo = Color.alphaBlend(
      accent.withValues(alpha: 0.06),
      Color.alphaBlend(
        Colors.black.withValues(
          alpha: cs.brightness == Brightness.dark ? 0.12 : 0.05,
        ),
        tinted,
      ),
    );
    return LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [hi, lo],
    );
  }

  /// Tombol ikon tunggal — permukaan gradien + border halus.
  static BoxDecoration fabDecoration(
    BuildContext context, {
    LinearGradient? gradient,
    Color? borderOverride,
    List<BoxShadow>? shadows,
  }) {
    final cs = Theme.of(context).colorScheme;
    return BoxDecoration(
      gradient: gradient ?? fabFaceGradient(context),
      borderRadius: fabBorderRadius,
      border: Border.all(
        color: borderOverride ?? fabBorder(cs),
        width: Theme.of(context).brightness == Brightness.dark ? 1 : 1.05,
      ),
      boxShadow: shadows ?? floatingShadows(context),
    );
  }

  static BoxDecoration zoomStackDecoration(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return BoxDecoration(
      gradient: fabFaceGradient(context),
      borderRadius: fabBorderRadius,
      border: Border.all(color: fabBorder(cs), width: 1.05),
      boxShadow: floatingShadows(context),
    );
  }

  static BoxDecoration fabDecorationActive(
    BuildContext context,
    Color accent, {
    double mix = 0.14,
  }) {
    return BoxDecoration(
      gradient: fabFaceGradientActive(context, accent, mix: mix),
      borderRadius: fabBorderRadius,
      border: Border.all(
        color: accent.withValues(alpha: 0.58),
        width: 1.35,
      ),
      boxShadow: [
        ...floatingShadows(context),
        BoxShadow(
          color: accent.withValues(alpha: 0.28),
          blurRadius: 14,
          offset: const Offset(0, 5),
          spreadRadius: -1,
        ),
      ],
    );
  }

  static Color splashForPrimary(BuildContext context) {
    return AppTheme.primary.withValues(alpha: 0.14);
  }

  /// Gradien untuk chip jemput/antar (dasar putih/surface + aksen).
  static BoxDecoration stopShortcutBaseDecoration(
    BuildContext context,
    Color accentColor,
    bool enabled,
  ) {
    final cs = Theme.of(context).colorScheme;
    final base = fabSurface(cs);
    final mid = enabled
        ? Color.alphaBlend(accentColor.withValues(alpha: 0.14), base)
        : base;
    final top = Color.alphaBlend(
      Colors.white.withValues(
        alpha: cs.brightness == Brightness.dark ? 0.06 : 0.2,
      ),
      mid,
    );
    final bottom = Color.alphaBlend(
      enabled
          ? accentColor.withValues(alpha: 0.07)
          : Colors.black.withValues(alpha: cs.brightness == Brightness.dark ? 0.1 : 0.04),
      mid,
    );
    return BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [top, bottom],
      ),
      borderRadius: fabBorderRadius,
      border: Border.all(
        color: enabled
            ? accentColor.withValues(alpha: 0.9)
            : fabBorder(cs),
        width: enabled ? 1.85 : 1.15,
      ),
      boxShadow: [
        ...floatingShadows(context),
        if (enabled)
          BoxShadow(
            color: accentColor.withValues(alpha: 0.26),
            blurRadius: 14,
            offset: const Offset(0, 5),
            spreadRadius: -1,
          ),
      ],
    );
  }
}
