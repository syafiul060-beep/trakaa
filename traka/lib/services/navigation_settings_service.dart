import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Preferensi navigasi driver (hemat data, dll.).
class NavigationSettingsService {
  NavigationSettingsService._();

  static const _prefKeyDataSaver = 'traka_nav_data_saver';

  static final ValueNotifier<bool> dataSaverNotifier = ValueNotifier<bool>(false);

  static Future<void> init() async {
    final p = await SharedPreferences.getInstance();
    dataSaverNotifier.value = p.getBool(_prefKeyDataSaver) ?? false;
  }

  static Future<void> setDataSaverEnabled(bool value) async {
    dataSaverNotifier.value = value;
    final p = await SharedPreferences.getInstance();
    await p.setBool(_prefKeyDataSaver, value);
  }

  static bool get dataSaverEnabled => dataSaverNotifier.value;
}
