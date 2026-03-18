import 'package:flutter_test/flutter_test.dart';

import 'package:traka/services/device_security_service.dart';

void main() {
  group('DeviceSecurityResult', () {
    test('allowed() creates result with allowed true and null message', () {
      const result = DeviceSecurityResult(allowed: true);
      expect(result.allowed, true);
      expect(result.message, isNull);
    });

    test('DeviceSecurityResult.allowed() factory', () {
      final result = DeviceSecurityResult.allowed();
      expect(result.allowed, true);
      expect(result.message, isNull);
    });

    test('DeviceSecurityResult.blocked() factory with message', () {
      const msg = 'Terlalu banyak percobaan login gagal.';
      final result = DeviceSecurityResult.blocked(msg);
      expect(result.allowed, false);
      expect(result.message, msg);
    });

    test('blocked result has non-null message', () {
      final result = DeviceSecurityResult.blocked('Registrasi tidak diperbolehkan.');
      expect(result.allowed, false);
      expect(result.message, isNotNull);
      expect(result.message, 'Registrasi tidak diperbolehkan.');
    });
  });

  group('DeviceSecurityService', () {
    test('DeviceSecurityResult types work for rate limit flow', () {
      // checkLoginRateLimit uses Cloud Function; unit test verifies result types
      expect(DeviceSecurityResult.allowed().allowed, true);
      expect(DeviceSecurityResult.blocked('rate limit').allowed, false);
    });
  });
}
