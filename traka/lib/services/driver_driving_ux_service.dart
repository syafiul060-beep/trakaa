/// Konteks UX saat driver fokus mengemudi / navigasi — dipakai FCM, snack, dan deep link notifikasi.
///
/// Aturan ringkas: lihat [docs/DRIVER_DRIVING_UX_POLICY.md].
class DriverDrivingUxService {
  DriverDrivingUxService._();

  static bool _navigatingToOrder = false;
  static bool _turnByTurnChrome = false;

  /// Dipanggil dari [DriverScreen] setiap frame profil (setelah state navigasi terbaru).
  static void syncDriverMapState({
    required bool navigatingToOrder,
    required bool turnByTurnChromeVisible,
  }) {
    _navigatingToOrder = navigatingToOrder;
    _turnByTurnChrome = turnByTurnChromeVisible;
  }

  /// Saat app ke background: anggap tidak ada konteks TBT di foreground (notifikasi boleh bersuara).
  static void clearForegroundDrivingContext() {
    _navigatingToOrder = false;
    _turnByTurnChrome = false;
  }

  /// Perjalanan ke stop / banner TBT aktif — hindari interupsi penuh (dialog/snack/tab push chat).
  static bool get isHighAttentionDriving =>
      _navigatingToOrder || _turnByTurnChrome;

  /// Notifikasi chat/pesanan di foreground: tanpa suara/getar agar tidak bentrok dengan TTS navigasi.
  static bool get foregroundChatOrderShouldBeQuiet => isHighAttentionDriving;
}
