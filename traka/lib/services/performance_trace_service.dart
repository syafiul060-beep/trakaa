import 'package:firebase_performance/firebase_performance.dart';

/// Firebase Performance: trace bernama untuk pengukuran di konsol (tanpa mengubah frekuensi update peta).
class PerformanceTraceService {
  PerformanceTraceService._();

  static Trace? _startupTrace;
  static bool _startupStarted = false;

  static Trace? _passengerMapTrace;
  static Trace? _driverMapTrace;

  /// Mulai trace dari cold start hingga layar interaktif pertama (home / login / onboarding, dll.).
  static Future<void> startStartupToInteractive() async {
    if (_startupStarted) return;
    _startupStarted = true;
    try {
      _startupTrace =
          FirebasePerformance.instance.newTrace('startup_to_interactive');
      await _startupTrace!.start();
    } catch (_) {
      _startupTrace = null;
    }
  }

  /// Hentikan trace startup (aman dipanggil berulang).
  static Future<void> stopStartupToInteractive() async {
    final t = _startupTrace;
    _startupTrace = null;
    if (t == null) return;
    try {
      await t.stop();
    } catch (_) {}
  }

  /// Mulai saat `GoogleMap` penumpang selesai dibuat (hentikan setelah frame pertama).
  static Future<void> startPassengerMapReadyTrace() async {
    await stopPassengerMapReadyTrace();
    try {
      _passengerMapTrace =
          FirebasePerformance.instance.newTrace('passenger_map_ready');
      await _passengerMapTrace!.start();
    } catch (_) {
      _passengerMapTrace = null;
    }
  }

  static Future<void> stopPassengerMapReadyTrace() async {
    final t = _passengerMapTrace;
    _passengerMapTrace = null;
    if (t == null) return;
    try {
      await t.stop();
    } catch (_) {}
  }

  /// Mulai saat `GoogleMap` driver (beranda) selesai dibuat — hentikan setelah frame pertama.
  /// Lihat `docs/PROFIL_PERFORMA_PETA_DRIVER.md` untuk profil lokal dengan DevTools.
  static Future<void> startDriverMapReadyTrace() async {
    await stopDriverMapReadyTrace();
    try {
      _driverMapTrace =
          FirebasePerformance.instance.newTrace('driver_map_ready');
      await _driverMapTrace!.start();
    } catch (_) {
      _driverMapTrace = null;
    }
  }

  static Future<void> stopDriverMapReadyTrace() async {
    final t = _driverMapTrace;
    _driverMapTrace = null;
    if (t == null) return;
    try {
      await t.stop();
    } catch (_) {}
  }

  /// Trace sekitar pembuatan pesanan (network + Firestore).
  static Future<T> traceOrderSubmit<T>(Future<T> Function() action) async {
    Trace? trace;
    try {
      trace = FirebasePerformance.instance.newTrace('order_submit');
      await trace.start();
    } catch (_) {
      trace = null;
    }
    try {
      return await action();
    } finally {
      if (trace != null) {
        try {
          await trace.stop();
        } catch (_) {}
      }
    }
  }
}
