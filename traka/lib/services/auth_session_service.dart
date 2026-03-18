import 'package:firebase_auth/firebase_auth.dart';

/// Layanan untuk menjaga sesi auth tetap valid (refresh token dengan retry).
class AuthSessionService {
  AuthSessionService._();

  static const _maxRetries = 3;
  static const _retryDelay = Duration(seconds: 2);

  /// Refresh token dengan retry. Return true jika berhasil, false jika gagal setelah retry.
  /// Dipanggil saat app resume atau sebelum aksi penting.
  static Future<bool> refreshTokenIfNeeded() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return false;

    for (int attempt = 0; attempt < _maxRetries; attempt++) {
      try {
        await user.getIdToken(true);
        return true;
      } catch (_) {
        if (attempt < _maxRetries - 1) {
          await Future.delayed(_retryDelay);
        }
      }
    }
    return false;
  }

  /// Refresh token di background (fire-and-forget). Untuk onResume, tidak blok UI.
  static void refreshTokenSilently() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    Future(() async {
      for (int attempt = 0; attempt < _maxRetries; attempt++) {
        try {
          await user.getIdToken(true);
          return;
        } catch (_) {
          if (attempt < _maxRetries - 1) {
            await Future.delayed(_retryDelay);
          }
        }
      }
    });
  }
}
