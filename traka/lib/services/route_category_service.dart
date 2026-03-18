import 'geocoding_service.dart';

import '../config/province_island.dart';

/// Kategori rute travel: dalam kota, antar provinsi (1 pulau), nasional.
/// Untuk informasi penumpang (estimasi durasi, filter). Bukan untuk tarif aplikasi.
class RouteCategoryService {
  RouteCategoryService._();

  static const String categoryDalamKota = 'dalam_kota';
  static const String categoryAntarKabupaten = 'antar_kabupaten';
  static const String categoryAntarProvinsi = 'antar_provinsi';
  static const String categoryNasional = 'nasional';

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

  /// Ambil placemark (provinsi, kabupaten) dari koordinat.
  static Future<({String? province, String? kabupaten})> _getPlacemark(
    double lat,
    double lng,
  ) async {
    try {
      final placemarks =
          await GeocodingService.placemarkFromCoordinates(lat, lng);
      if (placemarks.isEmpty) return (province: null, kabupaten: null);
      final p = placemarks.first;
      final province = (p.administrativeArea ?? '').trim();
      final kabupaten = (p.subAdministrativeArea ?? '').trim();
      return (
        province: province.isEmpty ? null : province,
        kabupaten: kabupaten.isEmpty ? null : kabupaten,
      );
    } catch (_) {
      return (province: null, kabupaten: null);
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
    final origin = await _getPlacemark(originLat, originLng);
    final dest = await _getPlacemark(destLat, destLng);

    // Default
    String category = categoryAntarProvinsi;
    String duration = '–';

    if (origin.province != null && dest.province != null) {
      final sameProvince = origin.province == dest.province;
      final sameKabupaten = (origin.kabupaten != null &&
          dest.kabupaten != null &&
          origin.kabupaten == dest.kabupaten);

      if (sameProvince && sameKabupaten) {
        category = categoryDalamKota;
        duration = '~1–3 jam';
      } else if (sameProvince) {
        category = categoryAntarKabupaten;
        duration = '~2–6 jam';
      } else {
        final originIsland =
            ProvinceIsland.getIslandForProvince(origin.province);
        final destIsland = ProvinceIsland.getIslandForProvince(dest.province);
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
