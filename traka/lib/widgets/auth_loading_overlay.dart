import 'package:flutter/material.dart';

import '../config/traka_lottie_assets.dart';
import 'traka_loading_indicator.dart';

/// Overlay semi-transparan + indikator bermerek saat login/daftar memproses.
/// Tanpa kartu putih di tengah — hanya spinner di atas scrim.
class AuthLoadingOverlay extends StatelessWidget {
  const AuthLoadingOverlay({
    super.key,
    required this.visible,
    this.message,
    this.useLottieCenter = false,
    this.lottieAssetPath,
  });

  final bool visible;
  final String? message;

  /// `true` → pusat loader memakai [TrakaLoadingIndicator.lottie] (file [lottieAssetPath] atau default).
  final bool useLottieCenter;

  /// Opsional; jika null dan [useLottieCenter], dipakai [TrakaLottieAssets.rangkongLoader].
  final String? lottieAssetPath;

  @override
  Widget build(BuildContext context) {
    if (!visible) return const SizedBox.shrink();
    final cs = Theme.of(context).colorScheme;
    final msgStyle = Theme.of(context).textTheme.bodyMedium?.copyWith(
          color: Colors.white.withValues(alpha: 0.92),
          height: 1.35,
          shadows: [
            Shadow(
              color: cs.scrim.withValues(alpha: 0.85),
              blurRadius: 8,
            ),
          ],
        );
    return Positioned.fill(
      child: AbsorbPointer(
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                cs.scrim.withValues(alpha: 0.42),
                cs.scrim.withValues(alpha: 0.52),
              ],
            ),
          ),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                useLottieCenter
                    ? TrakaLoadingIndicator.lottie(
                        size: 58,
                        variant: TrakaLoadingVariant.onDimmedBackdrop,
                        assetPath:
                            lottieAssetPath ?? TrakaLottieAssets.rangkongLoader,
                      )
                    : const TrakaLoadingIndicator(
                        size: 58,
                        variant: TrakaLoadingVariant.onDimmedBackdrop,
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
