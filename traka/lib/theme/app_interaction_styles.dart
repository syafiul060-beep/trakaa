import 'package:flutter/material.dart';

import 'app_theme.dart';

/// Gaya interaksi modern (bayangan berwarna, radius, ripple) — dipakai [AppTheme]
/// agar semua tombol bawaan Material konsisten tanpa mengubah setiap layar.
abstract final class AppInteractionStyles {
  AppInteractionStyles._();

  static const double _ctaRadius = AppTheme.radiusLg;
  static const EdgeInsets _ctaPadding = EdgeInsets.symmetric(
    horizontal: AppTheme.spacingLg,
    vertical: 18,
  );

  /// Tombol berbahaya (hapus, blokir, keluar dari percakapan, dll.) — pakai [ColorScheme.error].
  static ButtonStyle destructive(ColorScheme colorScheme) {
    return elevatedPrimary(
      backgroundColor: colorScheme.error,
      foregroundColor: colorScheme.onError,
      shadowTint: colorScheme.error,
      disabledBackground: colorScheme.error.withValues(alpha: 0.38),
    );
  }

  /// Tombol utama (Elevated / Filled primary).
  static ButtonStyle elevatedPrimary({
    required Color backgroundColor,
    required Color foregroundColor,
    required Color shadowTint,
    Color? disabledBackground,
  }) {
    return ButtonStyle(
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      minimumSize: WidgetStateProperty.all(const Size(64, 52)),
      backgroundColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.disabled)) {
          return disabledBackground ?? backgroundColor.withValues(alpha: 0.38);
        }
        return backgroundColor;
      }),
      foregroundColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.disabled)) {
          return foregroundColor.withValues(alpha: 0.62);
        }
        return foregroundColor;
      }),
      elevation: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.disabled)) return 0.0;
        if (states.contains(WidgetState.pressed)) return 1.0;
        if (states.contains(WidgetState.hovered)) return 5.0;
        return 3.5;
      }),
      shadowColor: WidgetStateProperty.all(
        shadowTint.withValues(alpha: 0.42),
      ),
      surfaceTintColor: WidgetStateProperty.all(Colors.transparent),
      padding: WidgetStateProperty.all(_ctaPadding),
      shape: WidgetStateProperty.all(
        RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(_ctaRadius),
        ),
      ),
      textStyle: WidgetStateProperty.all(
        const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.2,
        ),
      ),
      overlayColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.pressed)) {
          return foregroundColor.withValues(alpha: 0.14);
        }
        if (states.contains(WidgetState.hovered)) {
          return foregroundColor.withValues(alpha: 0.08);
        }
        return null;
      }),
    );
  }

  /// Tombol outline — sedikit “lift” saat aktif + border tegas saat fokus.
  static ButtonStyle outlinedModern({
    required Color primaryColor,
    required Color outlineColor,
    required Color foregroundColor,
  }) {
    return OutlinedButton.styleFrom(
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      minimumSize: const Size(64, 48),
      padding: _ctaPadding,
      elevation: 0,
      shadowColor: primaryColor.withValues(alpha: 0.2),
      side: WidgetStateBorderSide.resolveWith((states) {
        final focused = states.contains(WidgetState.focused);
        final disabled = states.contains(WidgetState.disabled);
        if (disabled) {
          return BorderSide(
            color: outlineColor.withValues(alpha: 0.45),
          );
        }
        return BorderSide(
          color: focused ? primaryColor : outlineColor,
          width: focused ? 2 : 1.25,
        );
      }),
      foregroundColor: foregroundColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(_ctaRadius),
      ),
      textStyle: const TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.15,
      ),
    ).copyWith(
      elevation: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.disabled)) return 0.0;
        if (states.contains(WidgetState.pressed)) return 0.0;
        return 0.5;
      }),
      overlayColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.pressed)) {
          return primaryColor.withValues(alpha: 0.12);
        }
        if (states.contains(WidgetState.hovered)) {
          return primaryColor.withValues(alpha: 0.06);
        }
        return null;
      }),
    );
  }

  /// TextButton — ripple halus + bentuk membulat (tap feel modern).
  static ButtonStyle textModern({
    required Color primaryColor,
  }) {
    return TextButton.styleFrom(
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      minimumSize: const Size(48, 44),
      padding: const EdgeInsets.symmetric(
        horizontal: AppTheme.spacingMd,
        vertical: AppTheme.spacingSm,
      ),
      foregroundColor: primaryColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppTheme.radiusSm),
      ),
      textStyle: const TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w600,
      ),
    ).copyWith(
      overlayColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.pressed)) {
          return primaryColor.withValues(alpha: 0.14);
        }
        if (states.contains(WidgetState.hovered)) {
          return primaryColor.withValues(alpha: 0.08);
        }
        return null;
      }),
    );
  }

  /// IconButton di AppBar / list — sudut membulat + ripple bermerek.
  static ButtonStyle iconButtonModern({
    required Color primaryColor,
    required Color iconColor,
  }) {
    return IconButton.styleFrom(
      foregroundColor: iconColor,
      hoverColor: primaryColor.withValues(alpha: 0.08),
      highlightColor: primaryColor.withValues(alpha: 0.14),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppTheme.radiusSm),
      ),
    );
  }

  /// Label isi [FilledButton] auth — warna teks dari tema tombol.
  static const TextStyle authCtaLabelStyle = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w700,
    letterSpacing: 0.2,
    height: 1.25,
  );

  /// Tombol utama login & daftar (Masuk, Kirim kode, dll.) — radius LG + tinggi tap konsisten.
  static ButtonStyle authPrimaryCta(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return elevatedPrimary(
      backgroundColor: cs.primary,
      foregroundColor: cs.onPrimary,
      shadowTint: cs.primary,
    ).copyWith(
      minimumSize: WidgetStateProperty.all(const Size(64, 54)),
      padding: WidgetStateProperty.all(
        const EdgeInsets.symmetric(
          horizontal: AppTheme.spacingLg,
          vertical: 16,
        ),
      ),
      textStyle: WidgetStateProperty.all(authCtaLabelStyle),
    );
  }

  /// Daftar: merek penuh hanya jika [agreeToTerms]; netral M3 jika belum centang.
  static ButtonStyle registerTermsSubmit(
    BuildContext context, {
    required bool agreeToTerms,
  }) {
    final cs = Theme.of(context).colorScheme;
    final brand = cs.primary;
    final inactiveBg = cs.surfaceContainerHighest;
    final inactiveFg = cs.onSurfaceVariant;
    return elevatedPrimary(
      backgroundColor: brand,
      foregroundColor: cs.onPrimary,
      shadowTint: brand,
      disabledBackground: inactiveBg,
    ).copyWith(
      minimumSize: WidgetStateProperty.all(const Size(64, 54)),
      padding: WidgetStateProperty.all(
        const EdgeInsets.symmetric(
          horizontal: AppTheme.spacingLg,
          vertical: 16,
        ),
      ),
      textStyle: WidgetStateProperty.all(authCtaLabelStyle),
      backgroundColor: WidgetStateProperty.resolveWith((states) {
        if (!agreeToTerms) return inactiveBg;
        if (states.contains(WidgetState.disabled)) {
          return brand.withValues(alpha: 0.55);
        }
        return brand;
      }),
      foregroundColor: WidgetStateProperty.resolveWith((states) {
        if (!agreeToTerms) return inactiveFg;
        if (states.contains(WidgetState.disabled)) {
          return cs.onPrimary.withValues(alpha: 0.92);
        }
        return cs.onPrimary;
      }),
      shadowColor: WidgetStateProperty.resolveWith((states) {
        if (!agreeToTerms) return Colors.transparent;
        return brand.withValues(alpha: 0.42);
      }),
      elevation: WidgetStateProperty.resolveWith((states) {
        if (!agreeToTerms) return 0.0;
        if (states.contains(WidgetState.disabled)) return 1.0;
        if (states.contains(WidgetState.pressed)) return 1.0;
        if (states.contains(WidgetState.hovered)) return 5.0;
        return 3.5;
      }),
    );
  }

  /// [ThemeData.filledButtonTheme] + override opsional.
  static ButtonStyle filledFromTheme(
    BuildContext context, {
    EdgeInsetsGeometry? padding,
    double? minHeight,
  }) {
    var s = Theme.of(context).filledButtonTheme.style;
    if (s == null) {
      return FilledButton.styleFrom(
        padding: padding as EdgeInsets?,
        minimumSize: minHeight != null ? Size(64, minHeight) : null,
      );
    }
    if (padding != null) {
      s = s.copyWith(padding: WidgetStateProperty.all(padding));
    }
    if (minHeight != null) {
      s = s.copyWith(
        minimumSize: WidgetStateProperty.all(Size(64, minHeight)),
      );
    }
    return s;
  }

  /// [ThemeData.elevatedButtonTheme] + override opsional.
  static ButtonStyle elevatedFromTheme(
    BuildContext context, {
    EdgeInsetsGeometry? padding,
  }) {
    var s = Theme.of(context).elevatedButtonTheme.style;
    if (s == null) {
      return ElevatedButton.styleFrom(padding: padding as EdgeInsets?);
    }
    if (padding != null) {
      s = s.copyWith(padding: WidgetStateProperty.all(padding));
    }
    return s;
  }

  /// [ThemeData.outlinedButtonTheme] + override opsional.
  static ButtonStyle outlinedFromTheme(
    BuildContext context, {
    EdgeInsetsGeometry? padding,
    Color? sideColor,
    double sideWidth = 1.25,
  }) {
    var s = Theme.of(context).outlinedButtonTheme.style;
    if (s == null) {
      return OutlinedButton.styleFrom(padding: padding as EdgeInsets?);
    }
    if (padding != null) {
      s = s.copyWith(padding: WidgetStateProperty.all(padding));
    }
    if (sideColor != null) {
      s = s.copyWith(
        side: WidgetStateProperty.all(
          BorderSide(color: sideColor, width: sideWidth),
        ),
      );
    }
    return s;
  }

  /// [ThemeData.textButtonTheme] + override opsional.
  static ButtonStyle textFromTheme(
    BuildContext context, {
    EdgeInsetsGeometry? padding,
    Color? foregroundColor,
  }) {
    var s = Theme.of(context).textButtonTheme.style;
    if (s == null) return TextButton.styleFrom(padding: padding as EdgeInsets?);
    if (padding != null) {
      s = s.copyWith(padding: WidgetStateProperty.all(padding));
    }
    if (foregroundColor != null) {
      s = s.copyWith(
        foregroundColor: WidgetStateProperty.all(foregroundColor),
      );
    }
    return s;
  }

  /// [ThemeData.iconButtonTheme] + override opsional — untuk `IconButton` / `IconButton.filled`.
  static ButtonStyle iconButtonFromTheme(
    BuildContext context, {
    EdgeInsetsGeometry? padding,
    Size? minimumSize,
    MaterialTapTargetSize? tapTargetSize,
  }) {
    var s = Theme.of(context).iconButtonTheme.style;
    if (s == null) {
      return IconButton.styleFrom(
        padding: padding,
        minimumSize: minimumSize,
        tapTargetSize: tapTargetSize,
      );
    }
    if (padding != null) {
      s = s.copyWith(padding: WidgetStateProperty.all(padding));
    }
    if (minimumSize != null) {
      s = s.copyWith(minimumSize: WidgetStateProperty.all(minimumSize));
    }
    if (tapTargetSize != null) {
      s = s.copyWith(tapTargetSize: tapTargetSize);
    }
    return s;
  }
}
