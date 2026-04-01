import 'dart:async' show unawaited;

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;

import '../l10n/app_localizations.dart';
import '../services/biometric_login_service.dart';
import '../services/biometric_lock_service.dart';
import '../services/locale_service.dart';

/// Toggle "Kunci dengan sidik jari/wajah" di Pengaturan.
/// Hanya tampil jika device mendukung biometric.
class BiometricToggleWidget extends StatefulWidget {
  const BiometricToggleWidget({super.key});

  @override
  State<BiometricToggleWidget> createState() => _BiometricToggleWidgetState();
}

class _BiometricToggleWidgetState extends State<BiometricToggleWidget> {
  bool _available = false;
  bool _enabled = false;
  bool _loading = true;
  bool _isToggling = false;
  bool _isFacePreferred = false;
  bool _hasQuickLoginCred = false;
  bool _canBioLoginScreen = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final available = await BiometricLockService.hasEnrolledBiometrics;
      final enabled = await BiometricLockService.isEnabled;
      final facePreferred = await BiometricLockService.isFacePreferred;
      final hasCred = await BiometricLoginService.hasStoredCredentials();
      final canBio = await BiometricLoginService.canUseBiometricLogin;
      if (mounted) {
        setState(() {
          _available = available;
          _enabled = enabled;
          _loading = false;
          _isFacePreferred = facePreferred;
          _hasQuickLoginCred = hasCred;
          _canBioLoginScreen = canBio;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _available = false;
          _enabled = false;
          _loading = false;
          _hasQuickLoginCred = false;
          _canBioLoginScreen = false;
        });
      }
    }
  }

  Future<void> _onChanged(bool value) async {
    if (!_available || _isToggling) return;
    _isToggling = true;
    if (mounted) setState(() {});

    try {
      if (value) {
        // Verifikasi dulu sebelum aktifkan — tunda agar dialog biometric tampil
        await Future<void>.delayed(const Duration(milliseconds: 150));
        if (!mounted) return;
        final l10n = AppLocalizations(locale: LocaleService.current);
        final reason = l10n.locale == AppLocale.id
            ? 'Verifikasi sidik jari/wajah untuk mengaktifkan kunci'
            : 'Verify fingerprint/face to enable lock';
        final ok = await BiometricLockService.unlock(reason: reason);
        if (!mounted) return;
        if (!ok) {
          _isToggling = false;
          if (mounted) setState(() {});
          return;
        }
      }

      await BiometricLockService.setEnabled(value);
      if (mounted) {
        setState(() {
          _enabled = value;
          _isToggling = false;
        });
        if (value) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            unawaited(_offerBiometricQuickLoginIfNeeded(context));
          });
        }
      }
    } catch (_) {
      _isToggling = false;
      if (mounted) setState(() {});
    }
  }

  /// Kunci app ≠ login cepat di layar masuk. Setelah kunci aktif, tawarkan simpan sandi
  /// (setelah verifikasi) agar tombol sidik jari/wajah muncul setelah logout.
  Future<void> _offerBiometricQuickLoginIfNeeded(BuildContext context) async {
    final l10n = AppLocalizations(locale: LocaleService.current);
    final isId = l10n.locale == AppLocale.id;

    if (await BiometricLoginService.hasStoredCredentials()) return;
    if (!await BiometricLoginService.canUseBiometricLogin) return;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final email = user.email?.trim();
    if (email == null || email.isEmpty) return;

    final hasPassword =
        user.providerData.any((p) => p.providerId == 'password');
    if (!hasPassword) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text(
            isId
                ? 'Login cepat dengan sidik jari hanya untuk akun email dan sandi.'
                : 'Biometric sign-in is only for email & password accounts.',
          ),
        ),
      );
      return;
    }

    if (!context.mounted) return;

    final passwordController = TextEditingController();
    String? err;

    final saved = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setLocal) {
            return AlertDialog(
              title: Text(
                isId ? 'Login cepat di halaman masuk?' : 'Quick sign-in on login screen?',
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      isId
                          ? 'Kunci aplikasi sudah aktif. Beda dengan itu: agar setelah logout Anda bisa masuk lagi dengan sidik jari/wajah di halaman login, sandi perlu disimpan sekali di HP ini (tersimpan aman, hanya untuk login cepat).'
                          : 'App lock is on. To also sign in with biometrics on the login screen after logout, save your password once on this device (stored securely for quick sign-in only).',
                    ),
                    const SizedBox(height: 12),
                    SelectableText(
                      email,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: passwordController,
                      obscureText: true,
                      decoration: InputDecoration(
                        labelText: isId ? 'Sandi akun' : 'Password',
                        errorText: err,
                      ),
                      onChanged: (_) => setLocal(() => err = null),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: Text(isId ? 'Lewati' : 'Skip'),
                ),
                FilledButton(
                  onPressed: () {
                    if (passwordController.text.isEmpty) {
                      setLocal(() {
                        err = isId ? 'Sandi wajib diisi' : 'Password required';
                      });
                      return;
                    }
                    Navigator.pop(ctx, true);
                  },
                  child: Text(isId ? 'Simpan' : 'Save'),
                ),
              ],
            );
          },
        );
      },
    );

    final password = passwordController.text.trim();
    passwordController.dispose();

    if (saved != true || password.isEmpty) return;

    try {
      final cred =
          EmailAuthProvider.credential(email: email, password: password);
      await user.reauthenticateWithCredential(cred);
      await BiometricLoginService.saveCredentials(
        email: email.toLowerCase(),
        password: password,
      );
      if (mounted) {
        setState(() => _hasQuickLoginCred = true);
      }
      if (!context.mounted) return;
      HapticFeedback.mediumImpact();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text(
            isId
                ? 'Login sidik jari/wajah di halaman masuk aktif.'
                : 'Biometric sign-in on the login screen is enabled.',
          ),
        ),
      );
    } on FirebaseAuthException catch (e) {
      if (!context.mounted) return;
      final wrong = e.code == 'wrong-password' ||
          e.code == 'invalid-credential' ||
          e.code == 'user-mismatch';
      final msg = wrong
          ? (isId ? 'Sandi salah.' : 'Wrong password.')
          : (e.message ??
              (isId ? 'Gagal menyimpan. Coba lagi.' : 'Could not save. Try again.'));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
          content: Text(msg),
        ),
      );
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
          content: Text(
            isId ? 'Terjadi kesalahan. Coba lagi.' : 'Something went wrong. Try again.',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations(locale: LocaleService.current);
    final isId = l10n.locale == AppLocale.id;

    if (_loading) {
      final colorScheme = Theme.of(context).colorScheme;
      return Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        decoration: BoxDecoration(
          color: colorScheme.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: colorScheme.outline.withValues(alpha: 0.4),
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: colorScheme.primary.withValues(alpha: 0.04),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: colorScheme.primary.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(
              _isFacePreferred ? Icons.face_rounded : Icons.fingerprint_rounded,
              color: colorScheme.primary,
              size: 24,
            ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                isId ? 'Kunci dengan sidik jari' : 'Lock with fingerprint',
                style: TextStyle(
                  fontWeight: FontWeight.w500,
                  color: colorScheme.onSurface,
                ),
              ),
            ),
            const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ],
        ),
      );
    }

    if (!_available) {
      return Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Text(
          isId
              ? 'Sidik jari/wajah tidak tersedia. Aktifkan di Pengaturan HP terlebih dahulu.'
              : 'Fingerprint/face not available. Enable in device settings first.',
          style: TextStyle(
            fontSize: 14,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }

    final colorScheme = Theme.of(context).colorScheme;
    final primary = colorScheme.primary;
    final showQuickLoginLink = _canBioLoginScreen &&
        _enabled &&
        !_hasQuickLoginCred &&
        FirebaseAuth.instance.currentUser != null &&
        FirebaseAuth.instance.currentUser!.providerData
            .any((p) => p.providerId == 'password');

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            decoration: BoxDecoration(
              color: colorScheme.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: primary.withValues(alpha: 0.25),
                width: 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: primary.withValues(alpha: 0.06),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: _isToggling ? null : () => _onChanged(!_enabled),
                borderRadius: BorderRadius.circular(16),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              primary.withValues(alpha: 0.2),
                              primary.withValues(alpha: 0.1),
                            ],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          _isFacePreferred
                              ? Icons.face_rounded
                              : Icons.fingerprint_rounded,
                          color: primary,
                          size: 26,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              isId
                                  ? 'Kunci dengan sidik jari/wajah'
                                  : 'Lock with fingerprint/face',
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 15,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              isId
                                  ? 'Hanya mengunci app setelah ditinggal ±${BiometricLockService.requireLockAfterMinutes} menit. Untuk login dengan sidik jari setelah logout, aktifkan lewat dialog atau centang di halaman login. Hanya untuk akun email+sandi.'
                                  : 'Locks the app after ~${BiometricLockService.requireLockAfterMinutes} min away. For biometric sign-in after logout, use the dialog when enabling or the checkbox on login. Email & password accounts only.',
                              style: TextStyle(
                                fontSize: 12,
                                color: colorScheme.onSurfaceVariant,
                                height: 1.3,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Switch(
                        value: _enabled,
                        onChanged: _isToggling ? null : _onChanged,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          if (showQuickLoginLink) ...[
            const SizedBox(height: 6),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () =>
                    unawaited(_offerBiometricQuickLoginIfNeeded(context)),
                icon: Icon(Icons.login_rounded, size: 20, color: primary),
                label: Text(
                  isId
                      ? 'Aktifkan login sidik jari/wajah di halaman masuk'
                      : 'Enable biometric sign-in on login screen',
                  style: TextStyle(color: primary, fontWeight: FontWeight.w500),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
