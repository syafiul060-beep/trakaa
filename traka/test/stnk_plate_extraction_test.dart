import 'package:flutter_test/flutter_test.dart';
import 'package:traka/utils/stnk_plate_extraction.dart';

void main() {
  group('StnkPlateExtraction', () {
    test('prefers plat on registration line over rangka line', () {
      const ocr = '''
NOMOR RANGKA MH1234567890ABCDEF
NOMOR REGISTRASI B 1234 XYZ
''';
      final lines = ocr.split('\n').map((e) => e.trim()).where((e) => e.isNotEmpty);
      final all = <ScoredPlate>[];
      for (final line in lines) {
        if (StnkPlateExtraction.isLineIgnoredForPlate(line)) continue;
        all.addAll(StnkPlateExtraction.extractScored(line, lineContext: line));
      }
      expect(StnkPlateExtraction.pickBest(all), 'B 1234 XYZ');
    });

    test('ignores line that is only rangka/mesin', () {
      const line = 'NOMOR MESIN AB1234567890';
      expect(StnkPlateExtraction.isLineIgnoredForPlate(line), isTrue);
      expect(StnkPlateExtraction.extractScored(line, lineContext: line), isEmpty);
    });

    test('extracts tight format B1234ABC', () {
      final list = StnkPlateExtraction.extractScored('STNK B1234ABC JAKARTA');
      expect(StnkPlateExtraction.pickBest(list), 'B 1234 ABC');
    });

    test('registration keyword boosts correct plat when two patterns exist', () {
      const line = 'REGISTRASI AD 5678 GH';
      final list = StnkPlateExtraction.extractScored(line, lineContext: line);
      expect(StnkPlateExtraction.pickBest(list), 'AD 5678 GH');
    });
  });
}
