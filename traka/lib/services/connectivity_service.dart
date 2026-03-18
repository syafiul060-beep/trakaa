import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

/// Status koneksi jaringan. Listen untuk tampilkan banner offline.
class ConnectivityService {
  static final ValueNotifier<bool> isOnlineNotifier = ValueNotifier<bool>(true);
  static StreamSubscription<List<ConnectivityResult>>? _subscription;

  /// Mulai listen perubahan koneksi. Panggil setelah app ready.
  static void startListening() {
    _subscription?.cancel();
    _subscription = Connectivity().onConnectivityChanged.listen(_onConnectivityChanged);
    Connectivity().checkConnectivity().then(_onConnectivityChanged);
  }

  static void _onConnectivityChanged(List<ConnectivityResult> results) {
    final online = results.isNotEmpty &&
        results.any((r) =>
            r != ConnectivityResult.none &&
            r != ConnectivityResult.bluetooth);
    if (isOnlineNotifier.value != online) {
      isOnlineNotifier.value = online;
    }
  }

  static void stopListening() {
    _subscription?.cancel();
    _subscription = null;
  }
}
