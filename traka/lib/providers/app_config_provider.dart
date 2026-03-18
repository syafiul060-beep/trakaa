import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../config/app_constants.dart';

/// Provider untuk app config (tarif per km, dll) dari Firestore.
class AppConfigProvider extends ChangeNotifier {
  int _tarifPerKm = AppConstants.defaultTarifPerKm;
  bool _loaded = false;

  int get tarifPerKm => _tarifPerKm;
  bool get isLoaded => _loaded;

  /// Load config dari Firestore. Panggil saat user login.
  Future<void> load() async {
    if (_loaded) return;
    try {
      final doc = await FirebaseFirestore.instance
          .collection('app_config')
          .doc('settings')
          .get();
      if (doc.exists && doc.data() != null) {
        final val = doc.data()!['tarifPerKm'];
        if (val is num) {
          _tarifPerKm = val.toInt();
        }
      }
      _loaded = true;
      notifyListeners();
    } catch (e, st) {
      if (kDebugMode) debugPrint('AppConfigProvider.load: $e\n$st');
    }
  }

  /// Reset saat logout.
  void reset() {
    _tarifPerKm = AppConstants.defaultTarifPerKm;
    _loaded = false;
    notifyListeners();
  }
}
