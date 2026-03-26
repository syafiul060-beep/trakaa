import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';

import '../utils/app_logger.dart' show logError;

/// Breadcrumb & metrik ringan untuk mode hybrid + jadwal driver (Crashlytics non-fatal / log).
class DriverHybridDiagnostics {
  DriverHybridDiagnostics._();

  static void breadcrumb(String message) {
    final line = '[DriverHybrid] $message';
    if (kDebugMode) {
      debugPrint(line);
    }
    try {
      FirebaseCrashlytics.instance.log(line);
    } catch (_) {}
  }

  /// Operasi jadwal: muat, hapus, sinkron diam, dll.
  static void recordScheduleOp(
    String operation, {
    required String outcome,
    int? ms,
    String? detail,
  }) {
    final parts = <String>[
      'schedule.$operation',
      'outcome=$outcome',
      if (ms != null) 'ms=$ms',
      if (detail != null && detail.isNotEmpty) 'detail=${detail.length > 120 ? detail.substring(0, 120) : detail}',
    ];
    breadcrumb(parts.join(' '));
    try {
      FirebaseCrashlytics.instance.setCustomKey('last_schedule_op', operation);
      FirebaseCrashlytics.instance.setCustomKey('last_schedule_outcome', outcome);
      if (ms != null) {
        FirebaseCrashlytics.instance.setCustomKey('last_schedule_ms', ms);
      }
    } catch (_) {}
  }

  static void recordError(String context, Object e, [StackTrace? st]) {
    logError(context, e, st);
  }

  /// Full-scan `driver_schedules` (semua dokumen). Breadcrumb di release hanya jika lambat / banyak dokumen.
  static void recordSchedulesCollectionScan({
    required String operation,
    required int elapsedMs,
    required int driverDocCount,
    required int resultCount,
  }) {
    if (kDebugMode) {
      debugPrint(
        '[DriverHybrid] schedules.scan op=$operation docs=$driverDocCount '
        'ms=$elapsedMs results=$resultCount',
      );
    }
    const slowMs = 2500;
    const manyDocs = 80;
    if (elapsedMs < slowMs && driverDocCount < manyDocs) return;
    breadcrumb(
      'schedules.full_scan op=$operation docs=$driverDocCount ms=$elapsedMs results=$resultCount',
    );
    try {
      FirebaseCrashlytics.instance
          .setCustomKey('last_schedules_scan_ms', elapsedMs);
      FirebaseCrashlytics.instance
          .setCustomKey('last_schedules_scan_docs', driverDocCount);
      FirebaseCrashlytics.instance.setCustomKey('last_schedules_scan_op', operation);
    } catch (_) {}
  }
}
