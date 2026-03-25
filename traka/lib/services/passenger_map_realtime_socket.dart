import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;

/// Socket.IO ke [traka-realtime-worker]: join room geohash-5, terima `driver:location`.
class PassengerMapRealtimeSocket {
  io.Socket? _socket;
  double? _lastJoinLat;
  double? _lastJoinLng;
  late double _anchorLat;
  late double _anchorLng;
  bool _disposed = false;
  String? _lastConnectUrl;
  String _lastAuthKey = '';
  void Function(Map<String, dynamic> data)? _onDriverLocation;

  /// [url] worker Socket.IO (bukan URL API HTTP); contoh `https://<worker>.up.railway.app`
  void connect({
    required String url,
    String? authToken,
    required double lat,
    required double lng,
    required void Function(Map<String, dynamic> data) onDriverLocation,
  }) {
    _disposed = false;
    _anchorLat = lat;
    _anchorLng = lng;
    _onDriverLocation = onDriverLocation;

    final trimmed = url.trim();
    if (trimmed.isEmpty) return;

    final authKey = authToken?.trim() ?? '';
    if (_socket != null &&
        _lastConnectUrl == trimmed &&
        _lastAuthKey == authKey &&
        !_disposed) {
      if (_socket!.connected) {
        _lastJoinLat = null;
        _lastJoinLng = null;
        _emitJoin(lat, lng);
      }
      return;
    }

    dispose();
    _disposed = false;
    _lastConnectUrl = trimmed;
    _lastAuthKey = authKey;

    final builder = io.OptionBuilder()
        .setTransports(['websocket'])
        .setReconnectionAttempts(12)
        .setReconnectionDelay(1500)
        .setReconnectionDelayMax(8000)
        .enableReconnection();
    if (authKey.isNotEmpty) {
      builder.setAuth({'token': authKey});
    }

    _socket = io.io(trimmed, builder.build());
    _socket!.on('driver:location', (data) {
      if (_disposed) return;
      if (data is! Map) return;
      _onDriverLocation?.call(Map<String, dynamic>.from(data));
    });
    _socket!.onConnect((_) {
      if (_disposed) return;
      _lastJoinLat = null;
      _lastJoinLng = null;
      _emitJoin(_anchorLat, _anchorLng);
    });
    _socket!.onConnectError((dynamic e) {
      if (kDebugMode) {
        debugPrint('PassengerMapRealtimeSocket connect_error: $e');
      }
    });
  }

  void _emitJoin(double lat, double lng) {
    final s = _socket;
    if (s == null || !s.connected) return;
    if (_lastJoinLat != null && _lastJoinLng != null) {
      s.emit('leave', {'lat': _lastJoinLat, 'lng': _lastJoinLng});
    }
    s.emit('join', {'lat': lat, 'lng': lng});
    _lastJoinLat = lat;
    _lastJoinLng = lng;
  }

  /// Panggil saat penumpang berpindah cukup jauh (~>800 m) agar room geohash-5 tetap relevan.
  void updatePassengerPosition(double lat, double lng) {
    if (_disposed || _socket == null) return;
    _anchorLat = lat;
    _anchorLng = lng;
    if (_lastJoinLat != null && _lastJoinLng != null) {
      final d = Geolocator.distanceBetween(
        _lastJoinLat!,
        _lastJoinLng!,
        lat,
        lng,
      );
      if (d < 800) return;
    }
    if (_socket!.connected) {
      _emitJoin(lat, lng);
    }
  }

  void dispose() {
    _disposed = true;
    _lastJoinLat = null;
    _lastJoinLng = null;
    _lastConnectUrl = null;
    _lastAuthKey = '';
    _onDriverLocation = null;
    _socket?.dispose();
    _socket = null;
  }
}
