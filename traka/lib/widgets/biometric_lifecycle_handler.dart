import 'package:flutter/material.dart';

import '../services/biometric_lock_service.dart';

/// Mendengarkan lifecycle app: saat ke background, kunci jika biometric aktif.
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
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      BiometricLockService.lockIfEnabled();
    } else if (state == AppLifecycleState.resumed) {
      // User kembali ke app — batalkan lock jika masih dalam grace period.
      // HP baru dibuka kunci → tidak perlu minta sidik jari lagi.
      BiometricLockService.cancelLockIfInGracePeriod();
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
