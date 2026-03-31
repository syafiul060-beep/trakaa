import 'package:flutter_test/flutter_test.dart';
import 'package:traka/services/driver_nav_premium_pricing.dart';

void main() {
  test('distance tier + nasional multiplier snaps to allowed SKU', () {
    final fee = DriverNavPremiumPricing.computeRupiah(
      scope: 'dalamNegara',
      distanceMeters: 600 * 1000,
      settings: null,
    );
    expect(fee, 50000);
  });

  test('short dalam provinsi uses lower band', () {
    final fee = DriverNavPremiumPricing.computeRupiah(
      scope: 'dalamProvinsi',
      distanceMeters: 50 * 1000,
      settings: null,
    );
    expect(fee, 10000);
  });

  test('driverNavPremiumDistancePricingEnabled false uses legacy scope fee', () {
    final fee = DriverNavPremiumPricing.computeRupiah(
      scope: 'dalamProvinsi',
      distanceMeters: 800 * 1000,
      settings: const {'driverNavPremiumDistancePricingEnabled': false},
    );
    expect(fee, 50000);
  });

  test('no distance falls back to legacy', () {
    final fee = DriverNavPremiumPricing.computeRupiah(
      scope: 'antarProvinsi',
      distanceMeters: null,
      settings: null,
    );
    expect(fee, 75000);
  });
}
