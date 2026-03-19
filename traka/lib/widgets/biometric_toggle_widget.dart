import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
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
      if (mounted) {
        setState(() {
          _available = available;
          _enabled = enabled;
          _loading = false;
          _isFacePreferred = facePreferred;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _available = false;
          _enabled = false;
          _loading = false;
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
      }
    } catch (_) {
      _isToggling = false;
      if (mounted) setState(() {});
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
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
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
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
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
                      _isFacePreferred ? Icons.face_rounded : Icons.fingerprint_rounded,
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
                          isId ? 'Kunci dengan sidik jari/wajah' : 'Lock with fingerprint/face',
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 15,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          isId
                              ? 'Minta verifikasi saat buka app dari background'
                              : 'Require verification when opening app from background',
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
    );
  }
}
