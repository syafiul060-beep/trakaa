import 'geocoding_service.dart';

import '../config/province_island.dart';
import 'app_config_service.dart';

/// Service untuk Lacak Barang (kirim barang).
/// Menentukan tier harga berdasarkan provinsi asal dan tujuan.
class LacakBarangService {
  /// Tier 1: dalam provinsi (7500)
  /// Tier 2: beda provinsi, satu pulau (10000)
  /// Tier 3: beda pulau / lintas pulau (15000)
  static const int tierDalamProvinsi = 1;
  static const int tierBedaProvinsi = 2;
  static const int tierLebihDari1Provinsi = 3;

  /// Ambil nama provinsi dari koordinat (administrativeArea).
  static Future<String?> getProvinceFromLatLng(double lat, double lng) async {
    try {
      final placemarks = await GeocodingService.placemarkFromCoordinates(lat, lng);
      if (placemarks.isEmpty) return null;
      final area = placemarks.first.administrativeArea;
      return area?.trim().isNotEmpty == true ? area : null;
    } catch (_) {
      return null;
    }
  }

  /// Tentukan tier berdasarkan provinsi asal (pickup) dan tujuan (receiver).
  /// [originLat], [originLng]: titik jemput barang (pengirim/pickup).
  /// [destLat], [destLng]: lokasi penerima.
  /// Return: (tier, feeRupiah). Tier 1 = sama provinsi, 2 = beda provinsi (satu pulau), 3 = beda pulau.
  static Future<(int tier, int feeRupiah)> getTierAndFee({
    required double originLat,
    required double originLng,
    required double destLat,
    required double destLng,
  }) async {
    final originProvince = await getProvinceFromLatLng(originLat, originLng);
    final destProvince = await getProvinceFromLatLng(destLat, destLng);

    int tier = tierBedaProvinsi; // default
    if (originProvince != null && destProvince != null) {
      if (originProvince == destProvince) {
        tier = tierDalamProvinsi;
      } else {
        final originIsland = ProvinceIsland.getIslandForProvince(originProvince);
        final destIsland = ProvinceIsland.getIslandForProvince(destProvince);
        tier = (originIsland != null && destIsland != null && originIsland != destIsland)
            ? tierLebihDari1Provinsi
            : tierBedaProvinsi;
      }
    }

    final fee = await AppConfigService.getLacakBarangFeeRupiah(tier);
    return (tier, fee);
  }

  /// Product ID untuk IAP. ID lama (traka_lacak_barang_10000 dll) tidak bisa dipakai jika pernah dihapus di Play Console.
  static String productIdForFee(int feeRupiah) {
    if (feeRupiah == 10000) return 'traka_lacak_barang_10k';
    if (feeRupiah == 15000) return 'traka_lacak_barang_15k';
    if (feeRupiah == 25000) return 'traka_lacak_barang_25k';
    return 'traka_lacak_barang_$feeRupiah';
  }
}
