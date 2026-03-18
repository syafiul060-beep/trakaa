import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'low_ram_warning_service.dart';

const _prefKey = 'lite_mode_enabled';
const _prefKeyUserDisabled = 'lite_mode_user_disabled';

/// Mode lite: optimasi untuk HP RAM < 3 GB.
/// Mengurangi cache, animasi, dan beban memori.
class LiteModeService {
  static bool _isLiteMode = false;
  static bool _initialized = false;

  static final ValueNotifier<bool> liteModeNotifier = ValueNotifier<bool>(false);

  /// Init: baca preferensi dan deteksi RAM. Panggil sebelum Firestore init.
  static Future<void> init() async {
    if (_initialized) return;
    final prefs = await SharedPreferences.getInstance();
    final userDisabled = prefs.getBool(_prefKeyUserDisabled) ?? false;

    if (prefs.containsKey(_prefKey)) {
      _isLiteMode = prefs.getBool(_prefKey) ?? false;
    } else {
      // Auto-detect: RAM < 3 GB
      final ramMb = await LowRamWarningService.getDeviceRamMb();
      _isLiteMode = !userDisabled && (ramMb != null && ramMb < 3072);
      await prefs.setBool(_prefKey, _isLiteMode);
    }

    liteModeNotifier.value = _isLiteMode;
    _initialized = true;
  }

  static bool get isLiteMode => _isLiteMode;

  /// Ukuran cache Firestore (bytes). Mode lite: 50 MB, standar: 100 MB.
  static int get firestoreCacheSizeBytes =>
      _isLiteMode ? 50 * 1024 * 1024 : 100 * 1024 * 1024;

  /// Aktifkan/nonaktifkan mode lite. Efek penuh setelah restart.
  static Future<void> setLiteMode(bool enabled) async {
    _isLiteMode = enabled;
    liteModeNotifier.value = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefKey, enabled);
    if (enabled) await prefs.setBool(_prefKeyUserDisabled, false);
  }

  /// User menolak saran mode lite (jangan auto-enable lagi).
  static Future<void> setUserDisabledLiteMode() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefKeyUserDisabled, true);
  }
}
