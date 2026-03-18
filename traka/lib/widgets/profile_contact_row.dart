import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../theme/responsive.dart';

/// Baris kontak (No. Telepon / Email) di sheet profil.
/// Dipakai oleh ProfilePenumpangScreen dan ProfileDriverScreen.
class ProfileContactRow extends StatelessWidget {
  const ProfileContactRow({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    required this.actionLabel,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String value;
  final String actionLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final responsive = context.responsive;
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: EdgeInsets.all(responsive.spacing(AppTheme.spacingMd)),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(responsive.radius(AppTheme.radiusSm)),
        border: Border.all(color: scheme.outline),
      ),
      child: Row(
        children: [
          Icon(icon, size: responsive.iconSize(24), color: AppTheme.primary),
          SizedBox(width: responsive.spacing(12)),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: responsive.fontSize(12),
                    fontWeight: FontWeight.w600,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                SizedBox(height: responsive.spacing(4)),
                Text(
                  value,
                  style: TextStyle(
                    fontSize: responsive.fontSize(14),
                    color: scheme.onSurface,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: onTap,
            child: Text(
              actionLabel,
              style: TextStyle(fontSize: responsive.fontSize(13)),
            ),
          ),
        ],
      ),
    );
  }
}
