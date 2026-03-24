import 'package:flutter/material.dart';

import 'traka_l10n_scope.dart';

/// Pilihan penumpang saat sudah ada order pra-sepakat ke driver yang sama.
enum PassengerDuplicatePendingChoice {
  cancel,
  openExisting,
  forceNew,
}

/// Nilai untuk Firebase Analytics ([AppAnalyticsService.logPassengerDuplicatePendingDialog]).
String passengerDuplicatePendingChoiceAnalyticsValue(
  PassengerDuplicatePendingChoice? choice,
) {
  if (choice == null) return 'dismiss';
  return switch (choice) {
    PassengerDuplicatePendingChoice.cancel => 'cancel',
    PassengerDuplicatePendingChoice.openExisting => 'open_existing',
    PassengerDuplicatePendingChoice.forceNew => 'force_new',
  };
}

Future<PassengerDuplicatePendingChoice?> showPassengerDuplicatePendingOrderDialog(
  BuildContext context, {
  required String title,
  required String body,
}) {
  final l10n = TrakaL10n.of(context);
  return showDialog<PassengerDuplicatePendingChoice>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: SingleChildScrollView(child: Text(body)),
      actions: [
        TextButton(
          onPressed: () =>
              Navigator.pop(ctx, PassengerDuplicatePendingChoice.cancel),
          child: Text(l10n.cancel),
        ),
        TextButton(
          onPressed: () =>
              Navigator.pop(ctx, PassengerDuplicatePendingChoice.forceNew),
          child: Text(l10n.passengerForceCreateNewOrderAnyway),
        ),
        FilledButton(
          onPressed: () =>
              Navigator.pop(ctx, PassengerDuplicatePendingChoice.openExisting),
          child: Text(l10n.passengerOpenExistingChat),
        ),
      ],
    ),
  );
}
