import 'package:geocoding/geocoding.dart' as geo;

import 'geocoding_service.dart';
import 'route_category_service.dart';

/// Wilayah administratif hasil geocode (Tahap 0–2 matching travel).
/// Kunci dinormalisasi agar bisa dibandingkan antar perangkat / penyedia geocode.
class TravelAdminRegion {
  final String? provinceKey;
  final String? kabupatenKey;
  final String? kecamatanKey;

  const TravelAdminRegion({
    this.provinceKey,
    this.kabupatenKey,
    this.kecamatanKey,
  });

  static String? normalizeToken(String? raw) {
    if (raw == null) return null;
    var s = raw.trim().toLowerCase();
    if (s.isEmpty) return null;
    for (final prefix in [
      'kabupaten ',
      'kab. ',
      'kota ',
      'kota administrasi ',
      'kecamatan ',
      'kec. ',
    ]) {
      if (s.startsWith(prefix)) {
        s = s.substring(prefix.length).trim();
        break;
      }
    }
    return s.isEmpty ? null : s;
  }

  static TravelAdminRegion? fromPlacemark(geo.Placemark p) {
    final prov = normalizeToken(p.administrativeArea);
    final kab = normalizeToken(p.subAdministrativeArea);
    final kec = normalizeToken(p.locality ?? p.subLocality);
    if (prov == null && kab == null && kec == null) return null;
    return TravelAdminRegion(
      provinceKey: prov,
      kabupatenKey: kab,
      kecamatanKey: kec,
    );
  }

  static Future<TravelAdminRegion?> fromCoordinates(
    double lat,
    double lng,
  ) async {
    try {
      final list = await GeocodingService.placemarkFromCoordinates(lat, lng);
      if (list.isEmpty) return null;
      return fromPlacemark(list.first);
    } catch (_) {
      return null;
    }
  }

  /// Filter administratif penumpang ↔ trayek driver (Tahap 2).
  /// Bila driver belum punya kunci (data lama), loloskan agar tidak memutus driver aktif.
  static bool passengerDriverAdminMatch({
    required String passengerRouteCategory,
    TravelAdminRegion? passengerOrigin,
    TravelAdminRegion? passengerDest,
    String? driverOriginKabKey,
    String? driverDestKabKey,
    String? driverOriginProvKey,
    String? driverDestProvKey,
  }) {
    final hasDriverAdmin = (driverOriginKabKey != null &&
            driverOriginKabKey.isNotEmpty) ||
        (driverDestKabKey != null && driverDestKabKey.isNotEmpty) ||
        (driverOriginProvKey != null && driverOriginProvKey.isNotEmpty) ||
        (driverDestProvKey != null && driverDestProvKey.isNotEmpty);
    if (!hasDriverAdmin) return true;

    if (passengerRouteCategory == RouteCategoryService.categoryUnknownGeocode) {
      return true;
    }
    if (passengerRouteCategory == RouteCategoryService.categoryAntarProvinsi ||
        passengerRouteCategory == RouteCategoryService.categoryNasional) {
      return true;
    }

    if (passengerOrigin == null || passengerDest == null) return true;

    if (passengerRouteCategory == RouteCategoryService.categoryDalamKota) {
      final kab = passengerOrigin.kabupatenKey;
      final kabD = passengerDest.kabupatenKey;
      if (kab == null ||
          kabD == null ||
          kab != kabD) {
        return true;
      }
      final onTrayek =
          driverOriginKabKey == kab || driverDestKabKey == kab;
      return onTrayek;
    }

    if (passengerRouteCategory == RouteCategoryService.categoryAntarKabupaten) {
      final prov = passengerOrigin.provinceKey;
      final provD = passengerDest.provinceKey;
      if (prov == null || provD == null || prov != provD) {
        return true;
      }
      if (driverOriginProvKey != null &&
          driverDestProvKey != null &&
          driverOriginProvKey.isNotEmpty &&
          driverDestProvKey.isNotEmpty) {
        return driverOriginProvKey == prov && driverDestProvKey == prov;
      }
      return true;
    }

    return true;
  }
}

/// Dokumentasi tahap matching driver aktif (penumpang «Cari travel»).
///
/// Tahap 0: driver [siap_kerja] + OD patokan tersimpan + kunci admin (jika sudah di-geocode).
/// Tahap 1: posisi GPS driver; tidak perlu menempel polyline untuk tampil bila lolos filter.
/// Tahap 2: OD penumpang vs koridor buffer + wilayah admin.
/// Tahap 3: koridor memakai alternatif OD driver + segmen live GPS→tujuan (re-route kasar).
/// Tahap 4: [orderBoundStrictMatching] memperketat buffer (setelah deal / navigasi ke penumpang).
abstract final class TravelMatchingPhases {
  static const int prerequisite = 0;
  static const int driverFreeMovement = 1;
  static const int corridorAndAdmin = 2;
  static const int navigationRerouteCorridor = 3;
  static const int orderBound = 4;
}
