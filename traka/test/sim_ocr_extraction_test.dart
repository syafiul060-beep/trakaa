import 'package:flutter_test/flutter_test.dart';
import 'package:traka/utils/sim_ocr_extraction.dart';

void main() {
  group('SimOcrExtraction', () {
    test('prefers nomor on SIM line over rangka line', () {
      const ocr = '''
NOMOR RANGKA 12345678901234567
NOMOR SIM 12345678901234
NAMA
BUDI SANTOSO
''';
      final m = SimOcrExtraction.extractNamaAndNomorSim(ocr);
      expect(m['nomorSIM'], '12345678901234');
      expect(m['nama'], isNotNull);
      expect(m['nama']!.toUpperCase(), contains('BUDI'));
    });

    test('extracts nama with NAMA label', () {
      const ocr = '''
NAMA : ANDI PRATAMA
1234567890123456
''';
      final m = SimOcrExtraction.extractNamaAndNomorSim(ocr);
      expect(m['nomorSIM'], '1234567890123456');
      expect(m['nama'], 'ANDI PRATAMA');
    });
  });
}
