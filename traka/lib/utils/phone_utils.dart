/// Utility untuk normalisasi nomor telepon Indonesia ke format E.164 (+62...).
///
/// Mendukung format masukan: 08xx, 62xx, 8xx, +62xx.
library;

/// Konversi nomor Indonesia ke E.164 (+62...).
///
/// - `08xxxxxxxxx` → `+628xxxxxxxxx`
/// - `62xxxxxxxxxx` → `+62xxxxxxxxxx`
/// - `8xxxxxxxxxx` → `+628xxxxxxxxxx`
///
/// Input kosong atau hanya karakter non-digit mengembalikan string kosong.
/// Panggil [toE164OrNull] jika butuh null untuk input tidak valid.
String toE164(String input) {
  final digits = input.replaceAll(RegExp(r'\D'), '');
  if (digits.isEmpty) return '';
  if (digits.startsWith('0')) return '+62${digits.substring(1)}';
  if (!digits.startsWith('62')) return '+62$digits';
  return '+$digits';
}

/// Konversi ke E.164, mengembalikan null jika input tidak valid.
///
/// Valid: minimal 9 digit (setelah normalisasi).
/// - `08xxxxxxxxx` (10+ digit) → `+628xxxxxxxxx`
/// - `62xxxxxxxxxx` (11+ digit) → `+62xxxxxxxxxx`
/// - `8xxxxxxxxxx` (9+ digit) → `+628xxxxxxxxxx`
String? toE164OrNull(String input) {
  final digits = input.replaceAll(RegExp(r'\D'), '');
  if (digits.isEmpty || digits.length < 9) return null;
  if (digits.startsWith('62') && digits.length >= 11) return '+$digits';
  if (digits.startsWith('0') && digits.length >= 10) return '+62${digits.substring(1)}';
  if (digits.length >= 9) return '+62$digits';
  return null;
}
