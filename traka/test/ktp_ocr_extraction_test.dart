import 'package:flutter_test/flutter_test.dart';
import 'package:traka/utils/ktp_ocr_extraction.dart';

void main() {
  group('KtpOcrExtraction', () {
    test('extracts NIK and name from typical OCR block', () {
      const ocr = '''
PROVINSI DKI JAKARTA
NIK : 3171234567890123
NAMA : BUDI SANTOSO
TEMPAT/TGL LAHIR : JAKARTA, 15-08-1990
''';
      final r = KtpOcrExtraction.extract(ocr);
      expect(r.nik, '3171234567890123');
      expect(r.nama, 'BUDI SANTOSO');
    });

    test('does not use TTL line as name when NAMA label missing', () {
      const ocr = '''
NIK 3171234567890123
JAKARTA, 15-08-1990
BUDI SANTOSO
''';
      final r = KtpOcrExtraction.extract(ocr);
      expect(r.nik, '3171234567890123');
      expect(r.nama, isNot(contains('1990')));
      expect(r.nama, 'BUDI SANTOSO');
    });

    test('rejects birth line with date pattern as name', () {
      const ocr = '''
NIK 3171234567890123
TEMPAT/TGL LAHIR
JAKARTA, 01-01-1990
NAMA
ANDI Wijaya
''';
      final r = KtpOcrExtraction.extract(ocr);
      expect(r.nama, 'ANDI Wijaya');
    });

    test('tolerates MAMA OCR typo on label line', () {
      const ocr = '''
MAMA : SITI NURHALIZA
NIK 3171234567890123
''';
      final r = KtpOcrExtraction.extract(ocr);
      expect(r.nama, 'SITI NURHALIZA');
      expect(r.nik, '3171234567890123');
    });

    test('strips trailing date merged on name line', () {
      const ocr = '''
NAMA: AHMAD RIZKI, 10-05-1988
NIK 3171234567890123
''';
      final r = KtpOcrExtraction.extract(ocr);
      expect(r.nama, 'AHMAD RIZKI');
    });
  });
}
