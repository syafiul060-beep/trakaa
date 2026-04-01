import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../services/app_analytics_service.dart';
import '../theme/traka_snackbar.dart';

/// SnackBar + analytics untuk [FirebaseAuth.verifyPhoneNumber] gagal — sama di login, daftar, profil, lupa sandi.
void showPhoneVerificationFailedSnackBar(
  BuildContext context, {
  required FirebaseAuthException exception,
  required String analyticsSource,
  required AppLocalizations l10n,
}) {
  AppAnalyticsService.logPhoneVerificationFailed(
    code: exception.code,
    source: analyticsSource,
  );

  final code = exception.code;
  final msgLower = (exception.message ?? '').toLowerCase();
  final shaCase =
      code == 'missing-client-identifier' ||
      msgLower.contains('app identifier') ||
      msgLower.contains('play integrity') ||
      msgLower.contains('recaptcha');
  final blockedCase =
      msgLower.contains('blocked') || msgLower.contains('unusual activity');

  late final Widget snackContent;
  if (shaCase) {
    snackContent = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.phoneVerificationFailedTitle,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 6),
        Text(
          l10n.phoneVerificationFailedShaHint,
          style: const TextStyle(fontSize: 13, height: 1.3),
        ),
      ],
    );
  } else if (blockedCase) {
    snackContent = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.phoneVerificationFailedTitle,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 6),
        Text(
          l10n.phoneVerificationFailedBlockedHint,
          style: const TextStyle(fontSize: 13, height: 1.3),
        ),
      ],
    );
  } else {
    final raw = exception.message?.trim();
    final fallback = l10n.locale == AppLocale.id
        ? 'Coba lagi atau periksa koneksi.'
        : 'Try again or check your connection.';
    var line = (raw != null && raw.isNotEmpty) ? raw : fallback;
    if (line.length > 140) line = '${line.substring(0, 140)}…';
    snackContent = Text(line);
  }

  ScaffoldMessenger.of(context).showSnackBar(
    TrakaSnackBar.error(
      context,
      snackContent,
      duration: const Duration(seconds: 5),
    ),
  );
}
