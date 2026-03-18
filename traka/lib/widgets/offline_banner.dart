import 'package:flutter/material.dart';

import 'package:traka/services/connectivity_service.dart';
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
        return Material(
          color: Colors.amber.shade700,
          child: SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  Icon(Icons.cloud_off, color: Colors.white, size: 20),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      l10n.offlineBannerMessage,
                      style: TextStyle(
                        color: Colors.white,
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
