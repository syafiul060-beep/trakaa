import 'package:flutter/material.dart';

import 'app_theme.dart';

/// Ekstensi tema Traka: gradien merek, backdrop layar — tanpa menyalin merek lain.
@immutable
class TrakaVisualTokens extends ThemeExtension<TrakaVisualTokens> {
  const TrakaVisualTokens({
    required this.screenBackdropGradient,
    required this.heroSheenGradient,
    required this.cardLiftShadow,
  });

  /// Latar aksen lembut untuk auth, form panjang, onboarding.
  final Gradient screenBackdropGradient;

  /// Sorotan diagonal untuk header / chip promosi (opsional).
  final Gradient heroSheenGradient;

  /// Bayangan kartu “mengambang” konsisten.
  final List<BoxShadow> cardLiftShadow;

  static TrakaVisualTokens light(ColorScheme cs) {
    final surface = cs.surface;
    return TrakaVisualTokens(
      screenBackdropGradient: LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        stops: const [0.0, 0.35, 1.0],
        colors: [
          Color.alphaBlend(AppTheme.primary.withValues(alpha: 0.09), surface),
          Color.alphaBlend(AppTheme.primary.withValues(alpha: 0.03), surface),
          surface,
        ],
      ),
      heroSheenGradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          AppTheme.primary.withValues(alpha: 0.2),
          AppTheme.primaryLight.withValues(alpha: 0.08),
          Colors.transparent,
        ],
        stops: const [0.0, 0.35, 1.0],
      ),
      cardLiftShadow: [
        BoxShadow(
          color: AppTheme.primary.withValues(alpha: 0.07),
          blurRadius: 24,
          offset: const Offset(0, 10),
          spreadRadius: -6,
        ),
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.06),
          blurRadius: 12,
          offset: const Offset(0, 4),
        ),
      ],
    );
  }

  static TrakaVisualTokens dark(ColorScheme cs) {
    final base = cs.surface;
    return TrakaVisualTokens(
      screenBackdropGradient: LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        stops: const [0.0, 0.4, 1.0],
        colors: [
          Color.alphaBlend(AppTheme.primaryLight.withValues(alpha: 0.12), base),
          Color.alphaBlend(AppTheme.primary.withValues(alpha: 0.05), base),
          base,
        ],
      ),
      heroSheenGradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          AppTheme.primaryLight.withValues(alpha: 0.22),
          AppTheme.primary.withValues(alpha: 0.1),
          Colors.transparent,
        ],
        stops: const [0.0, 0.4, 1.0],
      ),
      cardLiftShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.45),
          blurRadius: 28,
          offset: const Offset(0, 12),
          spreadRadius: -8,
        ),
        BoxShadow(
          color: AppTheme.primaryLight.withValues(alpha: 0.08),
          blurRadius: 16,
          offset: const Offset(0, 4),
        ),
      ],
    );
  }

  @override
  TrakaVisualTokens copyWith({
    Gradient? screenBackdropGradient,
    Gradient? heroSheenGradient,
    List<BoxShadow>? cardLiftShadow,
  }) {
    return TrakaVisualTokens(
      screenBackdropGradient:
          screenBackdropGradient ?? this.screenBackdropGradient,
      heroSheenGradient: heroSheenGradient ?? this.heroSheenGradient,
      cardLiftShadow: cardLiftShadow ?? this.cardLiftShadow,
    );
  }

  @override
  TrakaVisualTokens lerp(ThemeExtension<TrakaVisualTokens>? other, double t) {
    if (other is! TrakaVisualTokens) return this;
    return t < 0.5 ? this : other;
  }
}

extension TrakaVisualContext on BuildContext {
  TrakaVisualTokens? get trakaVisualTokens =>
      Theme.of(this).extension<TrakaVisualTokens>();
}
