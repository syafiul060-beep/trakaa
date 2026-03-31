import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_theme.dart';
import 'traka_l10n_scope.dart';

/// Tombol navigasi premium di peta driver (kanan bawah setelah driver mulai rute).
/// Abu-abu bila ada tunggakan / tidak aktif; biru bila akses premium berjalan normal.
class DriverNavPremiumMapChip extends StatelessWidget {
  const DriverNavPremiumMapChip({
    super.key,
    required this.enabled,
    required this.debtBlocked,
    required this.tooltip,
    required this.onTap,
    this.dense = false,
  });

  final bool enabled;
  final bool debtBlocked;
  final String tooltip;
  final VoidCallback onTap;
  /// Ukuran lebih kecil di bar bawah driver aktif agar tidak memenuhi layar.
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final primary = AppTheme.primary;
    final active = enabled && !debtBlocked;
    final label = TrakaL10n.of(context).driverNavPremiumChipLabel;

    final Color bg;
    final Color fg;
    final Color border;
    if (debtBlocked || !active) {
      bg = colorScheme.surfaceContainerHighest;
      fg = colorScheme.onSurface.withValues(alpha: 0.45);
      border = colorScheme.outline.withValues(alpha: 0.4);
    } else {
      bg = primary;
      fg = Colors.white;
      border = primary.withValues(alpha: 0.9);
    }

    return Semantics(
      button: true,
      label: '$label. $tooltip',
      child: Tooltip(
        message: tooltip,
        child: Material(
          elevation: dense ? 3 : 4,
          borderRadius: BorderRadius.circular(dense ? 20 : 24),
          color: Colors.transparent,
          shadowColor: Colors.black.withValues(alpha: 0.1),
          child: InkWell(
            onTap: () {
              HapticFeedback.lightImpact();
              onTap();
            },
            borderRadius: BorderRadius.circular(dense ? 20 : 24),
            child: Container(
              padding: EdgeInsets.symmetric(
                horizontal: dense ? 12 : 14,
                vertical: dense ? 9 : 12,
              ),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(dense ? 20 : 24),
                color: bg,
                border: Border.all(color: border, width: debtBlocked ? 1.5 : 1),
                boxShadow: [
                  BoxShadow(
                    color: colorScheme.onSurface.withValues(alpha: 0.2),
                    blurRadius: 8,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    debtBlocked ? Icons.lock_outline : Icons.workspace_premium,
                    size: 22,
                    color: fg,
                  ),
                  SizedBox(width: dense ? 6 : 8),
                  Text(
                    label,
                    style: TextStyle(
                      color: fg,
                      fontWeight: FontWeight.bold,
                      fontSize: dense ? 13 : 14,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
