import 'package:flutter/foundation.dart';

import 'package:firebase_crashlytics/firebase_crashlytics.dart';

/// Log hanya di debug mode. Di release build tidak menulis ke console.
void log(String message, [Object? error, StackTrace? stackTrace]) {
  if (kDebugMode) {
    if (error != null) {
      debugPrint('$message: $error');
      if (stackTrace != null) debugPrint(stackTrace.toString());
    } else {
      debugPrint(message);
    }
  }
}

/// Log error untuk debugging. Di debug: print ke console. Di release: non-fatal ke Crashlytics.
/// Gunakan untuk error yang tidak fatal (mis. catch block) agar bisa dilacak di production.
void logError(String context, Object error, [StackTrace? stackTrace]) {
  if (kDebugMode) {
    debugPrint('$context: $error');
    if (stackTrace != null) debugPrint(stackTrace.toString());
  } else {
    try {
      FirebaseCrashlytics.instance.recordError(
        error,
        stackTrace ?? StackTrace.current,
        reason: context,
        fatal: false,
      );
    } catch (_) {
      // Crashlytics mungkin belum init; abaikan
    }
  }
}
