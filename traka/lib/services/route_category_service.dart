import 'geocoding_service.dart';
import 'travel_admin_region.dart';

import '../config/province_island.dart';

/// Kategori rute travel: dalam kota, antar provinsi (1 pulau), nasional.
/// Untuk informasi penumpang (estimasi durasi, filter). Bukan untuk tarif aplikasi.
class RouteCategoryService {
  RouteCategoryService._();

  static const String categoryDalamKota = 'dalam_kota';
  static const String categoryAntarKabupaten = 'antar_kabupaten';
  static const String categoryAntarProvinsi = 'antar_provinsi';
  static const String categoryNasional = 'nasional';
  /// Kategori fallback saat geocoding gagal / tidak tersedia.
  static const String categoryUnknownGeocode = 'unknown_geocode';

  /// Label singkat untuk tampilan.
  static String getLabel(String category) {
    switch (category) {
      case categoryDalamKota:
        return 'Dalam Kota';
      case categoryAntarKabupaten:
        return 'Antar Kabupaten';
      case categoryAntarProvinsi:
        return 'Antar Provinsi';
      case categoryNasional:
        return 'Nasional';
      default:
        return '–';
    }
  }

  /// Ambil placemark pertama dari koordinat.
  static Future<Placemark?> _placemarkAt(double lat, double lng) async {
    try {
      final placemarks =
          await GeocodingService.placemarkFromCoordinates(lat, lng);
      if (placemarks.isEmpty) return null;
      return placemarks.first;
    } catch (_) {
      return null;
    }
  }

  /// Tentukan kategori rute berdasarkan origin dan destination.
  /// Return: (category, label, estimasiDurasi).
  static Future<({String category, String label, String estimatedDuration})>
      getRouteCategory({
    required double originLat,
    required double originLng,
    required double destLat,
    required double destLng,
  }) async {
    final oPm = await _placemarkAt(originLat, originLng);
    final dPm = await _placemarkAt(destLat, destLng);
    final oReg = oPm != null ? TravelAdminRegion.fromPlacemark(oPm) : null;
    final dReg = dPm != null ? TravelAdminRegion.fromPlacemark(dPm) : null;

    // Default
    String category = categoryAntarProvinsi;
    String duration = '–';

    final oProvRaw = (oPm?.administrativeArea ?? '').trim();
    final dProvRaw = (dPm?.administrativeArea ?? '').trim();
    final oProv = oProvRaw.isEmpty ? null : oProvRaw;
    final dProv = dProvRaw.isEmpty ? null : dProvRaw;

    if (oProv != null && dProv != null) {
      final sameProvince = (oReg?.provinceKey != null &&
              dReg?.provinceKey != null &&
              oReg!.provinceKey == dReg!.provinceKey) ||
          (oProv == dProv);
      final oKabRaw = (oPm?.subAdministrativeArea ?? '').trim();
      final dKabRaw = (dPm?.subAdministrativeArea ?? '').trim();
      final sameKabupaten = (oReg?.kabupatenKey != null &&
              dReg?.kabupatenKey != null &&
              oReg!.kabupatenKey == dReg!.kabupatenKey) ||
          (oKabRaw.isNotEmpty &&
              dKabRaw.isNotEmpty &&
              oKabRaw == dKabRaw);

      if (sameProvince && sameKabupaten) {
        category = categoryDalamKota;
        duration = '~1–3 jam';
      } else if (sameProvince) {
        category = categoryAntarKabupaten;
        duration = '~2–6 jam';
      } else {
        final originIsland = ProvinceIsland.getIslandForProvince(oProv);
        final destIsland = ProvinceIsland.getIslandForProvince(dProv);
        if (originIsland != null &&
            destIsland != null &&
            originIsland != destIsland) {
          category = categoryNasional;
          duration = '~1–3 hari';
        } else {
          category = categoryAntarProvinsi;
          duration = '~4–12 jam';
        }
      }
    }

    return (
      category: category,
      label: getLabel(category),
      estimatedDuration: duration,
    );
  }
}
