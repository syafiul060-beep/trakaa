/// Ekstraksi NIK & nama dari teks OCR KTP Indonesia (heuristik; bukan pengganti verifikasi manual).
library;

/// Hasil ekstraksi — nilai bisa null jika tidak terdeteksi.
class KtpOcrExtractResult {
  const KtpOcrExtractResult({this.nik, this.nama});

  final String? nik;
  final String? nama;

  Map<String, String?> toMap() => {'nik': nik, 'nama': nama};
}

/// Ekstrak NIK (16 digit) dan nama dari teks OCR.
/// Mendukung koreksi OCR digit: O↔0, I/l↔1.
/// Menghindari salah ambil baris tempat/tanggal lahir sebagai nama.
class KtpOcrExtraction {
  KtpOcrExtraction._();

  static final RegExp _nikDigits = RegExp(r'\b\d{16}\b');
  static final RegExp _nikOcrLoose = RegExp(r'\b[0-9OIl]{16}\b');

  /// Tanggal DD/MM/YYYY, DD-MM-YY, dll. (termasuk varian OCR).
  static final RegExp _dateLike = RegExp(
    r'\d{1,2}\s*[-/.,]\s*\d{1,2}\s*[-/.,]\s*\d{2,4}',
  );

  /// Substring yang sering muncul di baris TTL / alamat / header KTP — bukan nama orang.
  static const Set<String> _nonNameKeywords = {
    'PROVINSI',
    'KABUPATEN',
    'KOTA',
    'KECAMATAN',
    'KELURAHAN',
    'KEL/DESA',
    'DESA',
    'JENIS',
    'KELAMIN',
    'GOL',
    'DARAH',
    'STATUS',
    'PERKAWINAN',
    'ALAMAT',
    'RT/RW',
    'AGAMA',
    'PEKERJAAN',
    'KWARGANEGARAAN',
    'BERLAKU',
    'HINGGA',
    'RUMAH',
    'NIK',
    'KTP',
    'REPUBLIK',
    'INDONESIA',
  };

  static Map<String, String?> extractNikAndNama(String ocrText) {
    return extract(ocrText).toMap();
  }

  /// Hanya nama (tanpa NIK). Untuk SIM/dokumen lain: tambahkan [extraNonNameKeywords].
  static String? extractNamaOnly(
    String ocrText, {
    Set<String> extraNonNameKeywords = const {},
  }) {
    return _extractNama(ocrText, extraNonNameKeywords: extraNonNameKeywords);
  }

  static KtpOcrExtractResult extract(String ocrText) {
    final nik = _extractNik(ocrText);
    final nama = _extractNama(ocrText);
    return KtpOcrExtractResult(nik: nik, nama: nama);
  }

  static String? _extractNik(String ocrText) {
    var m = _nikDigits.firstMatch(ocrText);
    if (m != null) return m.group(0);
    m = _nikOcrLoose.firstMatch(ocrText);
    if (m == null) return null;
    return m
        .group(0)!
        .replaceAll('O', '0')
        .replaceAll('I', '1')
        .replaceAll('l', '1');
  }

  static String? _extractNama(
    String ocrText, {
    Set<String> extraNonNameKeywords = const {},
  }) {
    final lines = ocrText.split('\n').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();

    final fromLabel = _namaFromNamaLabel(lines, extraNonNameKeywords: extraNonNameKeywords);
    if (fromLabel != null && fromLabel.isNotEmpty) return fromLabel;

    for (final line in lines) {
      var candidate = line.trim();
      candidate = _cleanNameCandidate(candidate) ?? candidate;
      if (_isPlausibleKtpPersonName(candidate, extraNonNameKeywords: extraNonNameKeywords)) {
        return candidate;
      }
    }
    return null;
  }

  /// Cari baris label NAMA (toleransi OCR) lalu ambil nama di baris yang sama atau berikutnya.
  static String? _namaFromNamaLabel(
    List<String> lines, {
    Set<String> extraNonNameKeywords = const {},
  }) {
    for (var i = 0; i < lines.length; i++) {
      final raw = lines[i];
      final upper = raw.toUpperCase();
      if (!_lineContainsNamaLabel(upper)) continue;

      final afterLabel = _textAfterNamaLabel(raw);
      if (afterLabel != null && afterLabel.isNotEmpty) {
        var candidate = afterLabel.replaceFirst(RegExp(r'^[:\s.,]+'), '').trim();
        candidate = _cleanNameCandidate(candidate) ?? candidate;
        if (_isPlausibleKtpPersonName(candidate, extraNonNameKeywords: extraNonNameKeywords)) {
          return candidate;
        }
      }

      if (i + 1 < lines.length) {
        var next = lines[i + 1].trim();
        next = _cleanNameCandidate(next) ?? next;
        if (next.isNotEmpty &&
            _isPlausibleKtpPersonName(next, extraNonNameKeywords: extraNonNameKeywords)) {
          return next;
        }
      }
    }
    return null;
  }

