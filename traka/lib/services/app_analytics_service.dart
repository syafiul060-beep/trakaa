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
        'method':? method,
      },
    );
  }

  /// Log saat login gagal.
  static void logLoginFailed({String? reason}) {
    _analytics.logEvent(
      name: 'login_failed',
      parameters: {
        'reason':? reason,
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
        'role':? role,
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

  /// Tap saluran di dialog kontak admin (email, whatsapp, instagram, live_chat).
  static void logAdminContactChannelTap({required String channel}) {
    _analytics.logEvent(
      name: 'admin_contact_channel_tap',
      parameters: {'channel': channel},
    );
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

  /// Re-route / fetch rute dengan steps (utama, penumpang, atau tujuan).
  /// [scope]: `main` | `to_passenger` | `to_destination`
  static void logDriverNavRouteFetch({
    required String scope,
    required bool success,
    required int latencyMs,
    String? errorKey,
    bool staleCache = false,
  }) {
    _analytics.logEvent(
      name: 'driver_nav_route_fetch',
      parameters: {
        'scope': scope,
        'success': success.toString(),
        'latency_ms': latencyMs.clamp(0, 120000),
        if (errorKey != null && errorKey.isNotEmpty) 'error': errorKey,
        'stale_cache': staleCache.toString(),
      },
    );
  }

  /// Proyeksi GPS ke polyline untuk indeks step gagal (250m & 420m).
  static void logDriverNavTbtProjectionFail() {
    _analytics.logEvent(name: 'driver_nav_tbt_projection_fail');
  }

  /// Hemat data navigasi diaktifkan/nonaktifkan dari profil driver.
  static void logDriverNavDataSaverToggle({required bool enabled}) {
    _analytics.logEvent(
      name: 'driver_nav_data_saver',
      parameters: {'enabled': enabled.toString()},
    );
  }

  /// Banner «penumpang dekat titik jemput» di beranda driver.
  /// [action]: `shown` | `navigate` | `dismiss`
  static void logDriverPickupNearbyBanner({
    required String action,
    int? distanceMeters,
  }) {
    String? bucket;
    final d = distanceMeters;
    if (d != null) {
      if (d <= 200) {
        bucket = '0_200m';
      } else if (d <= 500) {
        bucket = '201_500m';
      } else {
        bucket = '501m_plus';
      }
    }
    _analytics.logEvent(
      name: 'driver_pickup_nearby_banner',
      parameters: {
        'action': action,
        'distance_bucket':? bucket,
      },
    );
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
  /// [firestoreCapHit]: true jika query Firestore memakai plafon dokumen (potensi subset acak).
  static void logPassengerActiveDriversSource({
    required String source,
    String? reason,
    int resultCount = 0,
    bool firestoreCapHit = false,
  }) {
    final r = reason == null || reason.isEmpty
        ? null
        : (reason.length > 99 ? reason.substring(0, 99) : reason);
    _analytics.logEvent(
      name: 'passenger_active_drivers_source',
      parameters: {
        'source': source,
        'result_count': resultCount.clamp(0, 500).toString(),
        'reason':? r,
        'fs_cap':? (firestoreCapHit ? '1' : null),
      },
    );
  }

  /// Driver mengetuk shortcut penjemputan/pengantaran saat belum ada aksi (SnackBar edukasi).
  /// [shortcut]: `pickup` | `dropoff` — [reason]: `no_agreed_pickups` | `need_pickup_first` | `no_flow_yet`
  static void logDriverStopShortcutEducationalTap({
    required String shortcut,
    required String reason,
  }) {
    _analytics.logEvent(
      name: 'driver_stop_shortcut_educational_tap',
      parameters: {
        'shortcut': shortcut,
        'reason': reason,
      },
    );
  }

  /// Tulis `driver_schedules` setelah UI optimistik — mulai satu job persist (antrean serial).
  static void logDriverJadwalPersistStart({required int scheduleCount}) {
    _analytics.logEvent(
      name: 'driver_jadwal_persist_start',
      parameters: {
        'schedule_count': scheduleCount.clamp(0, 500).toString(),
      },
    );
  }

  static void logDriverJadwalPersistSuccess({required int scheduleCount}) {
    _analytics.logEvent(
      name: 'driver_jadwal_persist_success',
      parameters: {
        'schedule_count': scheduleCount.clamp(0, 500).toString(),
      },
    );
  }

  /// [failureKind]: `timeout` | `error`
  static void logDriverJadwalPersistFail({
    required String failureKind,
    required int scheduleCount,
  }) {
    _analytics.logEvent(
      name: 'driver_jadwal_persist_fail',
      parameters: {
        'failure_kind': failureKind,
        'schedule_count': scheduleCount.clamp(0, 500).toString(),
      },
    );
  }

  /// Hybrid: `POST /api/driver/location` ditolak rate limit server (biasanya 429).
  static void logHybridDriverLocationRateLimited() {
    _analytics.logEvent(name: 'hybrid_driver_location_rate_limited');
  }

  // --- Tahap 4: CS & pemblokiran kebijakan (insight support / produk) ---

  /// User membuka dialog Hubungi Admin (ikon admin).
  static void logCsContactDialogOpen() {
    _analytics.logEvent(name: 'cs_contact_dialog_open');
  }

  /// Konten diblokir filter kebijakan (chat / saran).
  /// [channel]: `order_text` | `order_image_ocr` | `order_audio_policy` | `support_text` | `feedback_text`
  static void logChatPolicyBlocked({required String channel}) {
    _analytics.logEvent(
      name: 'chat_policy_blocked',
      parameters: {'channel': channel},
    );
  }

  /// Hapus order+chat dari daftar Pesan ditolak (aturan app atau Firestore).
  /// [bucket]: ringkas, mis. `not_participant` | `status_locked` | `travel_other_agreed` |
  /// `messages_failed` | `firestore_permission` | `network` | `not_found`
  static void logOrderChatDeleteBlocked({required String bucket}) {
    final b = bucket.length > 48 ? bucket.substring(0, 48) : bucket;
    _analytics.logEvent(
      name: 'order_chat_delete_blocked',
      parameters: {'bucket': b},
    );
  }

  /// User membuka bantuan Lacak dari sheet info.
  static void logLacakHelpOpen({String? audience}) {
    _analytics.logEvent(
      name: 'lacak_help_open',
      parameters: {'audience':? audience},
    );
  }
}
