import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../theme/traka_layout.dart';

/// State kosong konsisten (ikon + judul + opsional subjudul + aksi).
class TrakaEmptyState extends StatelessWidget {
  const TrakaEmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.action,
    this.iconSize = 56,
    this.iconColor,
    this.titleColor,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? action;
  final double iconSize;
  /// Jika non-null, mengganti warna ikon default (mis. [ColorScheme.error] untuk state gagal).
  final Color? iconColor;
  /// Jika non-null, mengganti warna judul default.
  final Color? titleColor;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Padding(
      padding: TrakaLayout.padScreenH +
          const EdgeInsets.symmetric(vertical: AppTheme.spacingXl),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: iconSize,
            color: iconColor ??
                cs.onSurfaceVariant.withValues(alpha: 0.65),
          ),
          SizedBox(height: AppTheme.spacingMd),
          Text(
            title,
            style: tt.titleMedium?.copyWith(color: titleColor ?? cs.onSurface),
            textAlign: TextAlign.center,
          ),
          if (subtitle != null && subtitle!.isNotEmpty) ...[
            SizedBox(height: AppTheme.spacingSm),
            Text(
              subtitle!,
              style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant, height: 1.35),
              textAlign: TextAlign.center,
            ),
          ],
          if (action != null) ...[
            SizedBox(height: AppTheme.spacingLg),
            action!,
          ],
        ],
      ),
    );
  }
}
