import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'theme_service.dart';

/// Service untuk menyediakan style peta Google Maps sesuai tema aplikasi.
/// Mode gelap: peta gelap agar tidak silau saat perjalanan malam.
/// Auto night: peta gelap otomatis jam 18:00–06:00 (kurangi silau).
class MapStyleService {
  MapStyleService._();

  static String? _darkStyle;
  static String? _lightStyle;
  static Timer? _nightModeTimer;

  /// Load style gelap dari assets (dipanggil sekali, cache).
  static Future<String?> loadDarkStyle() async {
    if (_darkStyle != null) return _darkStyle;
    try {
      _darkStyle = await rootBundle.loadString('assets/map_styles/dark.json');
      return _darkStyle;
    } catch (_) {
      return null;
    }
  }

  /// Load style terang custom (ala Grab) dari assets.
  static Future<String?> loadLightStyle() async {
    if (_lightStyle != null) return _lightStyle;
    try {
      _lightStyle = await rootBundle.loadString('assets/map_styles/light_custom.json');
      return _lightStyle;
    } catch (_) {
      return null;
    }
  }

  /// Cek apakah jam malam (18:00–06:00) untuk auto dark map.
  static bool isNightTime() {
    final hour = DateTime.now().hour;
    return hour >= 18 || hour < 6;
  }

  /// Notifier untuk auto night mode. Di-update setiap menit.
  static final ValueNotifier<bool> isNightTimeNotifier =
      ValueNotifier<bool>(isNightTime());

  /// Mulai timer yang cek jam setiap menit (untuk auto night).
  static void startNightModeTimer() {
    _nightModeTimer?.cancel();
    _nightModeTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      final now = isNightTime();
      if (isNightTimeNotifier.value != now) {
        isNightTimeNotifier.value = now;
      }
    });
  }

  /// Style untuk map: mengikuti tema aplikasi saja (bukan setingan HP/jam).
  static String? getStyleForMap(ThemeMode themeMode, bool useDark) {
    if (useDark) return _darkStyle;
    return _lightStyle;
  }

  /// Notifier tema untuk rebuild map saat user ganti tema.
  static ValueNotifier<ThemeMode> get themeNotifier =>
      ThemeService.themeModeNotifier;

  /// Zoom default beranda (driver/penumpang).
  static const double defaultZoom = 15.0;
  /// Zoom saat tracking (lebih dekat).
  static const double trackingZoom = 16.0;
  /// Zoom Cari Travel (area luas, banyak driver).
  static const double searchZoom = 11.0;
  /// Tilt awal untuk efek 3D gedung (35° = gedung tampil 3D, tidak terlalu curam).
  static const double defaultTilt = 35.0;
}
