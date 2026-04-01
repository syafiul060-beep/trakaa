import 'dart:math' show min;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_theme.dart';
import '../theme/map_control_chrome.dart';
import '../theme/responsive.dart';
import 'traka_l10n_scope.dart';
import 'traka_pin_widgets.dart';

/// Jarak bilah pencarian dari bawah — harus selaras dengan [PenumpangSearchBar].
const double kPenumpangSearchBarBottomInset = 80;

/// Ruang vertikal untuk kartu pencarian + celah agar CTA "Driver sekitar" tidak tertindih.
const double kPenumpangSearchBarStackReserve = 136;

/// Tombol "Driver sekitar" — gaya kartu mengambang (kontrol peta / ride-hailing).
class PenumpangDriverSekitarButton extends StatelessWidget {
  const PenumpangDriverSekitarButton({
    super.key,
    required this.visible,
    required this.onTap,
    this.loading = false,
  });

  final bool visible;
  final VoidCallback onTap;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    if (!visible) return const SizedBox.shrink();
    final cs = Theme.of(context).colorScheme;
    final pill = BorderRadius.circular(22);
    final surface = TrakaMapControlChrome.fabSurface(cs);
    final border = AppTheme.primary.withValues(alpha: loading ? 0.35 : 0.5);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: loading
            ? null
            : () {
                HapticFeedback.lightImpact();
                onTap();
              },
        borderRadius: pill,
        splashColor: TrakaMapControlChrome.splashForPrimary(context),
        highlightColor: AppTheme.primary.withValues(alpha: 0.06),
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: pill,
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: loading
                  ? [
                      Color.alphaBlend(
                        Colors.white.withValues(
                          alpha: cs.brightness == Brightness.dark ? 0.04 : 0.12,
                        ),
                        surface,
                      ),
                      Color.alphaBlend(
                        AppTheme.primary.withValues(alpha: 0.04),
                        surface,
                      ),
                    ]
                  : [
                      Color.alphaBlend(
                        Colors.white.withValues(
                          alpha: cs.brightness == Brightness.dark ? 0.08 : 0.28,
                        ),
                        Color.alphaBlend(
                          AppTheme.primary.withValues(alpha: 0.12),
                          surface,
                        ),
                      ),
                      Color.alphaBlend(
                        AppTheme.primary.withValues(alpha: 0.08),
                        Color.alphaBlend(
                          AppTheme.primary.withValues(alpha: 0.04),
                          surface,
                        ),
                      ),
                    ],
            ),
            border: Border.all(color: border, width: loading ? 1 : 1.2),
            boxShadow: TrakaMapControlChrome.floatingShadows(context),
          ),
          child: ClipRRect(
            borderRadius: pill,
            child: Stack(
              children: [
                Positioned(
                  left: 0,
                  right: 0,
                  top: 0,
                  height: 22,
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.white.withValues(
                              alpha: cs.brightness == Brightness.dark
                                  ? 0.1
                                  : 0.28,
                            ),
                            Colors.transparent,
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  child: loading
                      ? SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppTheme.primary.withValues(alpha: 0.85),
                          ),
                        )
                      : Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(6),
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                gradient: RadialGradient(
                                  colors: [
                                    AppTheme.primary.withValues(alpha: 0.2),
                                    AppTheme.primary.withValues(alpha: 0.06),
                                  ],
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: AppTheme.primary.withValues(
                                      alpha: 0.12,
                                    ),
                                    blurRadius: 6,
                                  ),
                                ],
                              ),
                              child: Icon(
                                Icons.near_me_rounded,
                                size: 18,
                                color: AppTheme.primary,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Text(
                              TrakaL10n.of(context).driverNearby,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.15,
                                color: AppTheme.primary.withValues(alpha: 0.96),
                                shadows: [
                                  Shadow(
                                    color: AppTheme.primary
                                        .withValues(alpha: 0.12),
                                    offset: const Offset(0, 1),
                                    blurRadius: 0,
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Baris quick action: hanya Driver sekitar.
class PenumpangQuickActionsRow extends StatelessWidget {
  const PenumpangQuickActionsRow({
    super.key,
    required this.visible,
    required this.onDriverSekitarTap,
    required this.nearbyRadiusKm,
    this.driverSekitarLoading = false,
  });

  final bool visible;
  final VoidCallback onDriverSekitarTap;
  /// Radius «Driver sekitar» (km) — tampil di bawah tombol.
  final int nearbyRadiusKm;
  final bool driverSekitarLoading;

  @override
  Widget build(BuildContext context) {
    if (!visible) return const SizedBox.shrink();
    final hp = context.responsive.horizontalPadding;
    return Positioned(
      left: hp,
      right: hp,
      bottom: kPenumpangSearchBarBottomInset + kPenumpangSearchBarStackReserve,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          PenumpangDriverSekitarButton(
            visible: true,
            onTap: onDriverSekitarTap,
            loading: driverSekitarLoading,
          ),
          const SizedBox(height: 4),
          Text(
            TrakaL10n.of(context).driverNearbyRadiusKm(nearbyRadiusKm),
            style: TextStyle(
              fontSize: 11,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

/// Bar pencarian - tap untuk buka form dalam bottom sheet.
class PenumpangSearchBar extends StatelessWidget {
  const PenumpangSearchBar({
    super.key,
    required this.visible,
    required this.currentLocationText,
    required this.destinationText,
    required this.onTap,
  });

  final bool visible;
  final String currentLocationText;
  final String destinationText;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    if (!visible) return const SizedBox.shrink();
    final r = context.responsive;
    final w = MediaQuery.sizeOf(context).width;
    // Bar tidak full-bleed: sisi kiri/kanan pakai IgnorePointer agar tap ke marker di peta tidak tertangkap InkWell.
    final maxBarW = min(380.0, (w - 40).clamp(200.0, 900.0));

    return Positioned(
      left: 0,
      right: 0,
      bottom: kPenumpangSearchBarBottomInset,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: IgnorePointer(
              ignoring: true,
              child: const SizedBox.shrink(),
            ),
          ),
          ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxBarW),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () {
                  HapticFeedback.lightImpact();
                  onTap();
                },
                borderRadius: BorderRadius.circular(18),
                splashColor: TrakaMapControlChrome.splashForPrimary(context),
                child: Ink(
                  padding: EdgeInsets.all(r.spacing(16)),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(18),
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        Color.alphaBlend(
                          Colors.white.withValues(
                            alpha:
                                Theme.of(context).brightness == Brightness.dark
                                    ? 0.05
                                    : 0.2,
                          ),
                          TrakaMapControlChrome.fabSurface(
                            Theme.of(context).colorScheme,
                          ),
                        ),
                        Color.alphaBlend(
                          Theme.of(context)
                              .colorScheme
                              .primary
                              .withValues(alpha: 0.06),
                          Color.alphaBlend(
                            Theme.of(context)
                                .colorScheme
                                .primary
                                .withValues(alpha: 0.03),
                            TrakaMapControlChrome.fabSurface(
                              Theme.of(context).colorScheme,
                            ),
                          ),
                        ),
                      ],
                    ),
                    border: Border.all(
                      color: TrakaMapControlChrome.fabBorder(
                        Theme.of(context).colorScheme,
                      ),
                    ),
                    boxShadow: TrakaMapControlChrome.floatingShadows(context),
                  ),
                  child: Stack(
                    children: [
                      Positioned(
                        left: 0,
                        right: 0,
                        top: 0,
                        height: 36,
                        child: IgnorePointer(
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [
                                  Colors.white.withValues(
                                    alpha: Theme.of(context).brightness ==
                                            Brightness.dark
                                        ? 0.08
                                        : 0.22,
                                  ),
                                  Colors.transparent,
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const TrakaPinFormIcon(
                                      variant: TrakaRoutePinVariant.origin,
                                    ),
                                    SizedBox(width: r.spacing(8)),
                                    Expanded(
                                      child: Text(
                                        currentLocationText,
                                        style: TextStyle(
                                          fontSize: r.fontSize(12),
                                          color: Theme.of(context)
                                              .colorScheme
                                              .onSurfaceVariant,
                                        ),
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                                SizedBox(height: r.spacing(8)),
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const TrakaPinFormIcon(
                                      variant: TrakaRoutePinVariant.destination,
                                    ),
                                    SizedBox(width: r.spacing(8)),
                                    Expanded(
                                      child: Text(
                                        destinationText.isEmpty
                                            ? 'Masukkan tujuan (contoh: Bandara, Terminal)'
                                            : destinationText,
                                        style: TextStyle(
                                          fontSize: r.fontSize(14),
                                          fontWeight: FontWeight.w500,
                                          color: destinationText.isEmpty
                                              ? Theme.of(context)
                                                  .colorScheme
                                                  .onSurfaceVariant
                                              : Theme.of(context)
                                                  .colorScheme
                                                  .onSurface,
                                        ),
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          SizedBox(width: r.spacing(8)),
                          Icon(
                            Icons.search_rounded,
                            color: AppTheme.primary,
                            size: 24,
                          ),
                          SizedBox(
                            width: 36,
                            height: 36,
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: AppTheme.primary.withValues(alpha: 0.1),
                                border: Border.all(
                                  color: AppTheme.primary.withValues(alpha: 0.22),
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: AppTheme.primary.withValues(alpha: 0.08),
                                    blurRadius: 8,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                              ),
                              child: Icon(
                                Icons.chevron_right_rounded,
                                size: 22,
                                color: AppTheme.primary.withValues(alpha: 0.9),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          Expanded(
            child: IgnorePointer(
              ignoring: true,
              child: const SizedBox.shrink(),
            ),
          ),
        ],
      ),
    );
  }
}

/// Banner gagal cari driver (dengan tombol Coba lagi).
class PenumpangSearchFailedBanner extends StatelessWidget {
  const PenumpangSearchFailedBanner({
    super.key,
    required this.visible,
    required this.onRetry,
  });

  final bool visible;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    if (!visible) return const SizedBox.shrink();
    return Positioned(
      left: 12,
      right: 12,
      top: MediaQuery.of(context).padding.top + 12,
      child: Material(
        elevation: 4,
        borderRadius: BorderRadius.circular(8),
        color: Theme.of(context).colorScheme.errorContainer,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              Icon(
                Icons.error_outline,
                size: 24,
                color: Theme.of(context).colorScheme.onErrorContainer,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  TrakaL10n.of(context).searchDriverFailed,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: Theme.of(context).colorScheme.onErrorContainer,
                  ),
                ),
              ),
              TextButton(
                onPressed: onRetry,
                child: Text(
                  TrakaL10n.of(context).retry,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: Theme.of(context).colorScheme.onErrorContainer,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
