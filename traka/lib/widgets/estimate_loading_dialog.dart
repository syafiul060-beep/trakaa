import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import 'traka_loading_indicator.dart';

/// Dialog non-dismissible sementara [action] berjalan (hitung estimasi jarak/kontribusi).
Future<T> runWithEstimateLoading<T>(
  BuildContext context,
  AppLocalizations l10n,
  Future<T> Function() action,
) async {
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    useRootNavigator: true,
    builder: (ctx) => PopScope(
      canPop: false,
      child: Semantics(
        label: l10n.calculatingEstimate,
        child: AlertDialog(
          shape: Theme.of(ctx).dialogTheme.shape,
          content: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const TrakaLoadingIndicator(size: 40),
              const SizedBox(width: 20),
              Expanded(
                child: Text(
                  l10n.calculatingEstimate,
                  style: Theme.of(ctx).textTheme.bodyLarge,
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
  try {
    return await action();
  } finally {
    if (context.mounted) {
      Navigator.of(context, rootNavigator: true).pop();
    }
  }
}
