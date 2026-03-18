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

  /// Log saat pembayaran Lacak Driver (Rp 3000) selesai.
  static void logPaymentTrackDriver({required bool success}) {
    _analytics.logEvent(
      name: 'payment_track_driver',
      parameters: {'success': success.toString()},
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
}
