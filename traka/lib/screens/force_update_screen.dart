import 'package:flutter/material.dart';

import '../services/app_update_service.dart';
import '../widgets/traka_l10n_scope.dart';

/// Layar update wajib ketika versi app < minVersion dari Firestore.
class ForceUpdateScreen extends StatelessWidget {
  const ForceUpdateScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.system_update,
                size: 80,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(height: 24),
              Text(
                TrakaL10n.of(context).updateRequired,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              Text(
                TrakaL10n.of(context).updateRequiredMessage,
                style: Theme.of(context).textTheme.bodyLarge,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),
              FilledButton.icon(
                onPressed: () => AppUpdateService.openPlayStore(),
                icon: const Icon(Icons.open_in_new),
                label: Text(TrakaL10n.of(context).openPlayStore),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 16,
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
