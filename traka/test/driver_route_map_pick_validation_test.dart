import 'package:flutter_test/flutter_test.dart';

import 'package:traka/config/province_island.dart';
import 'package:traka/l10n/app_localizations.dart';
import 'package:traka/services/driver_route_map_pick_validation.dart';

void main() {
  group('DriverRouteMapPickValidation', () {
    late List<String> jawaProvinces;
    late AppLocalizations l10nId;

    setUp(() {
      jawaProvinces = ProvinceIsland.getProvincesInSameIsland('Jawa Barat')!;
      l10nId = AppLocalizations(locale: AppLocale.id);
    });

    test('dalam provinsi: tujuan beda provinsi ditolak', () {
      final err =
          DriverRouteMapPickValidation.validateAdministrativeAreaForPoint(
        l10n: l10nId,
        administrativeArea: 'Jawa Timur',
        isOrigin: false,
        sameProvinceOnly: true,
        sameIslandOnly: false,
        currentProvinsi: 'Jawa Barat',
        provincesInIsland: const [],
      );
      expect(err, isNotNull);
      expect(err, l10nId.driverMapPickDestMustSameProvinceWithinRoute('Jawa Barat'));
    });

    test('dalam provinsi: tujuan sama provinsi diterima', () {
      expect(
        DriverRouteMapPickValidation.validateAdministrativeAreaForPoint(
          l10n: l10nId,
          administrativeArea: 'Jawa Barat',
          isOrigin: false,
          sameProvinceOnly: true,
          sameIslandOnly: false,
          currentProvinsi: 'Jawa Barat',
          provincesInIsland: const [],
        ),
        isNull,
      );
    });

    test('antar provinsi: tujuan di pulau lain ditolak', () {
      final err =
          DriverRouteMapPickValidation.validateAdministrativeAreaForPoint(
        l10n: l10nId,
        administrativeArea: 'Aceh',
        isOrigin: false,
        sameProvinceOnly: false,
        sameIslandOnly: true,
        currentProvinsi: 'Jawa Barat',
        provincesInIsland: jawaProvinces,
      );
      expect(err, isNotNull);
      expect(err, l10nId.driverMapPickDestMustSameIsland);
    });

    test('antar provinsi: tujuan provinsi lain di pulau sama diterima', () {
      expect(
        DriverRouteMapPickValidation.validateAdministrativeAreaForPoint(
          l10n: l10nId,
          administrativeArea: 'Jawa Timur',
          isOrigin: false,
          sameProvinceOnly: false,
          sameIslandOnly: true,
          currentProvinsi: 'Jawa Barat',
          provincesInIsland: jawaProvinces,
        ),
        isNull,
      );
    });

    test('antar provinsi: tujuan sama provinsi dengan referensi ditolak', () {
      expect(
        DriverRouteMapPickValidation.validateDestinationDifferentProvinceThanSync(
          l10n: l10nId,
          destAdministrativeArea: 'Jawa Barat',
          referenceProvince: 'Jawa Barat',
        ),
        l10nId.driverMapPickDestMustDifferentProvinceInterProvince,
      );
    });

    test('antar provinsi: tujuan beda provinsi dengan referensi diterima', () {
      expect(
        DriverRouteMapPickValidation.validateDestinationDifferentProvinceThanSync(
          l10n: l10nId,
          destAdministrativeArea: 'Jawa Timur',
          referenceProvince: 'Jawa Barat',
        ),
        isNull,
      );
    });

    test('admin kosong: ditolak', () {
      expect(
        DriverRouteMapPickValidation.validateAdministrativeAreaForPoint(
          l10n: l10nId,
          administrativeArea: '  ',
          isOrigin: true,
          sameProvinceOnly: false,
          sameIslandOnly: false,
          currentProvinsi: null,
          provincesInIsland: const [],
        ),
        l10nId.driverMapPickPointUnreadable,
      );
    });

    test('locale EN: pesan beda bahasa', () {
      final l10nEn = AppLocalizations(locale: AppLocale.en);
      final msg = DriverRouteMapPickValidation.validateAdministrativeAreaForPoint(
        l10n: l10nEn,
        administrativeArea: '  ',
        isOrigin: true,
        sameProvinceOnly: false,
        sameIslandOnly: false,
        currentProvinsi: null,
        provincesInIsland: const [],
      );
      expect(msg, l10nEn.driverMapPickPointUnreadable);
      expect(msg, isNot(equals(l10nId.driverMapPickPointUnreadable)));
    });
  });
}
