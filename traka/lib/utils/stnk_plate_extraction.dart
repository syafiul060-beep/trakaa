/// Ekstraksi nomor polisi Indonesia dari teks OCR STNK (heuristik).
library;

import 'dart:math' as math;

/// Satu kandidat plat dengan skor (lebih tinggi = lebih dipercaya).
class ScoredPlate {
  const ScoredPlate(this.plat, this.score);

  final String plat;
  final int score;
}

/// Logika murni teks — dipakai [StnkScanService] setelah ML Kit OCR.
class StnkPlateExtraction {
  StnkPlateExtraction._();

  static final RegExp _strictSpaced = RegExp(
    r'[A-Z]{1,2}\s+[0-9]{1,4}\s+[A-Z]{1,3}',
    caseSensitive: false,
  );
  static final RegExp _strictTight = RegExp(
    r'[A-Z]{1,2}[0-9]{1,4}[A-Z]{1,3}',
    caseSensitive: false,
  );
  static final RegExp _ocrLoose = RegExp(
    r'[A-Z]{1,2}[A-Z0-9]{1,4}[A-Z0-9]{1,3}',
    caseSensitive: false,
  );

  /// Baris yang hampir pasti bukan plat (nomor rangka/mesin, spesifikasi).
  static const List<String> _badLineHints = [
    'RANGKA',
    'MESIN',
    'CHASSIS',
    'NOMOR MESIN',
    'NOMOR RANGKA',
    'NO MESIN',
    'NO RANGKA',
    'NO. MESIN',
    'NO. RANGKA',
    'SILINDER',
    'ISI SILINDER',
    'BBM',
    'TYPE',
    'MODEL KENDARAAN',
    'JENIS',
    'DAYA',
    'WARNA',
    'MASA BERLAKU',
    'BERLAKU SAMPAI',
    'TNKB LAMA',
    'BERAT',
    'MUATAN',
    'JUMLAH',
    'SUMBU',
    'TAHUN PEMBUATAN',
    'ISI SILINDER',
  ];

  /// Baris yang sering memuat plat resmi.
  static const List<String> _goodLineHints = [
    'NOPOL',
    'NO.POL',
    'NO POL',
    'NOMOR POLISI',
    'NOMOR REGISTRASI',
    'NOMOR REG',
    'REGISTRASI',
    'POLISI',
    'TNKB',
    'PLAT',
    'NOMOR TNKB',
  ];

  static String normalizePlateKey(String plat) {
    return plat
        .trim()
        .replaceAll(RegExp(r'\s+'), ' ')
        .toUpperCase();
  }

  /// True jika baris sebaiknya diabaikan (hanya nomor rangka/mesin/dll.).
  static bool isLineIgnoredForPlate(String line) {
    final u = line.toUpperCase();
    var hasBad = false;
    for (final k in _badLineHints) {
      if (u.contains(k)) {
        hasBad = true;
        break;
      }
    }
    if (!hasBad) return false;
    for (final k in _goodLineHints) {
      if (u.contains(k)) return false;
    }
    return true;
  }

  static int _lineContextScore(String line) {
    final u = line.toUpperCase();
    var s = 0;
    for (final k in _goodLineHints) {
      if (u.contains(k)) s += 18;
    }
    for (final k in _badLineHints) {
      if (u.contains(k)) s -= 22;
    }
    return s;
  }

