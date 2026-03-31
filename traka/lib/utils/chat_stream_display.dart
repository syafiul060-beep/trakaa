import '../models/chat_message_model.dart';

/// Logika tampilan chat: tahan sementara daftar terakhir saat stream Firestore
/// mengirim snapshot kosong mendadak (reconnect / metadata), supaya UI tidak berkedip.
class ChatStreamDisplay {
  ChatStreamDisplay._();

  /// Lama mempertahankan daftar terakhir setelah stream mengatakan kosong.
  /// Diperpanjang: burst Firestore setelah transaksi kesepakatan bisa >4 dtk.
  static const Duration transientHoldTtl = Duration(seconds: 12);

  /// True jika [streamMsgs] kosong tetapi kita masih boleh menampilkan [hold].
  static bool shouldApplyTransientHold({
    required List<ChatMessageModel> streamMsgs,
    required bool hasError,
    required bool waitingFirst,
    required List<ChatMessageModel>? hold,
    required DateTime? holdAt,
    DateTime? now,
  }) {
    final clock = now ?? DateTime.now();
    if (streamMsgs.isNotEmpty) return false;
    if (hasError) return false;
    // Hanya blokir "waiting" saat belum pernah punya daftar (muat awal).
    // Jika sudah ada hold — mis. setelah setuju kesepakatan / burst Firestore —
    // stream bisa sesaat waiting tanpa data; tetap tampilkan hold agar body tidak kosong.
    if (waitingFirst && (hold == null || hold.isEmpty)) return false;
    if (hold == null || hold.isEmpty) return false;
    if (holdAt == null) return false;
    return clock.difference(holdAt) <= transientHoldTtl;
  }
}
