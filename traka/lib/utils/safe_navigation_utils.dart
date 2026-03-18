import 'dart:async';

import 'package:flutter/material.dart';

/// Defer Navigator.pop ke frame berikutnya (hindari _dependents.isEmpty di HP RAM rendah).
/// Gunakan untuk semua dialog di flow verifikasi KTP/SIM.
void safePop(BuildContext context, [dynamic result]) {
  void doPop() {
    if (!context.mounted) return;
    try {
      if (Navigator.of(context).canPop()) {
        Navigator.of(context).pop(result);
      }
    } catch (_) {}
  }

  WidgetsBinding.instance.addPostFrameCallback((_) {
    if (!context.mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!context.mounted) return;
      // Microtask: yield ke event loop agar tree selesai (hindari _dependents.isEmpty)
      Future<void>.delayed(Duration.zero, doPop);
    });
  });
}

/// Pop dengan defer, return Future yang selesai setelah pop. Untuk alur: tutup dialog A, lalu tampilkan dialog B.
/// Delay 300ms sebelum pop agar tree selesai (hindari _dependents.isEmpty di HP RAM rendah).
Future<void> safePopAndComplete(BuildContext context, [dynamic result]) async {
  final completer = Completer<void>();
  void doPop() {
    if (!context.mounted) {
      completer.complete();
      return;
    }
    try {
      final navigator = Navigator.of(context, rootNavigator: true);
      if (navigator.canPop()) {
        navigator.pop(result);
      }
    } catch (_) {}
    completer.complete();
  }

  WidgetsBinding.instance.addPostFrameCallback((_) {
    if (!context.mounted) {
      completer.complete();
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!context.mounted) {
        completer.complete();
        return;
      }
      // Delay 300ms: beri waktu tree selesai update (fix _dependents.isEmpty saat Simpan)
      Future<void>.delayed(const Duration(milliseconds: 300), doPop);
    });
  });
  return completer.future;
}
