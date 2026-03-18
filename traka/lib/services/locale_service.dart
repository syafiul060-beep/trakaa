import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../l10n/app_localizations.dart';

/// Service untuk menyimpan preferensi bahasa (Indonesia/English) app-wide.
/// Mirip ThemeService — digunakan di MaterialApp dan seluruh layar.
/// appLocale juga disinkronkan ke users/{uid} untuk indikator turis ke driver.
class LocaleService {
  LocaleService._();

  static const _keyLocale = 'pref_app_locale';

  static AppLocale _current = AppLocale.id;
  static final ValueNotifier<AppLocale> localeNotifier =
      ValueNotifier<AppLocale>(_current);

  static AppLocale get current => _current;

  /// Locale untuk MaterialApp.
  static Locale get materialLocale =>
      _current == AppLocale.id ? const Locale('id', 'ID') : const Locale('en');

  /// Inisialisasi: baca preferensi dari SharedPreferences.
  static Future<void> init() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(_keyLocale);
      if (saved == 'en') {
        _current = AppLocale.en;
        localeNotifier.value = AppLocale.en;
      }
    } catch (_) {
      _current = AppLocale.id;
    }
  }

  /// Set bahasa dan simpan ke SharedPreferences.
  /// Juga sinkron ke Firestore users/{uid} agar driver tahu bahasa penumpang (turis = EN).
  static Future<void> setLocale(AppLocale locale) async {
    if (_current == locale) return;
    _current = locale;
    localeNotifier.value = locale;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_keyLocale, locale == AppLocale.id ? 'id' : 'en');
      await _syncAppLocaleToFirestore(locale);
    } catch (_) {}
  }

  /// Sinkron appLocale ke users/{uid} untuk indikator turis (driver tahu penumpang berbahasa Inggris).
  static Future<void> _syncAppLocaleToFirestore(AppLocale locale) async {
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) return;
      await FirebaseFirestore.instance.collection('users').doc(uid).update({
        'appLocale': locale == AppLocale.id ? 'id' : 'en',
      });
    } catch (_) {}
  }
}
