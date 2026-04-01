import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'app_interaction_styles.dart';
import 'traka_visual_tokens.dart';

/// Tema aplikasi Traka — UX/UI modern konsisten di seluruh tampilan.
class AppTheme {
  AppTheme._();

  // ——— Warna utama — amber yang lebih lembut + teal (logo rangkong & mobil)
  static const Color primary = Color(0xFFD97706);
  static const Color primaryLight = Color(0xFFF59E0B);
  static const Color primaryDark = Color(0xFFB45309);
  static const Color secondary = Color(0xFF0D9488);
  static const Color surface = Color(0xFFFAF6F3);
  static const Color background = Color(0xFFFFFFFF);
  static const Color error = Color(0xFFB00020);
  static const Color onPrimary = Color(0xFFFFFFFF);
  static const Color onSurface = Color(0xFF1E293B);
  /// Sekunder: lebih gelap dari slate-500 agar teks kecil tetap terbaca di background terang (#F8FAFC).
  static const Color onSurfaceVariant = Color(0xFF475569);
  static const Color outline = Color(0xFFE2E8F0);

  /// Penjemputan di peta / daftar berhenti — amber Traka (bukan hijau merek lain).
  static const Color mapPickupAccent = Color(0xFFF9A825);

  /// Pengantaran / leg ke tujuan / ikon bendera — oranye dalam.
  static const Color mapDropoffAccent = Color(0xFFE65100);

  /// Chip & aksen “pengantaran” (hijau material) selaras shortcut peta.
  static const Color mapDeliveryAccent = Color(0xFF2E7D32);

  /// Warna rute alternatif indeks tinggi di peta driver.
  static const Color mapRouteOrange = Color(0xFFFB8C00);

  /// Rute alternatif indeks 4–5 (ungu / teal) — tetap khas di peta.
  static const Color mapRoutePurple = Color(0xFF7B1FA2);
  static const Color mapRouteTeal = Color(0xFF0097A7);

  /// Merah peta (berhenti, padat berat) — Material red 600.
  static const Color mapStopRed = Color(0xFFE53935);

  /// Splash: latar scaffold & gradien radial (hangat gelap, kontras logo terang).
  static const Color brandSplashBackground = Color(0xFF12100E);
  static const Color brandSplashMid = Color(0xFF1E2724);

  /// Teks / ikon gelap di atas aksen terang (banner, chip).
  static const Color onBrightAccentForeground = Color(0xFF0F172A);

  // ——— Radius & spacing
  static const double radiusXs = 8;
  static const double radiusSm = 12;
  static const double radiusMd = 16;
  static const double radiusLg = 22;
  static const double radiusXl = 26;
  static const double spacingXs = 4;
  static const double spacingSm = 8;
  static const double spacingMd = 16;
  static const double spacingLg = 24;
  static const double spacingXl = 32;

  /// Tipografi: Plus Jakarta Sans — modern, ramah layar, identitas sendiri.
  static TextTheme _textThemeLight(ColorScheme cs) {
    final seeded = ThemeData(useMaterial3: true, colorScheme: cs);
    return GoogleFonts.plusJakartaSansTextTheme(seeded.textTheme)
        .apply(
          bodyColor: onSurface,
          displayColor: onSurface,
        )
        .copyWith(
          displayLarge: GoogleFonts.plusJakartaSans(
            fontSize: 32,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.6,
            height: 1.16,
            color: onSurface,
          ),
          displayMedium: GoogleFonts.plusJakartaSans(
            fontSize: 28,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.45,
            height: 1.18,
            color: onSurface,
          ),
          headlineLarge: GoogleFonts.plusJakartaSans(
            fontSize: 24,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.25,
            height: 1.22,
            color: onSurface,
          ),
          headlineMedium: GoogleFonts.plusJakartaSans(
            fontSize: 20,
            fontWeight: FontWeight.w700,
            height: 1.25,
            color: onSurface,
          ),
          titleLarge: GoogleFonts.plusJakartaSans(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.12,
            color: onSurface,
          ),
          titleMedium: GoogleFonts.plusJakartaSans(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: onSurface,
          ),
          titleSmall: GoogleFonts.plusJakartaSans(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: onSurface,
          ),
          bodyLarge: GoogleFonts.plusJakartaSans(
            fontSize: 16,
            fontWeight: FontWeight.w400,
            height: 1.5,
            color: onSurface,
          ),
          bodyMedium: GoogleFonts.plusJakartaSans(
            fontSize: 14,
            fontWeight: FontWeight.w400,
            height: 1.45,
            color: onSurface,
          ),
          bodySmall: GoogleFonts.plusJakartaSans(
            fontSize: 12,
            fontWeight: FontWeight.w400,
            height: 1.4,
            color: onSurfaceVariant,
          ),
          labelLarge: GoogleFonts.plusJakartaSans(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.15,
            color: onSurface,
          ),
          labelMedium: GoogleFonts.plusJakartaSans(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: onSurfaceVariant,
          ),
        );
  }

