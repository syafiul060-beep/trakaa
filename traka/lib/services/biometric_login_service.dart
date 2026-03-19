import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show HapticFeedback, PlatformException;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/error_codes.dart' as auth_error;
import 'package:local_auth/local_auth.dart';

/// Layanan login dengan sidik jari/wajah.
/// Hanya untuk akun email+password (bukan OTP).
class BiometricLoginService {
  BiometricLoginService._();

  static const _keyEmail = 'biometric_login_email';
  static const _keyPassword = 'biometric_login_password';

  static final _auth = LocalAuthentication();
  static final _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  static bool get _isMobile =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  /// Apakah ada kredensial tersimpan untuk login biometric.
  static Future<bool> hasStoredCredentials() async {
    if (!_isMobile) return false;
    try {
      final email = await _storage.read(key: _keyEmail);
      return email != null && email.isNotEmpty;
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

  /// Apakah device mendukung biometric untuk login.
  static Future<bool> get canUseBiometricLogin async {
    if (!_isMobile) return false;
    try {
      return await _auth.canCheckBiometrics &&
          (await _auth.getAvailableBiometrics()).isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  /// Simpan kredensial untuk login biometric (hanya email+password).
  static Future<void> saveCredentials({
    required String email,
    required String password,
  }) async {
    if (!_isMobile) return;
    try {
      await _storage.write(key: _keyEmail, value: email.trim().toLowerCase());
      await _storage.write(key: _keyPassword, value: password);
    } catch (e) {
      debugPrint('BiometricLoginService.saveCredentials: $e');
    }
  }

  /// Hapus kredensial tersimpan (saat logout).
  static Future<void> clearCredentials() async {
    try {
      await _storage.delete(key: _keyEmail);
      await _storage.delete(key: _keyPassword);
    } catch (_) {}
  }

  /// Login dengan biometric. Return (success, errorMessage).
  /// errorMessage null = user batal; non-null = pesan error spesifik.
  static Future<(bool success, String? error)> loginWithBiometric({
    required String reason,
    required bool isId,
  }) async {
    if (!_isMobile) {
      return (false, isId ? 'Biometric tidak tersedia' : 'Biometric not available');
    }
    try {
      final ok = await _auth.authenticate(
        localizedReason: reason,
        options: const AuthenticationOptions(
          stickyAuth: true,
          useErrorDialogs: false,
        ),
      );
      if (!ok) return (false, null);

      HapticFeedback.mediumImpact();
      final email = await _storage.read(key: _keyEmail);
      final password = await _storage.read(key: _keyPassword);
      if (email == null || password == null || email.isEmpty || password.isEmpty) {
        await clearCredentials();
        return (false, isId ? 'Kredensial tidak ditemukan' : 'Credentials not found');
      }

      final cred = await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
      return (cred.user != null, null);
    } on PlatformException catch (e) {
      final msg = _biometricErrorToMessage(e.code, isId);
      return (false, msg);
    } on FirebaseAuthException catch (e) {
      return (false, e.message ?? e.code);
    } catch (e) {
      debugPrint('BiometricLoginService.loginWithBiometric: $e');
      return (false, isId ? 'Terjadi kesalahan. Coba lagi.' : 'Something went wrong. Try again.');
    }
  }

  static String _biometricErrorToMessage(String code, bool isId) {
    switch (code) {
      case auth_error.notEnrolled:
        return isId
            ? 'Sidik jari/wajah belum didaftarkan. Aktifkan di Pengaturan HP.'
            : 'Fingerprint/face not enrolled. Enable in device settings.';
      case auth_error.notAvailable:
        return isId
            ? 'Biometric tidak tersedia di perangkat ini'
            : 'Biometric not available on this device';
      case auth_error.lockedOut:
        return isId
            ? 'Terlalu banyak percobaan. Coba lagi nanti.'
            : 'Too many attempts. Try again later.';
      case auth_error.permanentlyLockedOut:
        return isId
            ? 'Biometric terkunci. Gunakan PIN/pattern HP untuk membuka.'
            : 'Biometric locked. Use device PIN/pattern to unlock.';
      case auth_error.passcodeNotSet:
        return isId
            ? 'Atur PIN/pattern HP terlebih dahulu'
            : 'Set device PIN/pattern first';
      default:
        return isId ? 'Verifikasi gagal. Coba lagi.' : 'Verification failed. Try again.';
    }
  }
}
