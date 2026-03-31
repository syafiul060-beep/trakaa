import 'package:cloud_firestore/cloud_firestore.dart';

/// Konfigurasi kontak admin (email, WhatsApp, Instagram).
/// Dibaca dari Firestore app_config/admin_contact agar admin bisa mengubah.
class AdminContactConfigService {
  static const _collection = 'app_config';
  static const _docId = 'admin_contact';

  static String _adminEmail = 'CodeAnalytic9@gmail.com';
  static String _adminWhatsApp = '6282218115551';
  static String? _adminInstagram;
  static bool _loaded = false;

  static String get adminEmail => _adminEmail;
  static String get adminWhatsApp => _adminWhatsApp;
  static String? get adminInstagram => _adminInstagram;

  /// True jika nomor WhatsApp admin tersedia (buka jalur SOS WhatsApp).
  static bool get adminWhatsAppEnabled => _adminWhatsApp.trim().isNotEmpty;

  /// Muat konfigurasi dari Firestore. Fallback ke default jika belum ada.
  /// [force] true = baca ulang dari server (untuk SOS / dialog: hindari nomor WA usang setelah admin ubah di web).
  static Future<void> load({bool force = false}) async {
    if (_loaded && !force) return;
    try {
      final getOptions =
          force ? GetOptions(source: Source.server) : const GetOptions(source: Source.serverAndCache);
      final doc = await FirebaseFirestore.instance
          .collection(_collection)
          .doc(_docId)
          .get(getOptions);
      final d = doc.data();
      if (d != null) {
        final e = d['adminEmail'] as String?;
        final w = d['adminWhatsApp'] as String?;
        final i = d['adminInstagram'] as String?;
        if (e != null && e.isNotEmpty) _adminEmail = e.trim();
        if (w != null) {
          final t = w.trim();
          _adminWhatsApp = t.isNotEmpty ? _normalizeWhatsApp(t) : '';
        }
        if (i != null && i.isNotEmpty) {
          _adminInstagram = i.trim();
        } else if (d.containsKey('adminInstagram')) {
          _adminInstagram = null;
        }
      }
      _loaded = true;
    } catch (_) {}
  }

  static String _normalizeWhatsApp(String s) {
    final digits = s.replaceAll(RegExp(r'\D'), '');
    if (digits.startsWith('0')) return '62${digits.substring(1)}';
    if (!digits.startsWith('62')) return '62$digits';
    return digits;
  }

  /// Stream untuk update real-time (opsional)
  static Stream<Map<String, String?>> stream() {
    return FirebaseFirestore.instance
        .collection(_collection)
        .doc(_docId)
        .snapshots()
        .map((doc) {
      final d = doc.data();
      if (d != null) {
        final e = (d['adminEmail'] as String?)?.trim();
        if (e != null && e.isNotEmpty) _adminEmail = e;
        final wRaw = d['adminWhatsApp'];
        if (wRaw is String) {
          final t = wRaw.trim();
          _adminWhatsApp = t.isNotEmpty ? _normalizeWhatsApp(t) : '';
        }
        final ig = (d['adminInstagram'] as String?)?.trim();
        if (ig != null && ig.isNotEmpty) {
          _adminInstagram = ig;
        } else if (d.containsKey('adminInstagram')) {
          _adminInstagram = null;
        }
      }
      return {
        'email': _adminEmail,
        'whatsapp': _adminWhatsApp,
        'instagram': _adminInstagram,
      };
    });
  }
}
