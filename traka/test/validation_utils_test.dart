import 'package:flutter_test/flutter_test.dart';

import 'package:traka/utils/validation_utils.dart';

void main() {
  group('ValidationUtils', () {
    group('validatePassword', () {
      test('returns error when empty', () {
        expect(
          ValidationUtils.validatePassword(null, isIndonesian: true),
          'Masukkan kata sandi',
        );
        expect(
          ValidationUtils.validatePassword('', isIndonesian: true),
          'Masukkan kata sandi',
        );
      });

      test('returns error when less than 8 chars', () {
        expect(
          ValidationUtils.validatePassword('Abc123', isIndonesian: true),
          isNotNull,
        );
        expect(
          ValidationUtils.validatePassword('Abc123', isIndonesian: false),
          isNotNull,
        );
      });

      test('returns error when no digit', () {
        expect(
          ValidationUtils.validatePassword('abcdefgh', isIndonesian: true),
          isNotNull,
        );
      });

      test('returns null when valid', () {
        expect(
          ValidationUtils.validatePassword('Password1', isIndonesian: true),
          isNull,
        );
        expect(
          ValidationUtils.validatePassword('abc12345', isIndonesian: false),
          isNull,
        );
      });

      test('returns null when exactly 8 chars with digit', () {
        expect(
          ValidationUtils.validatePassword('Abcd1234', isIndonesian: true),
          isNull,
        );
      });

      test('returns error when 8 chars but no digit', () {
        expect(
          ValidationUtils.validatePassword('abcdefgh', isIndonesian: true),
          isNotNull,
        );
      });
    });

    group('validateConfirmPassword', () {
      test('returns error when empty', () {
        expect(
          ValidationUtils.validateConfirmPassword(
            null,
            'pass',
            isIndonesian: true,
          ),
          'Konfirmasi kata sandi',
        );
      });

      test('returns error when mismatch', () {
        expect(
          ValidationUtils.validateConfirmPassword(
            'pass2',
            'pass1',
            isIndonesian: true,
          ),
          'Kata sandi tidak cocok',
        );
      });

      test('returns null when match', () {
        expect(
          ValidationUtils.validateConfirmPassword(
            'Password1',
            'Password1',
            isIndonesian: true,
          ),
          isNull,
        );
      });
    });
  });
}
