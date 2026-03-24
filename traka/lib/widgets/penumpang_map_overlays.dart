import 'dart:math' show min;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../theme/responsive.dart';
import 'traka_l10n_scope.dart';

/// Chip style untuk tombol quick action (pakai di Row).
Widget _buildQuickActionChip({
  required BuildContext context,
  required IconData icon,
  required String label,
  required VoidCallback onTap,
  bool loading = false,
}) {
  return Material(
    color: Colors.transparent,
    child: InkWell(
      onTap: loading ? null : onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: AppTheme.primary.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppTheme.primary.withValues(alpha: 0.4)),
        ),
        child: loading
            ? SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: AppTheme.primary,
                ),
              )
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 18, color: AppTheme.primary),
                  const SizedBox(width: 6),
                  Text(
                    label,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.primary,
                    ),
                  ),
                ],
              ),
      ),
    ),
  );
}

/// Tombol "Driver sekitar" - tampilkan driver aktif dalam radius 40 km tanpa isi tujuan.
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
    return _buildQuickActionChip(
      context: context,
      icon: Icons.near_me,
      label: TrakaL10n.of(context).driverNearby,
      onTap: onTap,
      loading: loading,
    );
  }
}

/// Tombol "Pesan nanti" - quick action ke Jadwal.
class PenumpangPesanNantiButton extends StatelessWidget {
  const PenumpangPesanNantiButton({
    super.key,
    required this.visible,
    required this.onTap,
  });

  final bool visible;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    if (!visible) return const SizedBox.shrink();
    return _buildQuickActionChip(
      context: context,
      icon: Icons.schedule,
      label: TrakaL10n.of(context).pesanNanti,
      onTap: onTap,
    );
  }
}

/// Baris tombol quick action: Driver sekitar + Pesan nanti.
class PenumpangQuickActionsRow extends StatelessWidget {
  const PenumpangQuickActionsRow({
    super.key,
    required this.visible,
    required this.onDriverSekitarTap,
    required this.onPesanNantiTap,
    this.driverSekitarLoading = false,
  });

  final bool visible;
  final VoidCallback onDriverSekitarTap;
  final VoidCallback onPesanNantiTap;
  final bool driverSekitarLoading;

  @override
  Widget build(BuildContext context) {
    if (!visible) return const SizedBox.shrink();
    final hp = context.responsive.horizontalPadding;
    return Positioned(
      left: hp,
      right: hp,
      bottom: 148,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Column(
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
                TrakaL10n.of(context).driverNearbyRadius,
                style: TextStyle(
                  fontSize: 11,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          PenumpangPesanNantiButton(
            visible: true,
            onTap: onPesanNantiTap,
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
      bottom: 80,
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
              elevation: 8,
              borderRadius: BorderRadius.circular(16),
              child: InkWell(
                onTap: onTap,
                borderRadius: BorderRadius.circular(16),
                child: Container(
                  padding: EdgeInsets.all(r.spacing(16)),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surface,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.search, color: AppTheme.primary, size: 24),
                      SizedBox(width: r.spacing(12)),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              currentLocationText,
                              style: TextStyle(
                                fontSize: r.fontSize(12),
                                color: Theme.of(context).colorScheme.onSurfaceVariant,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              destinationText.isEmpty
                                  ? 'Masukkan tujuan (contoh: Bandara, Terminal)'
                                  : destinationText,
                              style: TextStyle(
                                fontSize: r.fontSize(14),
                                fontWeight: FontWeight.w500,
                                color: destinationText.isEmpty
                                    ? Theme.of(context).colorScheme.onSurfaceVariant
                                    : Theme.of(context).colorScheme.onSurface,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      Icon(Icons.arrow_forward_ios, size: 16, color: AppTheme.primary),
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
