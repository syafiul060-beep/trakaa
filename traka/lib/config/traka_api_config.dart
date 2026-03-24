/// Konfigurasi Traka Backend API (hybrid Redis + PostgreSQL).
///
/// **Aktif jika** `--dart-define=TRAKA_USE_HYBRID=true` **dan**
/// `--dart-define=TRAKA_API_BASE_URL=https://...` (lihat `scripts/run_hybrid.ps1` /
/// `scripts/build_hybrid.ps1`). Tanpa itu, app hanya memakai Firestore untuk
/// `driver_status` / matching (tetap aman, tapi tanpa Redis).
///
/// Fitur saat [isApiEnabled]: lokasi & status driver → API + dual-write Firestore;
/// matching penumpang → `/api/match/drivers` + fallback; lacak → polling API.
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

  /// Jika true, pembuatan order penumpang memakai `POST /api/orders` (dual-write server)
  /// dengan fallback Firestore bila API error (bukan 409/403/400).
  /// `--dart-define=TRAKA_CREATE_ORDER_VIA_API=true`
  static const bool createOrderViaApi = bool.fromEnvironment(
    'TRAKA_CREATE_ORDER_VIA_API',
    defaultValue: false,
  );

  static bool get shouldCreateOrderViaApi => isApiEnabled && createOrderViaApi;

  /// Apakah certificate pinning aktif (fingerprint terisi dan API enabled).
  static bool get isCertificatePinningEnabled =>
      isApiEnabled &&
      certificateSha256Fingerprint.trim().isNotEmpty;
}