  static TextTheme _textThemeDark(
    ColorScheme cs,
    Color onSurfaceD,
    Color onSurfaceVariantD,
  ) {
    final seeded =
        ThemeData(useMaterial3: true, colorScheme: cs, brightness: Brightness.dark);
    return GoogleFonts.plusJakartaSansTextTheme(seeded.textTheme)
        .apply(
          bodyColor: onSurfaceD,
          displayColor: onSurfaceD,
        )
        .copyWith(
          displayLarge: GoogleFonts.plusJakartaSans(
            fontSize: 32,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.6,
            height: 1.16,
            color: onSurfaceD,
          ),
          displayMedium: GoogleFonts.plusJakartaSans(
            fontSize: 28,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.45,
            height: 1.18,
            color: onSurfaceD,
          ),
          headlineLarge: GoogleFonts.plusJakartaSans(
            fontSize: 24,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.25,
            height: 1.22,
            color: onSurfaceD,
          ),
          headlineMedium: GoogleFonts.plusJakartaSans(
            fontSize: 20,
            fontWeight: FontWeight.w700,
            height: 1.25,
            color: onSurfaceD,
          ),
          titleLarge: GoogleFonts.plusJakartaSans(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.12,
            color: onSurfaceD,
          ),
          titleMedium: GoogleFonts.plusJakartaSans(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: onSurfaceD,
          ),
          titleSmall: GoogleFonts.plusJakartaSans(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: onSurfaceD,
          ),
          bodyLarge: GoogleFonts.plusJakartaSans(
            fontSize: 16,
            fontWeight: FontWeight.w400,
            height: 1.5,
            color: onSurfaceD,
          ),
          bodyMedium: GoogleFonts.plusJakartaSans(
            fontSize: 14,
            fontWeight: FontWeight.w400,
            height: 1.45,
            color: onSurfaceD,
          ),
          bodySmall: GoogleFonts.plusJakartaSans(
            fontSize: 12,
            fontWeight: FontWeight.w400,
            height: 1.4,
            color: onSurfaceVariantD,
          ),
          labelLarge: GoogleFonts.plusJakartaSans(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.15,
            color: onSurfaceD,
          ),
          labelMedium: GoogleFonts.plusJakartaSans(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: onSurfaceVariantD,
          ),
        );
  }

