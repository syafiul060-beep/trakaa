import 'package:flutter_test/flutter_test.dart';

import 'package:traka/services/vehicle_plat_service.dart';

void main() {
  group('VehiclePlatService', () {
    test('platExistsForOtherDriver returns false for empty plat', () async {
      // Empty plat: service returns false (early return)
      final result = await VehiclePlatService.platExistsForOtherDriver('');
      expect(result, false);
    });

    test('platExistsForOtherDriver returns false for whitespace-only plat', () async {
      // Whitespace becomes empty after trim: early return
      final result = await VehiclePlatService.platExistsForOtherDriver('   ');
      expect(result, false);
    });
  });
}
