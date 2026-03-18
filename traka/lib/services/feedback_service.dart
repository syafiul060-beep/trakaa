import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../utils/app_logger.dart';

/// Service untuk mengirim saran & masukan ke admin.
/// Data disimpan di Firestore app_feedback.
class FeedbackService {
  static const _collection = 'app_feedback';

  /// Maksimal saran per pengguna per 24 jam (anti-spam).
  static const int maxFeedbackPerDay = 5;

  /// Maksimal panjang teks saran (karakter).
  static const int maxTextLength = 1000;

  /// Hitung jumlah feedback user dalam 24 jam terakhir.
  static Future<int> getFeedbackCountLast24Hours(String userId) async {
    try {
      final since = DateTime.now().subtract(const Duration(hours: 24));
      final snap = await FirebaseFirestore.instance
          .collection(_collection)
          .where('userId', isEqualTo: userId)
          .where('createdAt', isGreaterThan: Timestamp.fromDate(since))
          .count()
          .get();
      return snap.count ?? 0;
    } catch (_) {
      return 0;
    }
  }

  /// Kirim saran/masukan dari pengguna.
  /// [text] isi feedback, [type] saran|masukan|keluhan.
  /// Return (success, errorMessage). errorMessage null jika sukses.
  static Future<(bool, String?)> submit({
    required String text,
    String type = 'saran',
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return (false, 'Sesi tidak valid.');
    final trimmed = text.trim();
    if (trimmed.isEmpty) return (false, 'Isi saran terlebih dahulu.');
    if (trimmed.length > maxTextLength) {
      return (false, 'Maksimal $maxTextLength karakter.');
    }

    final count = await getFeedbackCountLast24Hours(user.uid);
    if (count >= maxFeedbackPerDay) {
      return (false, 'Maksimal $maxFeedbackPerDay saran per hari. Coba lagi besok.');
    }

    try {
      await FirebaseFirestore.instance.collection(_collection).add({
        'text': trimmed,
        'type': type,
        'userId': user.uid,
        'userEmail': user.email,
        'userName': user.displayName,
        'source': 'app',
        'createdAt': FieldValue.serverTimestamp(),
      });
      return (true, null);
    } catch (e, st) {
      logError('FeedbackService.submit', e, st);
      return (false, 'Gagal mengirim. Coba lagi.');
    }
  }
}