  static ThemeData get lightTheme {
    final colorScheme = ColorScheme.light(
      primary: primary,
      onPrimary: onPrimary,
      primaryContainer: primaryLight.withValues(alpha: 0.2),
      secondary: secondary,
      surface: surface,
      onSurface: onSurface,
      onSurfaceVariant: onSurfaceVariant,
      outline: outline,
      error: error,
      onError: Colors.white,
      surfaceContainerLowest: const Color(0xFFF8FAFC),
      surfaceContainerLow: background,
      surfaceContainer: const Color(0xFFF1F5F9),
      surfaceContainerHigh: const Color(0xFFE2E8F0),
      surfaceContainerHighest: const Color(0xFFCBD5E1),
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      visualDensity: VisualDensity.standard,
      scaffoldBackgroundColor: surface,
      textTheme: _textThemeLight(colorScheme),
      extensions: <ThemeExtension<dynamic>>[
        TrakaVisualTokens.light(colorScheme),
      ],
      splashFactory: InkSparkle.splashFactory,

      // AppBar — bersih, elevation 0
      appBarTheme: AppBarTheme(
        elevation: 0,
        scrolledUnderElevation: 0.5,
        centerTitle: false,
        backgroundColor: background,
        foregroundColor: onSurface,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: GoogleFonts.plusJakartaSans(
          fontSize: 18,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.15,
          color: onSurface,
        ),
        iconTheme: const IconThemeData(color: onSurface, size: 24),
      ),

      // Card — “lift” lembut + tepi berwarna merek sangat halus
      cardTheme: CardThemeData(
        elevation: 0,
        surfaceTintColor: primary.withValues(alpha: 0.05),
        shadowColor: colorScheme.shadow.withValues(alpha: 0.1),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusMd),
          side: BorderSide(
            color: primary.withValues(alpha: 0.08),
            width: 1,
          ),
        ),
        color: colorScheme.surfaceContainerLow,
        margin: const EdgeInsets.symmetric(
          horizontal: spacingMd,
          vertical: spacingSm,
        ),
        clipBehavior: Clip.antiAlias,
      ),
      scrollbarTheme: ScrollbarThemeData(
        thickness: WidgetStateProperty.all(6),
        radius: const Radius.circular(radiusXs),
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.dragged)) {
            return onSurfaceVariant.withValues(alpha: 0.55);
          }
          return onSurfaceVariant.withValues(alpha: 0.35);
        }),
      ),

      // Tombol utama: bayangan berwarna, radius 16, ripple halus (semua layar yang pakai tema)
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: AppInteractionStyles.elevatedPrimary(
          backgroundColor: primary,
          foregroundColor: onPrimary,
          shadowTint: primary,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: AppInteractionStyles.elevatedPrimary(
          backgroundColor: primary,
          foregroundColor: onPrimary,
          shadowTint: primary,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: AppInteractionStyles.outlinedModern(
          primaryColor: primary,
          outlineColor: outline,
          foregroundColor: primary,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: AppInteractionStyles.textModern(primaryColor: primary),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: AppInteractionStyles.iconButtonModern(
          primaryColor: primary,
          iconColor: onSurface,
        ),
      ),

      // InputDecoration — rounded, border jelas
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: background,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusSm),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusSm),
          borderSide: const BorderSide(color: outline),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusSm),
          borderSide: const BorderSide(color: primary, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusSm),
          borderSide: const BorderSide(color: error),
        ),
        labelStyle: const TextStyle(color: onSurfaceVariant, fontSize: 14),
        hintStyle: const TextStyle(color: onSurfaceVariant, fontSize: 14),
      ),

      // BottomNavigationBar — lebih tegas saat dipilih (weight & warna)
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: background,
        selectedItemColor: primary,
        selectedLabelStyle: GoogleFonts.plusJakartaSans(
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
        unselectedItemColor: onSurfaceVariant,
        unselectedLabelStyle: GoogleFonts.plusJakartaSans(
          fontSize: 12,
          fontWeight: FontWeight.w500,
        ),
        type: BottomNavigationBarType.fixed,
        elevation: 12,
        enableFeedback: true,
      ),

      navigationBarTheme: NavigationBarThemeData(
        indicatorColor: primary.withValues(alpha: 0.12),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return GoogleFonts.plusJakartaSans(
            fontSize: 12,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            color: selected ? primary : onSurfaceVariant,
          );
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return IconThemeData(
            color: selected ? primary : onSurfaceVariant,
            size: 24,
          );
        }),
      ),

      // TabBar (AppBar.bottom) — selaras M3, hindari Theme.primaryColor yang mudah tidak konsisten.
      tabBarTheme: TabBarThemeData(
        labelColor: primary,
        unselectedLabelColor: onSurfaceVariant,
        indicatorColor: primary,
        dividerColor: Colors.transparent,
      ),

      // ListTile
      listTileTheme: ListTileThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusSm),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: spacingMd,
          vertical: spacingXs,
        ),
      ),

      // Divider
      dividerTheme: const DividerThemeData(
        color: outline,
        thickness: 1,
        space: 1,
      ),

      // Chip
      chipTheme: ChipThemeData(
        backgroundColor: outline.withValues(alpha: 0.3),
        selectedColor: primaryLight.withValues(alpha: 0.3),
        labelStyle: GoogleFonts.plusJakartaSans(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: onSurfaceVariant,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusXs),
        ),
      ),

      // Dialog
      dialogTheme: DialogThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusLg),
        ),
        alignment: Alignment.center,
        actionsPadding: const EdgeInsets.fromLTRB(
          spacingMd,
          0,
          spacingMd,
          spacingMd,
        ),
        titleTextStyle: const TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w600,
          color: onSurface,
        ),
        contentTextStyle: const TextStyle(fontSize: 14, color: onSurface),
      ),

      // BottomSheet
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: background,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(radiusLg)),
        ),
        showDragHandle: true,
      ),

      // SnackBar — teks mengikuti onInverseSurface (bukan putih keras) agar kontras aman di M3
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusSm),
        ),
        backgroundColor: colorScheme.inverseSurface,
        contentTextStyle: TextStyle(
          fontSize: 14,
          color: colorScheme.onInverseSurface,
        ),
        actionTextColor: colorScheme.inversePrimary,
      ),

      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: primary,
        foregroundColor: onPrimary,
        elevation: 5,
        highlightElevation: 8,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusLg),
        ),
      ),

      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: primary,
        linearTrackColor: outline.withValues(alpha: 0.45),
        circularTrackColor: outline.withValues(alpha: 0.45),
      ),

      // Icon — konsisten, modern
      iconTheme: const IconThemeData(
        color: onSurfaceVariant,
        size: 24,
      ),

      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return primary;
          return null;
        }),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusXs / 2),
        ),
      ),

      // Transisi halaman — fade + slide halus
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: CupertinoPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
        },
      ),
    );
  }

  /// Tema gelap — mengikuti preferensi sistem.
  static ThemeData get darkTheme {
    const surfaceDark = Color(0xFF1E293B);
    const backgroundDark = Color(0xFF0F172A);
    const onSurfaceDark = Color(0xFFF1F5F9);
    const onSurfaceVariantDark = Color(0xFF94A3B8);
    const outlineDark = Color(0xFF334155);

    final colorScheme = ColorScheme.dark(
      primary: primaryLight,
      onPrimary: backgroundDark,
      primaryContainer: primaryDark,
      secondary: secondary,
      surface: surfaceDark,
      onSurface: onSurfaceDark,
      onSurfaceVariant: onSurfaceVariantDark,
      outline: outlineDark,
      error: const Color(0xFFCF6679),
      onError: backgroundDark,
      surfaceContainerLowest: backgroundDark,
      surfaceContainerLow: surfaceDark,
      surfaceContainer: const Color(0xFF334155),
      surfaceContainerHigh: const Color(0xFF475569),
      surfaceContainerHighest: const Color(0xFF64748B),
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: colorScheme,
      visualDensity: VisualDensity.standard,
      scaffoldBackgroundColor: backgroundDark,
      textTheme: _textThemeDark(
        colorScheme,
        onSurfaceDark,
        onSurfaceVariantDark,
      ),
      extensions: <ThemeExtension<dynamic>>[
        TrakaVisualTokens.dark(colorScheme),
      ],
      splashFactory: InkSparkle.splashFactory,
      appBarTheme: AppBarTheme(
        elevation: 0,
        scrolledUnderElevation: 0.5,
        centerTitle: false,
        backgroundColor: backgroundDark,
        foregroundColor: onSurfaceDark,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: GoogleFonts.plusJakartaSans(
          fontSize: 18,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.15,
          color: onSurfaceDark,
        ),
        iconTheme: const IconThemeData(color: onSurfaceDark, size: 24),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        surfaceTintColor: primaryLight.withValues(alpha: 0.08),
        shadowColor: colorScheme.shadow.withValues(alpha: 0.22),
        color: colorScheme.surfaceContainerLow,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusMd),
          side: BorderSide(
            color: primaryLight.withValues(alpha: 0.14),
            width: 1,
          ),
        ),
        margin: const EdgeInsets.symmetric(horizontal: spacingMd, vertical: spacingSm),
        clipBehavior: Clip.antiAlias,
      ),
      scrollbarTheme: ScrollbarThemeData(
        thickness: WidgetStateProperty.all(6),
        radius: const Radius.circular(radiusXs),
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.dragged)) {
            return onSurfaceVariantDark.withValues(alpha: 0.55);
          }
          return onSurfaceVariantDark.withValues(alpha: 0.35);
        }),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: AppInteractionStyles.elevatedPrimary(
          backgroundColor: primaryLight,
          foregroundColor: backgroundDark,
          shadowTint: primaryLight,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: AppInteractionStyles.elevatedPrimary(
          backgroundColor: primaryLight,
          foregroundColor: backgroundDark,
          shadowTint: primaryLight,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: AppInteractionStyles.outlinedModern(
          primaryColor: primaryLight,
          outlineColor: outlineDark,
          foregroundColor: primaryLight,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: AppInteractionStyles.textModern(primaryColor: primaryLight),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: AppInteractionStyles.iconButtonModern(
          primaryColor: primaryLight,
          iconColor: onSurfaceDark,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surfaceDark,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(radiusSm)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusSm),
          borderSide: const BorderSide(color: outlineDark),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusSm),
          borderSide: const BorderSide(color: primaryLight, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusSm),
          borderSide: const BorderSide(color: Color(0xFFCF6679)),
        ),
        labelStyle: const TextStyle(color: onSurfaceVariantDark, fontSize: 14),
        hintStyle: const TextStyle(color: onSurfaceVariantDark, fontSize: 14),
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: backgroundDark,
        selectedItemColor: primaryLight,
        selectedLabelStyle: GoogleFonts.plusJakartaSans(
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
        unselectedItemColor: onSurfaceVariantDark,
        unselectedLabelStyle: GoogleFonts.plusJakartaSans(
          fontSize: 12,
          fontWeight: FontWeight.w500,
        ),
        type: BottomNavigationBarType.fixed,
        elevation: 12,
        enableFeedback: true,
      ),
      navigationBarTheme: NavigationBarThemeData(
        indicatorColor: primaryLight.withValues(alpha: 0.18),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return GoogleFonts.plusJakartaSans(
            fontSize: 12,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            color: selected ? primaryLight : onSurfaceVariantDark,
          );
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return IconThemeData(
            color: selected ? primaryLight : onSurfaceVariantDark,
            size: 24,
          );
        }),
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: primaryLight,
        unselectedLabelColor: onSurfaceVariantDark,
        indicatorColor: primaryLight,
        dividerColor: Colors.transparent,
      ),
      listTileTheme: ListTileThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radiusSm)),
        contentPadding: const EdgeInsets.symmetric(horizontal: spacingMd, vertical: spacingXs),
      ),
      dividerTheme: const DividerThemeData(color: outlineDark, thickness: 1, space: 1),
      chipTheme: ChipThemeData(
        backgroundColor: outlineDark.withValues(alpha: 0.2),
        selectedColor: primaryLight.withValues(alpha: 0.2),
        labelStyle: GoogleFonts.plusJakartaSans(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: onSurfaceVariantDark,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radiusXs)),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: surfaceDark,
        alignment: Alignment.center,
        actionsPadding: const EdgeInsets.fromLTRB(
          spacingMd,
          0,
          spacingMd,
          spacingMd,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radiusLg)),
        titleTextStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: onSurfaceDark),
        contentTextStyle: const TextStyle(fontSize: 14, color: onSurfaceDark),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: surfaceDark,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(radiusLg)),
        ),
        showDragHandle: true,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radiusSm)),
        backgroundColor: colorScheme.inverseSurface,
        contentTextStyle: TextStyle(
          fontSize: 14,
          color: colorScheme.onInverseSurface,
        ),
        actionTextColor: colorScheme.inversePrimary,
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: primaryLight,
        foregroundColor: backgroundDark,
        elevation: 5,
        highlightElevation: 8,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusLg),
        ),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: primaryLight,
        linearTrackColor: outlineDark.withValues(alpha: 0.5),
        circularTrackColor: outlineDark.withValues(alpha: 0.5),
      ),
      iconTheme: const IconThemeData(color: onSurfaceVariantDark, size: 24),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return primaryLight;
          return null;
        }),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusXs / 2),
        ),
      ),

      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: CupertinoPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
        },
      ),
    );
  }
}
