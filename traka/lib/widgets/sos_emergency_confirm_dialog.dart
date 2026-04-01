import 'package:flutter/material.dart';

import '../theme/app_interaction_styles.dart';
import '../services/admin_contact_config_service.dart';
import 'traka_l10n_scope.dart';

/// Konfirmasi sebelum kirim SOS; teks menyesuaikan apakah jalur WhatsApp admin aktif.
Future<bool?> showSosEmergencyConfirmDialog(BuildContext context) async {
  await AdminContactConfigService.load(force: true);
  if (!context.mounted) return null;
  final l10n = TrakaL10n.of(context);
  final body = AdminContactConfigService.adminWhatsAppEnabled
      ? l10n.sosConfirmDialogBodyWhenWhatsApp
      : l10n.sosConfirmDialogBodyWhenLiveChatOnly;
  return showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(l10n.sosConfirmDialogTitle),
      content: Text(body),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          style: AppInteractionStyles.destructive(Theme.of(ctx).colorScheme),
          child: Text(l10n.sosConfirmSendAction),
        ),
      ],
    ),
  );
}
