import 'package:app_settings/app_settings.dart';
import 'package:flutter/material.dart';

import '../services/app_analytics_service.dart';
import '../widgets/traka_l10n_scope.dart';

/// Profil → Notifikasi: penjelasan channel + buka pengaturan sistem (Android/iOS 16+).
class NotificationSettingsScreen extends StatefulWidget {
  const NotificationSettingsScreen({super.key});

  @override
  State<NotificationSettingsScreen> createState() =>
      _NotificationSettingsScreenState();
}

class _NotificationSettingsScreenState extends State<NotificationSettingsScreen> {
  @override
  void initState() {
    super.initState();
    AppAnalyticsService.logNotificationSettingsOpen();
  }

  Future<void> _openSystemNotificationSettings() async {
    AppAnalyticsService.logNotificationSettingsSystemTap();
    await AppSettings.openAppSettings(type: AppSettingsType.notification);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = TrakaL10n.of(context);
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.notificationSettingsTitle),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              l10n.notificationSettingsIntro,
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(height: 1.45),
            ),
            const SizedBox(height: 20),
            Text(
              l10n.notificationSettingsAndroidLocal,
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: cs.primary,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              l10n.notificationSettingsAndroidLocalBullets,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(height: 1.5),
            ),
            const SizedBox(height: 16),
            Text(
              l10n.notificationSettingsPushNote,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(height: 1.45),
            ),
            const SizedBox(height: 16),
            DecoratedBox(
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest.withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Text(
                  l10n.notificationSettingsIosNote,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(height: 1.4),
                ),
              ),
            ),
            const SizedBox(height: 28),
            FilledButton.icon(
              onPressed: _openSystemNotificationSettings,
              icon: const Icon(Icons.notifications_active_outlined),
              label: Text(l10n.notificationSettingsOpenSystem),
            ),
          ],
        ),
      ),
    );
  }
}
