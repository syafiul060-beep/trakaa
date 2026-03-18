import 'package:flutter_test/flutter_test.dart';
import 'package:geocoding/geocoding.dart';

import 'package:traka/utils/placemark_formatter.dart';

void main() {
  group('PlacemarkFormatter', () {
    test('formatDetail returns "Lokasi dipilih" for empty placemark', () {
      const p = Placemark();
      expect(PlacemarkFormatter.formatDetail(p), 'Lokasi dipilih');
    });

    test('formatDetail returns name when only name is set', () {
      const p = Placemark(name: 'Toko ABC');
      expect(PlacemarkFormatter.formatDetail(p), 'Toko ABC');
    });

    test('formatDetail normalizes Jalan prefix', () {
      const p = Placemark(thoroughfare: 'Jalan Sudirman');
      expect(PlacemarkFormatter.formatDetail(p), 'Jl. Sudirman');
    });

    test('formatDetail adds Kec. prefix to locality', () {
      const p = Placemark(
        locality: 'Kecamatan Banjarmasin Tengah',
        administrativeArea: 'Kalimantan Selatan',
      );
      expect(
        PlacemarkFormatter.formatDetail(p),
        contains('Kec.'),
      );
    });

    test('formatShort returns "Lokasi saat ini" for empty placemark', () {
      const p = Placemark();
      expect(PlacemarkFormatter.formatShort(p), 'Lokasi saat ini');
    });

    test('formatShort includes locality and admin', () {
      const p = Placemark(
        locality: 'Banjarmasin Tengah',
        administrativeArea: 'Kalimantan Selatan',
      );
      final result = PlacemarkFormatter.formatShort(p);
      expect(result, contains('Kec.'));
      expect(result, contains('Kalimantan Selatan'));
    });
  });
}
