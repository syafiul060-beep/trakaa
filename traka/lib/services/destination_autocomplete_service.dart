import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../config/province_island.dart';
import 'geocoding_service.dart' show GeocodingService, Location, Placemark;

/// Konfigurasi untuk pencarian autocomplete tujuan.
class DestinationAutocompleteConfig {
  /// Bangun daftar query untuk geocode. Contoh: ["Bandung, Indonesia"] atau ["Bandung, Jabar, Indonesia", "Bandung, Indonesia"].
  final List<String> Function(String value) buildQueries;

  /// Urutkan hasil berdasarkan jarak dari titik ini. Null = tidak urutkan.
  final LatLng? sortByDistanceFrom;

  /// Filter provinsi: hanya tampilkan yang provinsinya ada di list (untuk sameIslandOnly).
  final List<String>? filterProvincesInIsland;

  /// Maksimal lokasi yang di-fetch dari geocode (sebelum placemark).
  final int maxLocations;

  /// Maksimal kandidat untuk placemark (driver: 25 jika sameIslandOnly, else 10).
  final int maxCandidates;

  /// Maksimal hasil placemark yang ditampilkan.
  final int maxDisplayCount;

  const DestinationAutocompleteConfig({
    required this.buildQueries,
    this.sortByDistanceFrom,
    this.filterProvincesInIsland,
    this.maxLocations = 20,
    this.maxCandidates = 10,
    this.maxDisplayCount = 10,
  });
}

/// Service untuk autocomplete tujuan (geocode + placemark).
/// Dipakai oleh [DestinationAutocompleteField] dan form rute driver/penumpang.
class DestinationAutocompleteService {
  DestinationAutocompleteService._();

  /// Cari lokasi dari teks, kembalikan list (Placemark, Location).
  /// [value] = teks yang diketik. [isStillCurrent] dipanggil saat async untuk cek apakah value belum berubah.
  static Future<List<(Placemark, Location)>> search(
    String value,
    DestinationAutocompleteConfig config, {
    bool Function()? isStillCurrent,
  }) async {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return [];

    final queries = config.buildQueries(trimmed);
    final allLocations = <Location>[];
    final seen = <String>{};

    for (final query in queries) {
      if (isStillCurrent != null && !isStillCurrent()) return [];
      try {
        final results = await GeocodingService.locationFromAddress(
          query,
          appendIndonesia: false,
        );
        for (final loc in results) {
          final key =
              '${loc.latitude.toStringAsFixed(4)},${loc.longitude.toStringAsFixed(4)}';
          if (!seen.contains(key)) {
            seen.add(key);
            allLocations.add(loc);
          }
          if (allLocations.length >= config.maxLocations) break;
        }
        if (allLocations.length >= config.maxLocations) break;
      } catch (_) {}
    }

    if (config.sortByDistanceFrom != null && allLocations.length > 1) {
      final from = config.sortByDistanceFrom!;
      allLocations.sort((a, b) {
        final da = Geolocator.distanceBetween(
          from.latitude,
          from.longitude,
          a.latitude,
          a.longitude,
        );
        final db = Geolocator.distanceBetween(
          from.latitude,
          from.longitude,
          b.latitude,
          b.longitude,
        );
        return da.compareTo(db);
      });
    }

    final placemarks = <Placemark>[];
    final locationsForPlacemarks = <Location>[];
    for (var i = 0;
        i < allLocations.length && i < config.maxCandidates;
        i++) {
      if (isStillCurrent != null && !isStillCurrent()) return [];
      final loc = allLocations[i];
      try {
        final list = await GeocodingService.placemarkFromCoordinates(
          loc.latitude,
          loc.longitude,
        );
        if (list.isNotEmpty) {
          final p = list.first;
          if (config.filterProvincesInIsland != null &&
              config.filterProvincesInIsland!.isNotEmpty) {
            final prov = p.administrativeArea ?? '';
            if (!ProvinceIsland.isProvinceInList(
              prov,
              config.filterProvincesInIsland!,
            )) {
              continue;
            }
          }
          placemarks.add(p);
          locationsForPlacemarks.add(loc);
          if (placemarks.length >= config.maxDisplayCount) break;
        }
      } catch (_) {}
    }

    return List.generate(
      placemarks.length,
      (i) => (placemarks[i], locationsForPlacemarks[i]),
    );
  }
}