  /// Label "NAMA" sering terbaca salah: MAMA (N→M), NAMA:, dll.
  static bool _lineContainsNamaLabel(String upperLine) {
    final u = upperLine.trim();
    if (u.contains('NAMA') || u.contains('NAME')) return true;
    // OCR: N depan terbaca M → baris "MAMA ..." sebagai label
    if (RegExp(r'^MAMA\b').hasMatch(u)) return true;
    final lettersOnly = u.replaceAll(RegExp(r'[^A-Z]'), '');
    if (lettersOnly.contains('NAMA')) return true;
    return false;
  }

  /// Ambil teks setelah kata "NAMA"/"NAME" pada baris yang sama.
  static String? _textAfterNamaLabel(String line) {
    final re = RegExp(r'(?:NAMA|NAME|MAMA)\s*[.:]?\s*', caseSensitive: false);
    final m = re.firstMatch(line);
    if (m == null) return null;
    final rest = line.substring(m.end).trim();
    return rest.isEmpty ? null : rest;
  }

  static bool _isLikelyBirthOrPlaceLine(String line) {
    final u = line.toUpperCase();
    if (u.contains('LAHIR') ||
        u.contains('TTL') ||
        u.contains('TEMPAT') && u.contains('LAHIR') ||
        u.contains('TANGGAL') && u.contains('LAHIR')) {
      return true;
    }
    if (u.contains('TEMPAT') && u.contains('TG')) return true;
    if (_dateLike.hasMatch(line)) return true;
    // "JAKARTA, 01-01-1990" atau koma sebelum pola tanggal
    if (RegExp(r',\s*\d{1,2}\s*[-/.,]\s*\d').hasMatch(line)) return true;
    return false;
  }

  /// Baris yang jelas bukan nama lengkap (alamat panjang dengan angka RT).
  static bool _isLikelyAddressLine(String line) {
    final u = line.toUpperCase();
    if (u.contains('RT') && u.contains('RW')) return true;
    if (RegExp(r'NO\.?\s*\d').hasMatch(line) && line.length > 30) return true;
    return false;
  }

  /// Nama wajar: cukup huruf, ≥2 kata, bukan baris TTL/tanggal/header.
  static bool _isPlausibleKtpPersonName(
    String line, {
    Set<String> extraNonNameKeywords = const {},
  }) {
    if (line.length < 3) return false;
    if (_isLikelyBirthOrPlaceLine(line)) return false;
    if (_isLikelyAddressLine(line)) return false;

    final upper = line.toUpperCase();
    for (final k in _nonNameKeywords) {
      if (upper.contains(k)) return false;
    }
    for (final k in extraNonNameKeywords) {
      if (upper.contains(k)) return false;
    }

    final words = line.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    if (words.length < 2 && line.length < 10) return false;

    if (RegExp(r'\d{10,}').hasMatch(line)) return false;

    // Terlalu banyak digit → bukan nama
    final digitCount = RegExp(r'\d').allMatches(line).length;
    final letterCount = RegExp(r'[A-Za-z]').allMatches(line).length;
    if (digitCount > 3) return false;
    if (letterCount < 4) return false;
    if (letterCount < digitCount * 2 && digitCount > 0) return false;

    // Pola tanggal tersebar di baris (OCR memecah)
    if (_dateLike.hasMatch(line)) return false;

    return true;
  }

  /// Buang sisa tanggal di akhir baris jika menyatu dengan nama.
  static String? _cleanNameCandidate(String? nama) {
    if (nama == null) return null;
    var t = nama.trim();
    t = t.replaceFirst(
      RegExp(
        r'\s*[,;]?\s*\d{1,2}\s*[-/.,]\s*\d{1,2}\s*[-/.,]\s*\d{2,4}\s*$',
      ),
      '',
    ).trim();
    return t.isEmpty ? null : t;
  }
}
