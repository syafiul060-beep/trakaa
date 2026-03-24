import 'traka_api_config.dart';

/// Konfigurasi Socket.IO realtime (worker Tahap 4: Redis → worker → WS).
///
/// Jika [enableMapWs] + [realtimeWsUrl] aktif, peta penumpang **tidak** memakai
/// polling API tiap 4 detik per driver (hindari dobel dengan WebSocket).
///
/// Build contoh:
/// `--dart-define=TRAKA_ENABLE_MAP_WS=true`
/// `--dart-define=TRAKA_REALTIME_WS_URL=https://xxx.up.railway.app`
/// Opsional jika worker pakai `SOCKET_AUTH_DEV_SECRET`:
/// `--dart-define=TRAKA_REALTIME_SOCKET_TOKEN=...`
class TrakaRealtimeConfig {
  TrakaRealtimeConfig._();

  /// Base URL worker (HTTPS, tanpa path; Socket.IO default `/socket.io/`).
  static const String realtimeWsUrl = String.fromEnvironment(
    'TRAKA_REALTIME_WS_URL',
    defaultValue: '',
  );

  /// Aktifkan koneksi peta realtime (default false agar rilis aman).
  static const bool enableMapWs = bool.fromEnvironment(
    'TRAKA_ENABLE_MAP_WS',
    defaultValue: false,
  );

  /// Token handshake (`auth.token`) — harus sama dengan `SOCKET_AUTH_DEV_SECRET` di worker jika diset.
  static const String socketAuthToken = String.fromEnvironment(
    'TRAKA_REALTIME_SOCKET_TOKEN',
    defaultValue: '',
  );

  /// Hanya jalan jika hybrid API aktif + flag + URL terisi.
  static bool get isEnabled =>
      TrakaApiConfig.useHybrid &&
      TrakaApiConfig.apiBaseUrl.isNotEmpty &&
      enableMapWs &&
      realtimeWsUrl.trim().isNotEmpty;
}
