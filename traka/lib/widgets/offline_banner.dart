import 'package:flutter/material.dart';

import 'package:traka/services/connectivity_service.dart';
import 'package:traka/theme/app_theme.dart';
import 'package:traka/theme/traka_layout.dart';
import 'package:traka/widgets/traka_l10n_scope.dart';

/// Banner kuning di atas layar saat offline. Firestore persistence tetap tampilkan data cache.
class OfflineBanner extends StatelessWidget {
  const OfflineBanner({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: ConnectivityService.isOnlineNotifier,
      builder: (context, isOnline, _) {
        if (isOnline) return const SizedBox.shrink();
        final l10n = TrakaL10n.of(context);
        final band = Colors.amber.shade700;
        final onBand = trakaOnAccentForeground(band);
        return Material(
          color: band,
          elevation: 1,
          shadowColor: Theme.of(context).colorScheme.shadow,
          child: SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppTheme.spacingMd,
                vertical: AppTheme.spacingSm,
              ),
              child: Row(
                children: [
                  Icon(Icons.cloud_off, color: onBand, size: 20),
                  const SizedBox(width: AppTheme.spacingSm),
                  Expanded(
                    child: Text(
                      l10n.offlineBannerMessage,
                      style: TextStyle(
                        color: onBand,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
