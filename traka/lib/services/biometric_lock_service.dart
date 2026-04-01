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

  /// Setelah app tidak terlihat ([AppLifecycleState.paused]) lebih lama dari ini,
  /// saat kembali [resumed] wajib verifikasi biometric (jika fitur aktif).
  ///
  /// Di bawah ambang ini: cukup unlock HP — tidak menampilkan overlay lagi
  /// (mengurangi rasa "double unlock" setelah layar kunci singkat).
  static const Duration requireLockAfterBackground = Duration(minutes: 15);

  static final LocalAuthentication _auth = LocalAuthentication();

  /// Waktu terakhir app masuk [paused] (benar-benar ke background).
  static DateTime? _lastPausedAt;

  static bool _isLocked = false;
  static bool get isLocked => _isLocked;

  static final ValueNotifier<bool> lockStateNotifier = ValueNotifier<bool>(false);

  static bool get _isMobile =>
      !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  /// Menit untuk copy teks bantuan di pengaturan (sinkron dengan [requireLockAfterBackground]).
  static int get requireLockAfterMinutes => requireLockAfterBackground.inMinutes;

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
      _lastPausedAt = null;
      _isLocked = false;
      lockStateNotifier.value = false;
    }
  }

  /// Catat masuk background (hanya panggil dari [AppLifecycleState.paused]).
  /// Jangan panggil dari [inactive] agar panel notifikasi singkat tidak menggeser waktu.
  static Future<void> lockIfEnabled() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final enabled = await isEnabled;
    if (!enabled) return;
    _lastPausedAt = DateTime.now();
  }

  /// Dipanggil saat app [resumed]: kunci hanya jika sudah lama di background.
  static void onAppResumed() {
    unawaited(_applyResumePolicy());
  }

  /// @nodoc — kompatibilitas nama lama; gunakan [onAppResumed].
  static void cancelLockIfInGracePeriod() => onAppResumed();

  static Future<void> _applyResumePolicy() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      _lastPausedAt = null;
      return;
    }

    final enabled = await isEnabled;
    if (!enabled) {
      _lastPausedAt = null;
      _isLocked = false;
      lockStateNotifier.value = false;
      return;
    }

    final pausedAt = _lastPausedAt;
    _lastPausedAt = null;

    if (pausedAt == null) {
      // Hanya inactive / tidak lewat paused — jangan ubah state kunci.
      return;
    }

    final elapsed = DateTime.now().difference(pausedAt);
    if (elapsed >= requireLockAfterBackground) {
      _isLocked = true;
      lockStateNotifier.value = true;
    } else {
      _isLocked = false;
      lockStateNotifier.value = false;
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
        persistAcrossBackgrounding: true,
        sensitiveTransaction: true,
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
    _lastPausedAt = null;
    _isLocked = false;
    lockStateNotifier.value = false;
  }

  /// Apakah saat ini terkunci dan perlu unlock.
  static bool get needsUnlock => _isLocked;

  /// Kunci aktif tapi pengguna menonaktifkan semua biometric di HP — matikan kunci agar tidak terkunci permanen.
  /// Return `true` jika preferensi kunci baru saja dimatikan.
  static Future<bool> disableLockIfBiometricsUnavailable() async {
    if (!_isMobile) return false;
    final enabled = await isEnabled;
    if (!enabled) return false;
    final enrolled = await hasEnrolledBiometrics;
    if (enrolled) return false;
    await setEnabled(false);
    forceUnlock();
    return true;
  }
}
