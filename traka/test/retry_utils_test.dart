import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:traka/utils/retry_utils.dart';

void main() {
  group('RetryUtils', () {
    test('returns result on first success', () async {
      final result = await RetryUtils.withRetry(() async => 42);
      expect(result, 42);
    });

    test('retries on SocketException and eventually succeeds', () async {
      int attempts = 0;
      final result = await RetryUtils.withRetry(() async {
        attempts++;
        if (attempts < 2) {
          throw const SocketException('Connection refused');
        }
        return 'ok';
      }, maxAttempts: 3, baseDelayMs: 10, maxDelayMs: 50);
      expect(result, 'ok');
      expect(attempts, 2);
    });

    test('rethrows after max attempts', () async {
      await expectLater(
        RetryUtils.withRetry(
          () async => throw const SocketException('fail'),
          maxAttempts: 2,
          baseDelayMs: 5,
          maxDelayMs: 20,
        ),
        throwsA(isA<SocketException>()),
      );
    });

    test('rethrows immediately on non-retryable exception', () async {
      await expectLater(
        RetryUtils.withRetry(
          () async => throw Exception('not retryable'),
          maxAttempts: 3,
          baseDelayMs: 5,
          maxDelayMs: 20,
        ),
        throwsA(isA<Exception>()),
      );
    });
  });
}