  /// Kumpulkan semua kandidat dari satu potongan teks (satu baris atau blok).
  static List<ScoredPlate> extractScored(String? text, {String? lineContext}) {
    if (text == null || text.isEmpty) return [];

    final forIgnore = lineContext ?? text;
    // Hanya abaikan baris tunggal (bukan gabungan beberapa baris OCR).
    if (!forIgnore.contains('\n') && isLineIgnoredForPlate(forIgnore)) {
      return [];
    }

    final normalized = text.replaceAll(RegExp(r'\s+'), ' ').trim().toUpperCase();
    if (normalized.isEmpty) return [];

    final ctx = _lineContextScore(lineContext ?? text);
    final byKey = <String, int>{};

    void add(String? plat, int baseScore) {
      if (plat == null || plat.length < 5) return;
      final key = normalizePlateKey(plat);
      if (key.length < 5) return;
      final sc = baseScore + ctx;
      byKey[key] = math.max(byKey[key] ?? 0, sc);
    }

    for (final m in _strictSpaced.allMatches(normalized)) {
      var plat = m.group(0)!;
      plat = _formatPlatWithSpaces(plat.replaceAll(' ', ''));
      add(plat, 22);
    }
    for (final m in _strictTight.allMatches(normalized)) {
      final plat = _formatPlatWithSpaces(m.group(0)!);
      add(plat, 20);
    }
    for (final m in _ocrLoose.allMatches(normalized)) {
      final corrected = _tryOcrCorrectPlat(m.group(0)!);
      add(corrected, 14);
    }

    final words = normalized.split(' ');
    for (var i = 0; i < words.length - 2; i++) {
      final a = words[i];
      final b = words[i + 1];
      final c = words[i + 2];
      if (_isRegionCode(a) && _isDigits(b) && _isSuffix(c)) {
        add('$a $b $c', 16);
      }
    }

    return byKey.entries
        .map((e) => ScoredPlate(e.key, e.value))
        .toList();
  }

  /// Pilih plat dengan skor tertinggi; imbang urutkan panjang (lebih lengkap).
  static String? pickBest(List<ScoredPlate> plates) {
    if (plates.isEmpty) return null;
    plates.sort((a, b) {
      final c = b.score.compareTo(a.score);
      if (c != 0) return c;
      return b.plat.length.compareTo(a.plat.length);
    });
    return plates.first.plat;
  }

  static bool _isRegionCode(String s) =>
      s.isNotEmpty && s.length <= 2 && RegExp(r'^[A-Z]+$').hasMatch(s);
  static bool _isDigits(String s) =>
      s.isNotEmpty && s.length <= 4 && RegExp(r'^[0-9]+$').hasMatch(s);
  static bool _isSuffix(String s) =>
      s.isNotEmpty && s.length <= 3 && RegExp(r'^[A-Z]+$').hasMatch(s);

  static String _formatPlatWithSpaces(String plat) {
    final noSpace = plat.replaceAll(RegExp(r'\s+'), '').toUpperCase();
    final m = RegExp(r'^([A-Z]{1,2})([0-9]{1,4})([A-Z]{1,3})$').firstMatch(noSpace);
    if (m != null) {
      return '${m.group(1)} ${m.group(2)} ${m.group(3)}';
    }
    return plat.trim();
  }

  static String? _tryOcrCorrectPlat(String raw) {
    final noSpace = raw.replaceAll(RegExp(r'\s+'), '').toUpperCase();
    final m = RegExp(r'^([A-Z]{1,2})([A-Z0-9]{1,4})([A-Z0-9]{1,3})$').firstMatch(noSpace);
    if (m == null) return null;

    final prefix = m.group(1)!;
    final digits = m.group(2)!;
    final suffix = m.group(3)!;

    final digitCorrected = digits
        .replaceAll('O', '0')
        .replaceAll('I', '1')
        .replaceAll('L', '1')
        .replaceAll('B', '8')
        .replaceAll('S', '5')
        .replaceAll('G', '6')
        .replaceAll('Z', '2');

    final suffixCorrected = suffix
        .replaceAll('0', 'O')
        .replaceAll('1', 'I')
        .replaceAll('8', 'B');

    if (!RegExp(r'^[0-9]{1,4}$').hasMatch(digitCorrected)) return null;
    if (!RegExp(r'^[A-Z]{1,3}$').hasMatch(suffixCorrected)) return null;

    return '$prefix $digitCorrected $suffixCorrected';
  }
}
