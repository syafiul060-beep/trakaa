import 'package:firebase_crashlytics/firebase_crashlytics.dart';

/// Non-fatal Crashlytics untuk kegagalan Directions (throttle — hindari spam saat loop reroute).
class NavigationDiagnostics {
  NavigationDiagnostics._();

  static DateTime? _lastDirectionsFailureReportAt;
  static String? _lastReportedSignature;

  /// Laporkan kegagalan fetch rute (bukan sukses dengan stale).
  static void reportDirectionsFailureThrottled({
    required String scope,
    required String? errorKey,
  }) {
    final key = (errorKey ?? '').trim();
    if (key.isEmpty) return;
    // Bukan isu infrastruktur / produk yang perlu trend di Crashlytics
    if (key == 'zero_routes' || key == 'no_polyline') return;

    final sig = '$scope|$key';
    final now = DateTime.now();
    if (_lastReportedSignature == sig &&
        _lastDirectionsFailureReportAt != null &&
        now.difference(_lastDirectionsFailureReportAt!) <
            const Duration(minutes: 10)) {
      return;
    }
    _lastReportedSignature = sig;
    _lastDirectionsFailureReportAt = now;

    FirebaseCrashlytics.instance.log(
      '[directions_fail] scope=$scope error=$key',
    );
    FirebaseCrashlytics.instance.recordError(
      Exception('DirectionsFailure $scope: $key'),
      StackTrace.current,
      fatal: false,
      reason: 'driver_directions_route_fetch',
    );
  }
}
