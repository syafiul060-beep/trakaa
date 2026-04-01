import 'dart:async' show unawaited;

import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../services/biometric_lock_service.dart';
import '../services/locale_service.dart';

/// Mendengarkan lifecycle app: catat waktu saat [paused]; saat [resumed] kunci
/// hanya jika sudah lama di background (lihat [BiometricLockService.requireLockAfterBackground]).
class BiometricLifecycleHandler extends StatefulWidget {
  const BiometricLifecycleHandler({
    super.key,
    required this.child,
  });

  final Widget child;

  @override
  State<BiometricLifecycleHandler> createState() =>
      _BiometricLifecycleHandlerState();
}

class _BiometricLifecycleHandlerState extends State<BiometricLifecycleHandler>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Hanya [paused]: app benar-benar tidak terlihat (bukan [inactive] seperti
    // panel notifikasi), agar waktu background akurat dan tidak "reset" terus.
    if (state == AppLifecycleState.paused) {
      BiometricLockService.lockIfEnabled();
    } else if (state == AppLifecycleState.resumed) {
      BiometricLockService.onAppResumed();
      unawaited(_disableLockIfNoEnrollment(context));
    }
  }

  Future<void> _disableLockIfNoEnrollment(BuildContext context) async {
    final off = await BiometricLockService.disableLockIfBiometricsUnavailable();
    if (!off || !context.mounted) return;
    final l10n = AppLocalizations(locale: LocaleService.current);
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        content: Text(l10n.biometricLockDisabledNoEnrollment),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
