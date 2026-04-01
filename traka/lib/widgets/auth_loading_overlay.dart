import 'package:flutter/material.dart';

import '../config/traka_lottie_assets.dart';
import 'traka_loading_indicator.dart';

/// Overlay semi-transparan + indikator bermerek saat login/daftar memproses.
/// Tanpa kartu putih di tengah — hanya spinner di atas scrim.
///
/// [opaqueBackdrop] — latar penuh mengikuti [ColorScheme.surface] (tanpa scrim tembus pandang).
/// Dipakai mis. di pendaftaran saat sambung Google: menghindari «kotak abu» lapisan native
/// yang terlihat di balik overlay transparan.
class AuthLoadingOverlay extends StatelessWidget {
  const AuthLoadingOverlay({
    super.key,
    required this.visible,
    this.message,
    this.useLottieCenter = false,
    this.lottieAssetPath,
    this.opaqueBackdrop = false,
  });

  final bool visible;
  final String? message;

  /// `true` → pusat loader memakai [TrakaLoadingIndicator.lottie] (file [lottieAssetPath] atau default).
  final bool useLottieCenter;

  /// Opsional; jika null dan [useLottieCenter], dipakai [TrakaLottieAssets.rangkongLoader].
  final String? lottieAssetPath;

  final bool opaqueBackdrop;

  @override
  Widget build(BuildContext context) {
    if (!visible) return const SizedBox.shrink();
    final cs = Theme.of(context).colorScheme;
    final dimmed = !opaqueBackdrop;
    final msgStyle = Theme.of(context).textTheme.bodyMedium?.copyWith(
          color: dimmed
              ? Colors.white.withValues(alpha: 0.95)
              : cs.onSurface.withValues(alpha: 0.88),
          height: 1.35,
          fontWeight: FontWeight.w600,
        );
    final loaderVariant = dimmed
        ? TrakaLoadingVariant.onDimmedBackdrop
        : TrakaLoadingVariant.onLightSurface;
    return Positioned.fill(
      child: AbsorbPointer(
        child: DecoratedBox(
          decoration: opaqueBackdrop
              ? BoxDecoration(color: cs.surface)
              : BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.45),
                ),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                useLottieCenter
                    ? TrakaLoadingIndicator.lottie(
                        size: 58,
                        variant: loaderVariant,
                        assetPath:
                            lottieAssetPath ?? TrakaLottieAssets.rangkongLoader,
                      )
                    : TrakaLoadingIndicator(
                        size: 58,
                        variant: loaderVariant,
                      ),
                if (message != null && message!.isNotEmpty) ...[
                  const SizedBox(height: 18),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32),
                    child: Text(
                      message!,
                      textAlign: TextAlign.center,
                      style: msgStyle,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
