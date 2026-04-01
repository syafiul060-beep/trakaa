import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n/app_localizations.dart';
import '../screens/login_screen.dart';
import '../services/auth_redirect_state.dart';
import '../services/biometric_lock_service.dart';
import '../services/locale_service.dart';
import '../widgets/app_update_wrapper.dart';
import '../theme/app_interaction_styles.dart';

/// Overlay kunci biometric — tampil saat app resume dari background dan user punya kunci aktif.
class BiometricLockOverlay extends StatefulWidget {
  const BiometricLockOverlay({super.key});

  @override
  State<BiometricLockOverlay> createState() => _BiometricLockOverlayState();
}

class _BiometricLockOverlayState extends State<BiometricLockOverlay> {
  bool _isAuthenticating = false;
  int _failedAttempts = 0;
  static const _maxAttemptsBeforeFallback = 3;

  Future<void> _unlock() async {
    if (_isAuthenticating) return;
    setState(() => _isAuthenticating = true);
    final l10n = AppLocalizations(locale: LocaleService.current);
    final isId = l10n.locale == AppLocale.id;
    final reason = isId
        ? 'Buka kunci Traka dengan sidik jari atau wajah'
        : 'Unlock Traka with fingerprint or face';
    final success = await BiometricLockService.unlock(reason: reason);
    if (mounted) {
      setState(() {
        _isAuthenticating = false;
        if (!success) _failedAttempts++;
      });
      if (success) {
        HapticFeedback.mediumImpact();
        _failedAttempts = 0;
      } else if (BiometricLockService.needsUnlock) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              isId ? 'Verifikasi gagal. Coba lagi.' : 'Verification failed. Try again.',
            ),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _loginWithEmail() async {
    await FirebaseAuth.instance.signOut();
    BiometricLockService.forceUnlock();
    AuthRedirectState.setOnLoginScreen(true);
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute<void>(
        builder: (_) => const AppUpdateWrapper(child: LoginScreen()),
      ),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations(locale: LocaleService.current);
    final isId = l10n.locale == AppLocale.id;
    final showFallback = _failedAttempts >= _maxAttemptsBeforeFallback;

    return ValueListenableBuilder<bool>(
      valueListenable: BiometricLockService.lockStateNotifier,
      builder: (context, isLocked, _) {
        if (!isLocked) return const SizedBox.shrink();

        final colorScheme = Theme.of(context).colorScheme;
        final primary = colorScheme.primary;
        return FutureBuilder<bool>(
          future: BiometricLockService.isFacePreferred,
          builder: (context, faceSnap) {
            final isFace = faceSnap.data ?? false;
            return Material(
              color: colorScheme.surface,
              child: SafeArea(
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(28),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                primary.withValues(alpha: 0.2),
                                primary.withValues(alpha: 0.08),
                              ],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: primary.withValues(alpha: 0.12),
                                blurRadius: 24,
                                offset: const Offset(0, 8),
                              ),
                            ],
                          ),
                          child: Icon(
                            isFace ? Icons.face_rounded : Icons.fingerprint_rounded,
                            size: 72,
                            color: primary,
                          ),
                        ),
                    const SizedBox(height: 32),
                    Text(
                      isId ? 'Aplikasi terkunci' : 'App locked',
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.3,
                          ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      isId
                          ? 'Gunakan sidik jari atau wajah untuk membuka'
                          : 'Use fingerprint or face to unlock',
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                            height: 1.4,
                          ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 40),
                    FilledButton.icon(
                      onPressed: _isAuthenticating ? null : _unlock,
                      style: AppInteractionStyles.filledFromTheme(
                        context,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 28,
                          vertical: 16,
                        ),
                      ),
                      icon: _isAuthenticating
                          ? SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.5,
                                color: colorScheme.onPrimary,
                              ),
                            )
                          : Icon(
                              isFace ? Icons.face_rounded : Icons.fingerprint_rounded,
                              size: 24,
                              color: colorScheme.onPrimary,
                            ),
                      label: Text(
                        _isAuthenticating
                            ? (isId ? 'Memverifikasi...' : 'Verifying...')
                            : (isId ? 'Buka dengan sidik jari' : 'Unlock with fingerprint'),
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                        if (showFallback) ...[
                          const SizedBox(height: 20),
                          TextButton.icon(
                            onPressed: _loginWithEmail,
                            icon: const Icon(Icons.login_rounded, size: 20),
                            label: Text(
                              isId ? 'Login dengan email' : 'Login with email',
                              style: const TextStyle(fontWeight: FontWeight.w500),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}
