import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../theme/responsive.dart';
import 'traka_l10n_scope.dart';

/// Judul AppBar Profil + versi app di kanan (satu baris), versi dalam chip ringan.
class ProfileAppBarTitle extends StatelessWidget {
  const ProfileAppBarTitle({super.key});

  @override
  Widget build(BuildContext context) {
    final r = context.responsive;
    final cs = Theme.of(context).colorScheme;
    final titleStyle = TextStyle(
      color: cs.primary,
      fontWeight: FontWeight.bold,
      fontSize: r.fontSize(18),
    );
    return Row(
      mainAxisSize: MainAxisSize.max,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Flexible(
          child: Text(
            TrakaL10n.of(context).navProfile,
            style: titleStyle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        SizedBox(width: r.spacing(10)),
        FutureBuilder<PackageInfo>(
          future: PackageInfo.fromPlatform(),
          builder: (context, snap) {
            final v = snap.data?.version ?? '…';
            final label = 'v$v';
            return Semantics(
              label: 'Versi aplikasi $label',
              child: _ProfileVersionChip(label: label),
            );
          },
        ),
      ],
    );
  }
}

class _ProfileVersionChip extends StatelessWidget {
  const _ProfileVersionChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final r = context.responsive;
    final cs = Theme.of(context).colorScheme;
    final textStyle = Theme.of(context).textTheme.labelSmall?.copyWith(
          fontSize: r.fontSize(11),
          color: cs.onSurfaceVariant,
          fontWeight: FontWeight.w600,
          height: 1.15,
        );
    return Material(
      color: Colors.transparent,
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: r.spacing(8),
          vertical: r.spacing(3),
        ),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest.withValues(alpha: 0.55),
          borderRadius: BorderRadius.circular(r.radius(8)),
          border: Border.all(
            color: cs.outlineVariant.withValues(alpha: 0.8),
          ),
        ),
        child: Text(label, style: textStyle, maxLines: 1),
      ),
    );
  }
}
