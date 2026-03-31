import '../config/province_island.dart';
import '../l10n/app_localizations.dart';
import 'geocoding_service.dart' show GeocodingService;

/// Validasi titik pilih-di-peta untuk form rute driver — selaras filter autocomplete.
/// Pesan memakai [AppLocalizations] (ID/EN).
class DriverRouteMapPickValidation {
  DriverRouteMapPickValidation._();

  /// Validasi dari [administrativeArea] saja (unit test, tanpa geocode).
  static String? validateAdministrativeAreaForPoint({
    required AppLocalizations l10n,
    required String? administrativeArea,
    required bool isOrigin,
    required bool sameProvinceOnly,
    required bool sameIslandOnly,
    required String? currentProvinsi,
    required List<String> provincesInIsland,
  }) {
    final admin = (administrativeArea ?? '').trim();
    if (admin.isEmpty) {
      return l10n.driverMapPickPointUnreadable;
    }
    final pointCanon = ProvinceIsland.resolveProvinceCanonical(admin);
    final driverCanon = ProvinceIsland.resolveProvinceCanonical(currentProvinsi);

    if (sameProvinceOnly) {
      if (driverCanon != null &&
          pointCanon != null &&
          pointCanon != driverCanon) {
        return isOrigin
            ? l10n.driverMapPickOriginMustSameProvince(
                currentProvinsi ?? '',
              )
            : l10n.driverMapPickDestMustSameProvinceWithinRoute(
                currentProvinsi ?? '',
              );
      }
    }
    if (sameIslandOnly && provincesInIsland.isNotEmpty) {
      if (!ProvinceIsland.isProvinceInList(admin, provincesInIsland)) {
        return isOrigin
            ? l10n.driverMapPickOriginMustSameIsland
            : l10n.driverMapPickDestMustSameIsland;
      }
    }
    return null;
  }

  /// [isOrigin]: true = titik awal, false = titik tujuan.
  static Future<String?> validatePoint({
    required AppLocalizations l10n,
    required double lat,
    required double lng,
    required bool isOrigin,
    required bool sameProvinceOnly,
    required bool sameIslandOnly,
    required String? currentProvinsi,
    required List<String> provincesInIsland,
  }) async {
    final pList = await GeocodingService.placemarkFromCoordinates(lat, lng);
    if (pList.isEmpty) {
      return l10n.driverMapPickPointUnreadable;
    }
    return validateAdministrativeAreaForPoint(
      l10n: l10n,
      administrativeArea: pList.first.administrativeArea,
      isOrigin: isOrigin,
      sameProvinceOnly: sameProvinceOnly,
      sameIslandOnly: sameIslandOnly,
      currentProvinsi: currentProvinsi,
      provincesInIsland: provincesInIsland,
    );
  }

  /// Rute antar provinsi: tujuan tidak boleh satu provinsi dengan [referenceProvince].
  static String? validateDestinationDifferentProvinceThanSync({
    required AppLocalizations l10n,
    required String? destAdministrativeArea,
    required String? referenceProvince,
  }) {
    final ref = referenceProvince?.trim();
    if (ref == null || ref.isEmpty) return null;
    final destCanon = ProvinceIsland.resolveProvinceCanonical(
      destAdministrativeArea,
    );
    final refCanon = ProvinceIsland.resolveProvinceCanonical(ref);
    if (destCanon != null && refCanon != null && destCanon == refCanon) {
      return l10n.driverMapPickDestMustDifferentProvinceInterProvince;
    }
    return null;
  }

  static Future<String?> validateDestinationDifferentProvinceThan({
    required AppLocalizations l10n,
    required double destLat,
    required double destLng,
    required String? referenceProvince,
  }) async {
    final pList =
        await GeocodingService.placemarkFromCoordinates(destLat, destLng);
    if (pList.isEmpty) return null;
    return validateDestinationDifferentProvinceThanSync(
      l10n: l10n,
      destAdministrativeArea: pList.first.administrativeArea,
      referenceProvince: referenceProvince,
    );
  }

  static Future<String?> administrativeAreaFromCoordinates(
    double lat,
    double lng,
  ) async {
    final pList = await GeocodingService.placemarkFromCoordinates(lat, lng);
    if (pList.isEmpty) return null;
    final a = pList.first.administrativeArea;
    if (a == null || a.trim().isEmpty) return null;
    return a.trim();
  }
}
