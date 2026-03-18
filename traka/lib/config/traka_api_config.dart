/// Konfigurasi Traka Backend API (hybrid Redis + PostgreSQL).
///
/// Set [useHybrid] = true untuk mengalihkan driver_status ke API.
/// Set [apiBaseUrl] ke URL backend yang sudah di-deploy.
class TrakaApiConfig {
  TrakaApiConfig._();

  /// Base URL backend API (tanpa trailing slash).
  /// Contoh: https://traka-api.railway.app
  static const String apiBaseUrl = String.fromEnvironment(
    'TRAKA_API_BASE_URL',
    defaultValue: '',
  );

  /// Jika true, driver_status menggunakan API (Redis) bukan Firestore.
  /// Default false agar tidak mengganggu production.
  static const bool useHybrid = bool.fromEnvironment(
    'TRAKA_USE_HYBRID',
    defaultValue: false,
  );

  /// SHA-256 fingerprint sertifikat API untuk certificate pinning.
  /// Format: 'AA:BB:CC:...' (dari openssl x509 -noout -fingerprint -sha256).
  /// Kosong = pinning tidak aktif. Lihat docs/SETUP_CERTIFICATE_PINNING.md
  static const String certificateSha256Fingerprint = String.fromEnvironment(
    'TRAKA_API_CERT_SHA256',
    defaultValue: '',
  );

  /// Apakah API tersedia (base URL terisi dan hybrid aktif).
  static bool get isApiEnabled => apiBaseUrl.isNotEmpty && useHybrid;

  /// Apakah certificate pinning aktif (fingerprint terisi dan API enabled).
  static bool get isCertificatePinningEnabled =>
      isApiEnabled &&
      certificateSha256Fingerprint.trim().isNotEmpty;
}
