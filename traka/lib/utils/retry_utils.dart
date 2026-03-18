import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../config/app_constants.dart';

/// Utility untuk retry operasi yang gagal karena error transient (jaringan, timeout, 5xx).
class RetryUtils {
  RetryUtils._();

  /// Jumlah percobaan maksimal (termasuk percobaan pertama).
  static const int defaultMaxAttempts = 3;

  /// Delay awal antar percobaan (ms).
  static const int baseDelayMs = 1000;

  /// Delay maksimal antar percobaan (ms).
  static const int maxDelayMs = 8000;

  /// Timeout per percobaan (detik).
  static int get _timeoutSeconds => AppConstants.networkTimeoutSeconds;

  /// Cek apakah exception termasuk error transient yang layak di-retry.
  static bool _isRetryableException(Object e, StackTrace? st) {
    if (e is SocketException) return true;
    if (e is TimeoutException) return true;
    if (e is HandshakeException) return true;
    if (e is OSError) {
      // Connection refused, network unreachable, dll.
      return true;
    }
    final msg = e.toString().toLowerCase();
    if (msg.contains('socket') ||
        msg.contains('timeout') ||
        msg.contains('connection') ||
        msg.contains('network')) {
      return true;
    }
    return false;
  }

  /// Jalankan [fn] dengan retry exponential backoff jika gagal.
  /// Retry hanya untuk error transient (SocketException, TimeoutException, dll).
  /// [fn] harus throw untuk menandakan kegagalan yang perlu di-retry.
  static Future<T> withRetry<T>(
    Future<T> Function() fn, {
    int maxAttempts = defaultMaxAttempts,
    int baseDelayMs = RetryUtils.baseDelayMs,
    int maxDelayMs = RetryUtils.maxDelayMs,
    bool Function(Object e, StackTrace? st)? isRetryable,
  }) async {
    int attempt = 0;

    while (true) {
      attempt++;
      try {
        final result = await fn().timeout(
          Duration(seconds: _timeoutSeconds),
          onTimeout: () => throw TimeoutException(
            'Operation timed out after $_timeoutSeconds seconds',
          ),
        );
        return result;
      } catch (e, st) {
        final shouldRetry = (isRetryable ?? _isRetryableException)(e, st);
        if (!shouldRetry || attempt >= maxAttempts) {
          rethrow;
        }

        final delayMs = (baseDelayMs * (1 << (attempt - 1)))
            .clamp(baseDelayMs, maxDelayMs);
        if (kDebugMode) {
          debugPrint(
            '[RetryUtils] Attempt $attempt/$maxAttempts failed: $e. '
            'Retrying in ${delayMs}ms...',
          );
        }
        await Future<void>.delayed(Duration(milliseconds: delayMs));
      }
    }
  }
}
