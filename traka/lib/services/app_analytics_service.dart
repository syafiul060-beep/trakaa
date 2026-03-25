import 'package:firebase_analytics/firebase_analytics.dart';

/// Service untuk log event analytics (Firebase Analytics).
/// Mendukung keputusan fitur dan perbaikan jangka panjang.
class AppAnalyticsService {
  static final FirebaseAnalytics _analytics = FirebaseAnalytics.instance;

  /// Log saat pengguna membuka halaman Panduan.
  static void logPanduanOpen() {
    _analytics.logEvent(name: 'panduan_open');
  }

  /// Log saat pengguna membuka section tertentu di Panduan.
  static void logPanduanSectionView(String sectionName) {
    _analytics.logEvent(
      name: 'panduan_section_view',
      parameters: {'section': sectionName},
    );
  }

  /// Log saat pengguna mengirim saran ke admin.
  static void logFeedbackSubmit({required String type}) {
    _analytics.logEvent(
      name: 'feedback_submit',
      parameters: {'type': type},
    );
  }

  // --- Tahap 2: Custom events untuk monitoring flow kritis ---

  /// Log saat login berhasil.
  static void logLoginSuccess({String? method}) {
    _analytics.logEvent(
      name: 'login_success',
      parameters: {
        if (method != null) 'method': method,
      },
    );
  }

  /// Log saat login gagal.
  static void logLoginFailed({String? reason}) {
    _analytics.logEvent(
      name: 'login_failed',
      parameters: {
        if (reason != null) 'reason': reason,
      },
    );
  }

  /// Log saat order berhasil dibuat.
  static void logOrderCreated({
    required String orderType,
    required bool success,
  }) {
    _analytics.logEvent(
      name: 'order_created',
      parameters: {
        'order_type': orderType,
        'success': success.toString(),
      },
    );
  }

  /// Estimasi jarak/kontribusi di pesan pertama (pesanan terjadwal + geocode).
  /// [outcome]: `numeric` | `fallback_geocode` | `unavailable_short` | `empty_address` | `timeout` | `error`
  static void logChatEstimateScheduledResult({required String outcome}) {
    _analytics.logEvent(
      name: 'chat_estimate_scheduled',
      parameters: {'outcome': outcome},
    );
  }

  /// Log saat pembayaran Lacak Driver (Rp 3000) selesai.
  static void logPaymentTrackDriver({required bool success}) {
    _analytics.logEvent(
      name: 'payment_track_driver',
      parameters: {'success': success.toString()},
    );
  }

  /// Verifikasi server (Cloud Function) menolak pembayaran — mismatch SKU/nominal atau kewajiban.
  static void logPaymentVerifyRejected({
    required String flow,
    String? detail,
  }) {
    _analytics.logEvent(
      name: 'payment_verify_rejected',
      parameters: {
        'flow': flow,
        if (detail != null && detail.isNotEmpty)
          'detail': detail.length > 100 ? detail.substring(0, 100) : detail,
      },
    );
  }

  /// Log saat pembayaran Lacak Barang selesai.
  static void logPaymentLacakBarang({
    required bool success,
    required String payerType,
  }) {
    _analytics.logEvent(
      name: 'payment_lacak_barang',
      parameters: {
        'success': success.toString(),
        'payer_type': payerType,
      },
    );
  }

  /// Log saat registrasi berhasil.
  static void logRegisterSuccess({String? role}) {
    _analytics.logEvent(
      name: 'register_success',
      parameters: {
        if (role != null) 'role': role,
      },
    );
  }

  /// Log saat penumpang mencari driver: via "Driver sekitar" atau "Cari dengan rute".
  static void logPassengerSearchDriver({required String mode}) {
    _analytics.logEvent(
      name: 'passenger_search_driver',
      parameters: {'mode': mode},
    );
  }

  /// Hasil pencarian driver di beranda penumpang (untuk tuning filter rute vs data driver).
  /// [outcome]: `route_search_ok` | `route_search_empty` | `route_search_directions_all_failed` |
  /// `nearby_search_ok` | `nearby_search_empty` | `nearby_fallback_from_route` | …
  /// [driverCount]: jumlah driver di peta setelah filter (opsional, untuk funnel).
  /// [searchMode]: `route` | `nearby` | `prefill` (opsional).
  static void logPassengerDriverSearchOutcome({
    required String outcome,
    int? driverCount,
    String? searchMode,
  }) {
    _analytics.logEvent(
      name: 'passenger_driver_search_outcome',
      parameters: {
        'outcome': outcome,
        if (driverCount != null) 'driver_count': driverCount.clamp(0, 99).toString(),
        if (searchMode != null && searchMode.isNotEmpty) 'search_mode': searchMode,
      },
    );
  }

