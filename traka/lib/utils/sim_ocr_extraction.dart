/// Ekstraksi nama & nomor SIM dari teks OCR (heuristik; konfirmasi user tetap di UI).
library;

import 'ktp_ocr_extraction.dart';

/// Kata yang sering muncul di SIM / sekitar nomor — bukan nama pemegang.
const Set<String> simOcrExtraNonNameKeywords = {
  'SURAT IZIN',
  'MENGEMUDI',
  'DRIVING',
  'LICENSE',
  'KELAS',
  'CLASS',
  'BERLAKU',
  'RANGKA',
  'MESIN',
  'CHASSIS',
  'POLISI',
  'POLRI',
  'NOMOR RANGKA',
  'NOMOR MESIN',
  'TINGGI',
  'BADAN',
};

class SimOcrExtraction {
  SimOcrExtraction._();

  static final RegExp _digitsStrict = RegExp(r'\b\d{12,16}\b');
  static final RegExp _digitsOcrLoose = RegExp(r'\b[0-9OIl]{12,16}\b');

  static Map<String, String?> extractNamaAndNomorSim(String ocrText) {
    return {
      'nama': KtpOcrExtraction.extractNamaOnly(
        ocrText,
        extraNonNameKeywords: simOcrExtraNonNameKeywords,
      ),
      'nomorSIM': _extractNomorSim(ocrText),
    };
  }

  /// Pilih nomor 12–16 digit dengan skor konteks baris (NOMOR/SIM vs rangka).
  static String? _extractNomorSim(String ocrText) {
    final lines = ocrText.split('\n');
    final scored = <String, int>{};

    void scoreNumber(String num, String line, int base) {
      var s = base;
      final u = line.toUpperCase();
      if (u.contains('NOMOR') && (u.contains('SIM') || u.contains('MENGEMUDI'))) {
        s += 25;
      } else if (u.contains('SIM') || u.contains('SURAT IZIN')) {
        s += 18;
      } else if (u.contains('NOMOR')) {
        s += 8;
      }
      if (u.contains('RANGKA') || u.contains('MESIN') || u.contains('CHASSIS')) {
        s -= 35;
      }
      if (RegExp(r'\d{1,2}\s*[-/.,]\s*\d{1,2}\s*[-/.,]\s*\d').hasMatch(line)) {
        s -= 12;
      }
      final prev = scored[num] ?? -999;
      if (s > prev) scored[num] = s;
    }

    for (final line in lines) {
      for (final m in _digitsStrict.allMatches(line)) {
        final n = m.group(0)!;
        scoreNumber(n, line, 15);
      }
      for (final m in _digitsOcrLoose.allMatches(line)) {
        final raw = m.group(0)!;
        final corrected = raw
            .replaceAll('O', '0')
            .replaceAll('I', '1')
            .replaceAll('l', '1');
        if (!RegExp(r'^\d{12,16}$').hasMatch(corrected)) continue;
        scoreNumber(corrected, line, 12);
      }
    }

    if (scored.isEmpty) {
      final m = _digitsStrict.firstMatch(ocrText.replaceAll(RegExp(r'\s+'), ' '));
      if (m != null) return m.group(0);
      final m2 = _digitsOcrLoose.firstMatch(ocrText.replaceAll(RegExp(r'\s+'), ' '));
      if (m2 != null) {
        return m2
            .group(0)!
            .replaceAll('O', '0')
            .replaceAll('I', '1')
            .replaceAll('l', '1');
      }
      return null;
    }

    return scored.entries.reduce((a, b) => a.value >= b.value ? a : b).key;
  }
}
