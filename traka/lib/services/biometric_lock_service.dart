import 'dart:async';
import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Layanan kunci aplikasi dengan sidik jari/wajah (biometric).
/// Preference disimpan lokal per device — saat ganti HP, user login ulang dan bisa aktifkan lagi di Pengaturan.
class BiometricLockService {
  BiometricLockService._();

  static const _keyEnabled = 'biometric_lock_enabled';

  /// Grace period: jika user kembali ke app dalam waktu ini, tidak perlu verifikasi lagi.
  /// Mis. HP baru dibuka kunci → buka app → tidak ribet minta sidik jari lagi.
  static const Duration lockGracePeriod = Duration(seconds: 20);

  static final LocalAuthentication _auth = LocalAuthentication();
  static Timer? _lockDelayTimer;

  static bool _isLocked = false;
  static bool get isLocked => _isLocked;

  static final ValueNotifier<bool> lockStateNotifier = ValueNotifier<bool>(false);

  static bool get _isMobile =>
      !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  /// Apakah device mendukung biometric (fingerprint/face).
  static Future<bool> get canUseBiometric async {
    if (!_isMobile) return false;
    try {
      return await _auth.canCheckBiometrics;
    } catch (_) {
      return false;
    }
  }

  /// True jika device punya Face ID/Face Unlock (prioritas tampil ikon wajah).
  static Future<bool> get isFacePreferred async {
    if (!_isMobile) return false;
    try {
      final list = await _auth.getAvailableBiometrics();
      return list.contains(BiometricType.face);
    } catch (_) {
      return false;
    }
  }

  /// Apakah ada biometric terdaftar di device (user sudah setup fingerprint/face di HP).
  static Future<bool> get hasEnrolledBiometrics async {
    if (!_isMobile) return false;
    try {
      return await _auth.canCheckBiometrics &&
          (await _auth.getAvailableBiometrics()).isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  /// Cek apakah user sudah mengaktifkan kunci biometric (preference lokal).
  static Future<bool> get isEnabled async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyEnabled) ?? false;
  }

  /// Aktifkan/nonaktifkan kunci biometric.
  static Future<void> setEnabled(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyEnabled, value);
    if (!value) {
      _lockDelayTimer?.cancel();
      _lockDelayTimer = null;
      _isLocked = false;
      lockStateNotifier.value = false;
    }
  }

  /// Kunci app (dipanggil saat app ke background).
  /// Tidak langsung kunci — gunakan grace period: jika user kembali dalam lockGracePeriod,
  /// tidak perlu verifikasi (HP baru dibuka kunci = sudah cukup).
  static Future<void> lockIfEnabled() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final enabled = await isEnabled;
    if (!enabled) return;

    _lockDelayTimer?.cancel();
    _lockDelayTimer = Timer(lockGracePeriod, () {
      _lockDelayTimer = null;
      _isLocked = true;
      lockStateNotifier.value = true;
    });
  }

  /// Batalkan lock yang akan datang (dipanggil saat app resume dalam grace period).
  static void cancelLockIfInGracePeriod() {
    if (_lockDelayTimer != null) {
      _lockDelayTimer!.cancel();
      _lockDelayTimer = null;
    }
  }

  /// Buka kunci dengan biometric. Return true jika berhasil.
  static Future<bool> unlock({required String reason}) async {
    if (!_isMobile) {
      _isLocked = false;
      lockStateNotifier.value = false;
      return true;
    }
    try {
      final success = await _auth.authenticate(
        localizedReason: reason,
        options: const AuthenticationOptions(
          stickyAuth: true,
          useErrorDialogs: true,
        ),
      );
      if (success) {
        _isLocked = false;
        lockStateNotifier.value = false;
      }
      return success;
    } catch (e) {
      debugPrint('BiometricLockService.unlock: $e');
      return false;
    }
  }

  /// Paksa unlock (mis. user logout).
  static void forceUnlock() {
    _lockDelayTimer?.cancel();
    _lockDelayTimer = null;
    _isLocked = false;
    lockStateNotifier.value = false;
  }

  /// Apakah saat ini terkunci dan perlu unlock.
  static bool get needsUnlock => _isLocked;
}