  /// Overlay beranda penumpang diblokir (travel agreed/picked_up).
  /// [action]: `shown` (pertama kali terdeteksi) | `open_orders` (tombol Buka Pesanan).
  static void logPassengerHomeTravelBlock({required String action}) {
    _analytics.logEvent(
      name: 'passenger_home_travel_block',
      parameters: {'action': action},
    );
  }

  /// Log saat OCR dokumen (KTP/SIM/STNK) gagal.
  static void logOcrFailed({
    required String documentType,
    required String reason,
  }) {
    _analytics.logEvent(
      name: 'ocr_failed',
      parameters: {
        'document_type': documentType,
        'reason': reason,
      },
    );
  }

  // --- Peta penumpang: tap driver & ETA sheet ---

  static String _shortUid(String uid) =>
      uid.length > 36 ? uid.substring(0, 36) : uid;

  /// Penumpang mengetuk marker driver di peta.
  static void logPassengerDriverMarkerTap({
    required String driverUid,
    required bool recommended,
  }) {
    _analytics.logEvent(
      name: 'passenger_driver_marker_tap',
      parameters: {
        'driver_uid': _shortUid(driverUid),
        'recommended': recommended.toString(),
      },
    );
  }

  /// Layar Profil → Notifikasi dibuka.
  static void logNotificationSettingsOpen() {
    _analytics.logEvent(name: 'notification_settings_open');
  }

  /// Pengguna mengetuk buka pengaturan notifikasi sistem.
  static void logNotificationSettingsSystemTap() {
    _analytics.logEvent(name: 'notification_settings_system_tap');
  }

  /// Notifikasi lokal jarak tampil (`flutter_local_notifications`) — funnel & anti-spam tuning.
  /// [flow]: `passenger_pickup` | `receiver_goods`; [band]: `500m` | `1km`.
  static void logLocalProximityNotificationShown({
    required String flow,
    required String band,
  }) {
    _analytics.logEvent(
      name: 'local_proximity_notif_shown',
      parameters: {
        'flow': flow,
        'band': band,
      },
    );
  }

  /// Bottom sheet detail driver ditutup (swipe / tombol / navigasi).
  static void logPassengerDriverSheetClosed({required int durationMs}) {
    _analytics.logEvent(
      name: 'passenger_driver_sheet_closed',
      parameters: {'duration_ms': durationMs.clamp(0, 86400000)},
    );
  }

  /// Directions dengan steps memakai snapshot (kuota/jaringan) saat navigasi driver.
  static void logDriverNavigationDirectionsStale() {
    _analytics.logEvent(name: 'driver_nav_directions_stale_cache');
  }

  /// Driver tidak bisa menyelesaikan kerja (order aktif / di dekat tujuan rute).
  /// [surface]: `snackbar` | `near_dest`
  /// [bucket]: `both` | `passengers` | `goods` | `pending_unknown`
  static void logDriverFinishWorkBlocked({
    required String surface,
    required String bucket,
  }) {
    _analytics.logEvent(
      name: 'driver_finish_work_blocked',
      parameters: {
        'surface': surface,
        'bucket': bucket,
      },
    );
  }

  /// Penumpang melihat dialog duplikat pra-sepakat (travel / kirim barang).
  /// [orderKind]: `travel` | `kirim_barang`
  /// [choice]: `open_existing` | `force_new` | `cancel`
  /// [surface]: `map_home` | `cari_travel` | `scheduled_pesan` | `jadwal_kirim_sheet`
  static void logPassengerDuplicatePendingDialog({
    required String orderKind,
    required String choice,
    required String surface,
  }) {
    _analytics.logEvent(
      name: 'passenger_duplicate_pending_dialog',
      parameters: {
        'order_kind': orderKind,
        'choice': choice,
        'surface': surface,
      },
    );
  }

  /// ETA driver→penumpang selesai dihitung (Directions).
  static void logPassengerDriverEtaLoaded({
    required int durationMs,
    required bool success,
    bool staleCache = false,
  }) {
    _analytics.logEvent(
      name: 'passenger_driver_eta_loaded',
      parameters: {
        'duration_ms': durationMs.clamp(0, 600000),
        'success': success.toString(),
        'stale_cache': staleCache.toString(),
      },
    );
  }

  /// Sumber data driver aktif (Cari travel): pantau fallback Firestore vs Redis/geo.
  /// [source]: `geo_match` | `api_list` | `firestore`
  static void logPassengerActiveDriversSource({
    required String source,
    String? reason,
    int resultCount = 0,
  }) {
    final r = reason == null || reason.isEmpty
        ? null
        : (reason.length > 99 ? reason.substring(0, 99) : reason);
    _analytics.logEvent(
      name: 'passenger_active_drivers_source',
      parameters: {
        'source': source,
        'result_count': resultCount.clamp(0, 500).toString(),
        if (r != null) 'reason': r,
      },
    );
  }
}
