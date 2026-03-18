import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart' as ph;

import '../services/permission_service.dart';
import '../widgets/app_update_wrapper.dart';
import 'login_screen.dart';

/// Layar ditampilkan ketika user sudah login tapi menolak izin lokasi/device ID.
/// User bisa buka pengaturan, coba lagi, atau keluar.
class PermissionRequiredScreen extends StatefulWidget {
  /// Callback saat permission berhasil diberikan. Diberi [BuildContext] untuk navigasi.
  final void Function(BuildContext context)? onPermissionGranted;

  const PermissionRequiredScreen({
    super.key,
    this.onPermissionGranted,
  });

  @override
  State<PermissionRequiredScreen> createState() =>
      _PermissionRequiredScreenState();
}

class _PermissionRequiredScreenState extends State<PermissionRequiredScreen>
    with WidgetsBindingObserver {
  bool _isRetrying = false;

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
    if (state == AppLifecycleState.resumed && mounted) {
      _retryPermissionCheck();
    }
  }

  Future<void> _retryPermissionCheck() async {
    if (_isRetrying || !mounted) return;
    setState(() => _isRetrying = true);
    final locationGranted =
        await PermissionService.requestLocationPermission(context);
    final phoneStateGranted =
        await PermissionService.requestPhoneStatePermission(context);
    if (mounted) setState(() => _isRetrying = false);
    if (!mounted) return;
    if (locationGranted && phoneStateGranted) {
      widget.onPermissionGranted?.call(context);
    }
  }

  Future<void> _openSettings() async {
    await ph.openAppSettings();
  }

  Future<void> _logoutAndGoToLogin() async {
    await FirebaseAuth.instance.signOut();
    if (!mounted) return;
    Navigator.of(context, rootNavigator: true).pushAndRemoveUntil(
      MaterialPageRoute<void>(builder: (_) => const AppUpdateWrapper(child: LoginScreen())),
      (route) => false,
    );
  }

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
                Icons.location_off_outlined,
                size: 64,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(height: 24),
              Text(
                'Izin Diperlukan',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              Text(
                'Aplikasi Traka memerlukan izin lokasi dan device ID untuk berfungsi.\n\n'
                '• Lokasi: untuk peta dan menemukan driver\n'
                '• Device ID: untuk keamanan akun',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),
              if (_isRetrying)
                const Padding(
                  padding: EdgeInsets.only(bottom: 16),
                  child: SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              else ...[
                FilledButton.icon(
                  onPressed: _retryPermissionCheck,
                  icon: const Icon(Icons.refresh, size: 20),
                  label: const Text('Coba Lagi'),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(48),
                  ),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: _openSettings,
                  icon: const Icon(Icons.settings, size: 20),
                  label: const Text('Buka Pengaturan'),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(48),
                  ),
                ),
                const SizedBox(height: 12),
                TextButton.icon(
                  onPressed: _logoutAndGoToLogin,
                  icon: const Icon(Icons.logout, size: 20),
                  label: const Text('Keluar'),
                  style: TextButton.styleFrom(
                    minimumSize: const Size.fromHeight(48),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
