import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../models/user_role.dart';
import '../services/auth_flow_service.dart';
import '../services/device_service.dart';
import '../services/maintenance_service.dart';
import '../services/permission_service.dart';
import '../utils/app_logger.dart';
import '../widgets/app_update_wrapper.dart';
import '../widgets/traka_l10n_scope.dart';
import 'force_update_screen.dart';
import 'login_screen.dart';
import 'maintenance_screen.dart';
import 'permission_required_screen.dart';
import 'splash_screen.dart';
import 'package:permission_handler/permission_handler.dart' as ph;
import '../services/app_update_service.dart';
import '../services/voice_call_incoming_service.dart';

/// Wrapper untuk splash screen + cek auth status.
class SplashScreenWrapper extends StatefulWidget {
  const SplashScreenWrapper({super.key});

  @override
  State<SplashScreenWrapper> createState() => _SplashScreenWrapperState();
}

class _SplashScreenWrapperState extends State<SplashScreenWrapper> {
  @override
  void initState() {
    super.initState();
    // Langsung setelah frame pertama — tanpa jeda tambahan agar transisi ke login/home terasa lebih cepat.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_checkAuthAndRequestPermissions());
    });
  }

  Future<void> _checkAuthAndRequestPermissions() async {
    if (!mounted) return;
    final updateRequired = await AppUpdateService.isUpdateRequired();
    if (updateRequired && mounted) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(builder: (_) => const ForceUpdateScreen()),
      );
      return;
    }
    if (!mounted) return;
    final (maintenanceEnabled, maintenanceMessage) =
        await MaintenanceService.check();
    if (maintenanceEnabled && mounted) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) => MaintenanceScreen(message: maintenanceMessage),
        ),
      );
      return;
    }
    if (!mounted) return;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) => const AppUpdateWrapper(child: LoginScreen()),
        ),
      );
      return;
    }
    final granted = await PermissionService.requestEssentialForHome(context);
    if (!granted) {
      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute<void>(
            builder: (_) => PermissionRequiredScreen(
              onPermissionGranted: (ctx) {
                Navigator.of(ctx).pushReplacement(
                  MaterialPageRoute<void>(
                    builder: (_) => const SplashScreenWrapper(),
                  ),
                );
              },
            ),
          ),
        );
      }
      return;
    }
    if (mounted) _checkAuthAndNavigate();
  }

  Future<void> _checkAuthAndNavigate() async {
    if (!mounted) return;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) => const AppUpdateWrapper(child: LoginScreen()),
        ),
      );
      return;
    }

    try {
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();

      if (!mounted) return;
      if (!userDoc.exists) {
        await FirebaseAuth.instance.signOut();
        if (!mounted) return;
        Navigator.of(context).pushReplacement(
          MaterialPageRoute<void>(
            builder: (_) => const AppUpdateWrapper(child: LoginScreen()),
          ),
        );
        return;
      }

      final data = userDoc.data();
      final role = data?['role'] as String?;
      final suspendedAt = data?['suspendedAt'];
      if (suspendedAt != null) {
        await FirebaseAuth.instance.signOut();
        if (!mounted) return;
        Navigator.of(context).pushReplacement(
          MaterialPageRoute<void>(
            builder: (routeCtx) => Scaffold(
              body: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.block, size: 64, color: Colors.red.shade700),
                      const SizedBox(height: 16),
                      Text(
                        TrakaL10n.of(routeCtx).accountBlocked,
                        style: const TextStyle(
                            fontSize: 20, fontWeight: FontWeight.bold),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        (data?['suspendedReason'] as String?) ??
                            TrakaL10n.of(routeCtx).accountSuspendedMessage,
                        style: const TextStyle(fontSize: 14),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 24),
                      FilledButton(
                        onPressed: () => Navigator.of(routeCtx).pushReplacement(
                          MaterialPageRoute<void>(
                            builder: (_) => const AppUpdateWrapper(
                                child: LoginScreen()),
                          ),
                        ),
                        child: Text(TrakaL10n.of(routeCtx).backToLogin),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
        return;
      }
      final storedDeviceId = data?['deviceId'] as String?;
      final currentDeviceId = await DeviceService.getDeviceId();

      if (await AuthFlowService.hasDeviceConflict(
          user.uid, role, currentDeviceId)) {
        await FirebaseAuth.instance.signOut();
        if (!mounted) return;
        Navigator.of(context).pushReplacement(
          MaterialPageRoute<void>(
            builder: (_) => const AppUpdateWrapper(child: LoginScreen()),
          ),
        );
        return;
      }

      final deviceChanged =
          currentDeviceId != null &&
          currentDeviceId.isNotEmpty &&
          storedDeviceId != null &&
          storedDeviceId.isNotEmpty &&
          currentDeviceId != storedDeviceId;

      if (deviceChanged) {
        await FirebaseAuth.instance.signOut();
        if (!mounted) return;
        Navigator.of(context).pushReplacement(
          MaterialPageRoute<void>(
            builder: (_) => const AppUpdateWrapper(child: LoginScreen()),
          ),
        );
        return;
      }

      final userRole = (role ?? '').toUserRoleOrNull;
      if (userRole == UserRole.penumpang || userRole == UserRole.driver) {
        if (!mounted) return;
        await AuthFlowService.navigateToHome(
          context,
          uid: user.uid,
          role: userRole!.firestoreValue,
          userData: data ?? {},
          skipReverifyCheck: false,
        );
        _requestNotificationInBackground();
      } else {
        VoiceCallIncomingService.stop();
        await FirebaseAuth.instance.signOut();
        if (!mounted) return;
        Navigator.of(context).pushReplacement(
          MaterialPageRoute<void>(
            builder: (_) => const AppUpdateWrapper(child: LoginScreen()),
          ),
        );
      }
    } catch (e, st) {
      logError('SplashScreenWrapper._checkAuthAndNavigate', e, st);
      if (!mounted) return;
      // Jangan signOut pada error jaringan/data — retry dulu, lalu coba cache
      try {
        final success = await _retryOrUseCache(user);
        if (success) return;
      } catch (_) {}
      if (!mounted) return;
      _showConnectionErrorAndRetry();
    }
  }

  /// Retry fetch sekali, lalu coba dari cache. Return true jika berhasil.
  Future<bool> _retryOrUseCache(User user) async {
    // Retry dari server sekali
    try {
      await Future<void>.delayed(const Duration(seconds: 2));
      if (!mounted) return false;
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get(const GetOptions(source: Source.server));
      if (!mounted) return false;
      if (!userDoc.exists) {
        await FirebaseAuth.instance.signOut();
        if (!mounted) return false;
        Navigator.of(context).pushReplacement(
          MaterialPageRoute<void>(
            builder: (_) => const AppUpdateWrapper(child: LoginScreen()),
          ),
        );
        return true;
      }
      await _processUserDocAndNavigate(user, userDoc);
      return true;
    } catch (_) {}
    // Fallback: coba dari cache
    try {
      if (!mounted) return false;
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get(const GetOptions(source: Source.cache));
      if (!mounted) return false;
      if (!userDoc.exists) return false;
      await _processUserDocAndNavigate(user, userDoc);
      return true;
    } catch (_) {}
    return false;
  }

  Future<void> _processUserDocAndNavigate(
    User user,
    DocumentSnapshot<Map<String, dynamic>> userDoc,
  ) async {
    final data = userDoc.data();
    final role = data?['role'] as String?;
    final suspendedAt = data?['suspendedAt'];
    if (suspendedAt != null) {
      await FirebaseAuth.instance.signOut();
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (routeCtx) => Scaffold(
            body: SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.block, size: 64, color: Colors.red.shade700),
                    const SizedBox(height: 16),
                    Text(
                      TrakaL10n.of(routeCtx).accountBlocked,
                      style: const TextStyle(
                          fontSize: 20, fontWeight: FontWeight.bold),
                        textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      (data?['suspendedReason'] as String?) ??
                          TrakaL10n.of(routeCtx).accountSuspendedMessage,
                      style: const TextStyle(fontSize: 14),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 24),
                    FilledButton(
                      onPressed: () => Navigator.of(routeCtx).pushReplacement(
                        MaterialPageRoute<void>(
                          builder: (_) => const AppUpdateWrapper(
                              child: LoginScreen()),
                        ),
                      ),
                      child: Text(TrakaL10n.of(routeCtx).backToLogin),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      return;
    }
    final storedDeviceId = data?['deviceId'] as String?;
    final currentDeviceId = await DeviceService.getDeviceId();
    if (await AuthFlowService.hasDeviceConflict(
        user.uid, role, currentDeviceId)) {
      await FirebaseAuth.instance.signOut();
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) => const AppUpdateWrapper(child: LoginScreen()),
        ),
      );
      return;
    }
    final deviceChanged =
        currentDeviceId != null &&
        currentDeviceId.isNotEmpty &&
        storedDeviceId != null &&
        storedDeviceId.isNotEmpty &&
        currentDeviceId != storedDeviceId;
    if (deviceChanged) {
      await FirebaseAuth.instance.signOut();
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) => const AppUpdateWrapper(child: LoginScreen()),
        ),
      );
      return;
    }
    final userRole = (role ?? '').toUserRoleOrNull;
    if (userRole == UserRole.penumpang || userRole == UserRole.driver) {
      if (!mounted) return;
      await AuthFlowService.navigateToHome(
        context,
        uid: user.uid,
        role: userRole!.firestoreValue,
        userData: data ?? {},
        skipReverifyCheck: false,
      );
      _requestNotificationInBackground();
    } else {
      VoiceCallIncomingService.stop();
      await FirebaseAuth.instance.signOut();
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) => const AppUpdateWrapper(child: LoginScreen()),
        ),
      );
    }
  }

  void _showConnectionErrorAndRetry() {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (routeCtx) {
          final cs = Theme.of(routeCtx).colorScheme;
          final textTheme = Theme.of(routeCtx).textTheme;
          return Scaffold(
            backgroundColor: cs.surface,
            body: SafeArea(
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(22),
                        decoration: BoxDecoration(
                          color: cs.tertiaryContainer,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.signal_wifi_off_rounded,
                          size: 56,
                          color: cs.onTertiaryContainer,
                        ),
                      ),
                      const SizedBox(height: 24),
                      Text(
                        'Gagal memuat data',
                        style: textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: cs.onSurface,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Cek koneksi internet Anda dan coba lagi.',
                        style: textTheme.bodyLarge?.copyWith(
                          color: cs.onSurfaceVariant,
                          height: 1.4,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 28),
                      FilledButton(
                        onPressed: () {
                          Navigator.of(routeCtx).pushReplacement(
                            MaterialPageRoute<void>(
                              builder: (_) => const SplashScreenWrapper(),
                            ),
                          );
                        },
                        child: const Text('Coba Lagi'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  void _requestNotificationInBackground() {
    Future(() async {
      final status = await ph.Permission.notification.status;
      if (!status.isGranted) {
        await ph.Permission.notification.request();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return const SplashScreen();
  }
}
