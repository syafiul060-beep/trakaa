import 'package:flutter_test/flutter_test.dart';

import 'package:traka/config/app_constants.dart';

void main() {
  group('AppConstants', () {
    test('defaultTarifPerKm is 50', () {
      expect(AppConstants.defaultTarifPerKm, 50);
    });

    test('packageName is id.traka.app', () {
      expect(AppConstants.packageName, 'id.traka.app');
    });

    test('defaultPageSize is 20', () {
      expect(AppConstants.defaultPageSize, 20);
    });

    test('networkTimeoutSeconds is 30', () {
      expect(AppConstants.networkTimeoutSeconds, 30);
    });

    test('listViewCacheExtent is 200', () {
      expect(AppConstants.listViewCacheExtent, 200);
    });

    test('constants are positive where expected', () {
      expect(AppConstants.defaultTarifPerKm, greaterThan(0));
      expect(AppConstants.defaultPageSize, greaterThan(0));
      expect(AppConstants.networkTimeoutSeconds, greaterThan(0));
      expect(AppConstants.listViewCacheExtent, greaterThan(0));
    });
  });
}
