import 'package:flutter/foundation.dart';

/// Untuk mode hybrid (API + Firestore), antrean jaringan kadang membuat UI "nyangkut"
/// sampai aplikasi ditutup. Sinyal ini memicu **penyegaran halus** di layar yang mendengarkan
/// (baca server ringan, bukan spinner global) setelah driver cukup lama di background.
///
/// - [tick]: jadwal + chat bisa memuat ulang data setelah **≥3 detik** di background, atau saat
///   buka tab Jadwal/Chat (debounce). **Bukan** polling tiap detik.
/// - [manualSyncAllTick]: dari Profil → "Sinkronkan data" / semisal: naikkan refresh Data Order + tick.
class HybridForegroundRecovery {
  HybridForegroundRecovery._();

  /// Durasi paused→resumed dari siklus terakhir (untuk kebijakan per layar).
  static Duration lastBackgroundDuration = Duration.zero;

  static final ValueNotifier<int> tick = ValueNotifier<int>(0);

  /// Di-prof driver: "Sinkronkan data" — parent [DriverScreen] naikkan refresh Data Order.
  static final ValueNotifier<int> manualSyncAllTick = ValueNotifier<int>(0);

  static int _lastSignalMs = 0;
  static int _lastTabSwitchSignalMs = 0;

  /// Set true pada [signalTabBecameVisible] index 2; konsumsi sekali oleh Chat.
  static bool _pendingChatTabSoftResync = false;

  /// Panggil dari [DriverScreen] saat lifecycle [AppLifecycleState.resumed].
  static void signalAfterBackground({required Duration backgroundDuration}) {
    lastBackgroundDuration = backgroundDuration;
    if (backgroundDuration < const Duration(seconds: 3)) {
      return;
    }
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - _lastSignalMs < 1500) {
      return;
    }
    _lastSignalMs = now;
    tick.value = tick.value + 1;
  }

  /// Panggil dari bottom navigation saat user membuka tab Jadwal (1) atau Chat (2).
  /// Memicu penyegaran halus tanpa minimize app — debounce antar tap cepat.
  static void signalTabBecameVisible(int index) {
    if (index != 1 && index != 2) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - _lastTabSwitchSignalMs < 3500) {
      return;
    }
    _lastTabSwitchSignalMs = now;
    if (index == 2) {
      _pendingChatTabSoftResync = true;
    }
    tick.value = tick.value + 1;
  }

  static bool takeChatTabSoftResyncPending() {
    final v = _pendingChatTabSoftResync;
    _pendingChatTabSoftResync = false;
    return v;
  }

  /// Dari Profil driver: segarkan jadwal (tick), chat, dan indikator order tanpa tutup app.
  static void requestManualDriverSyncAll() {
    lastBackgroundDuration = const Duration(seconds: 8);
    _pendingChatTabSoftResync = true;
    manualSyncAllTick.value = manualSyncAllTick.value + 1;
    tick.value = tick.value + 1;
  }
}
