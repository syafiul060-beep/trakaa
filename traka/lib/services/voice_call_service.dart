import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:permission_handler/permission_handler.dart';

import 'app_config_service.dart';

/// Hasil mulai/terima panggilan (pesan untuk pengguna jika gagal).
class VoiceCallOutcome {
  const VoiceCallOutcome._({required this.success, this.message});
  final bool success;
  final String? message;

  static const VoiceCallOutcome ok = VoiceCallOutcome._(success: true);
  static VoiceCallOutcome fail(String message) =>
      VoiceCallOutcome._(success: false, message: message);
}

/// Signaling untuk panggilan suara in-app via Firestore.
/// voice_calls/{orderId} = state panggilan
/// voice_calls/{orderId}/ice = ICE candidates
class VoiceCallService {
  VoiceCallService._();

  static const _collection = 'voice_calls';
  static const _subIce = 'ice';

  static StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _callSub;
  static StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _iceSub;
  static RTCPeerConnection? _peerConnection;
  static MediaStream? _localStream;
  static String? _currentOrderId;

  static void Function(MediaStream stream)? onLocalStream;
  static void Function(MediaStream stream)? onRemoteStream;
  static void Function(String status)? onCallStateChange;
  static void Function()? onCallEnded;
  static void Function(bool muted)? onMuteChange;

  /// Dipanggil saat koneksi WebRTC gagal (mis. NAT/jaringan) sebelum layar ditutup.
  static void Function(String userMessage)? onConnectionError;

  static bool _isMuted = false;

  static Future<VoiceCallOutcome> _ensureMicPermission() async {
    var status = await Permission.microphone.status;
    if (!status.isGranted) {
      status = await Permission.microphone.request();
    }
    if (status.isGranted) return VoiceCallOutcome.ok;
    if (status.isPermanentlyDenied) {
      return VoiceCallOutcome.fail(
        'Akses mikrofon ditolak permanen. Buka Pengaturan > Traka > Izin, lalu aktifkan Mikrofon.',
      );
    }
    return VoiceCallOutcome.fail(
      'Izin mikrofon diperlukan untuk panggilan suara. Izinkan akses saat diminta.',
    );
  }

  static String _mapMediaError(Object e) {
    final s = e.toString().toLowerCase();
    if (s.contains('permission') ||
        s.contains('denied') ||
        s.contains('notallowed')) {
      return 'Mikrofon tidak dapat diakses. Periksa izin aplikasi di pengaturan perangkat.';
    }
    if (s.contains('notfound') || s.contains('no device')) {
      return 'Tidak ada mikrofon yang terdeteksi di perangkat ini.';
    }
    if (s.contains('network') || s.contains('timeout')) {
      return 'Koneksi bermasalah. Periksa internet dan coba lagi.';
    }
    return 'Gagal menghubungkan panggilan. Periksa koneksi dan coba lagi.';
  }

  /// Apakah mikrofon saat ini dimute.
  static bool get isMuted => _isMuted;

  /// Set mute mikrofon saat panggilan aktif.
  static void setMuted(bool muted) {
    _isMuted = muted;
    final tracks = _localStream?.getAudioTracks();
    if (tracks != null && tracks.isNotEmpty) {
      tracks[0].enabled = !muted;
    }
    onMuteChange?.call(muted);
  }

  /// Mulai panggilan keluar (caller).
  static Future<VoiceCallOutcome> startCall({
    required String orderId,
    required String callerUid,
    required String calleeUid,
    required String callerName,
    required String calleeName,
  }) async {
    if (_currentOrderId != null) {
      return VoiceCallOutcome.fail('Panggilan lain sedang berlangsung.');
    }
    final perm = await _ensureMicPermission();
    if (!perm.success) return perm;

    try {
      final col = FirebaseFirestore.instance.collection(_collection);
      await col.doc(orderId).set({
        'callerUid': callerUid,
        'calleeUid': calleeUid,
        'callerName': callerName,
        'calleeName': calleeName,
        'status': 'ringing',
        'createdAt': FieldValue.serverTimestamp(),
      });
      _currentOrderId = orderId;

      _localStream = await navigator.mediaDevices.getUserMedia({
        'audio': true,
        'video': false,
      });
      onLocalStream?.call(_localStream!);

      _peerConnection = await _createPeerConnection(orderId, callerUid, true);
      _peerConnection!.addTrack(_localStream!.getAudioTracks()[0], _localStream!);

      final offer = await _peerConnection!.createOffer();
      await _peerConnection!.setLocalDescription(offer);
      await col.doc(orderId).update({
        'offer': {'type': offer.type, 'sdp': offer.sdp},
        'updatedAt': FieldValue.serverTimestamp(),
      });

      _listenForAnswer(orderId);
      _listenForIce(orderId);
      onCallStateChange?.call('ringing');
      return VoiceCallOutcome.ok;
    } catch (e, st) {
      if (kDebugMode) debugPrint('VoiceCallService.startCall error: $e\n$st');
      await endCall(orderId);
      return VoiceCallOutcome.fail(_mapMediaError(e));
    }
  }

  /// Terima panggilan (callee).
  static Future<VoiceCallOutcome> acceptCall({
    required String orderId,
    required String calleeUid,
  }) async {
    if (_currentOrderId != null) {
      return VoiceCallOutcome.fail('Panggilan lain sedang berlangsung.');
    }
    final perm = await _ensureMicPermission();
    if (!perm.success) return perm;

    try {
      final doc = await FirebaseFirestore.instance
          .collection(_collection)
          .doc(orderId)
          .get();
      if (!doc.exists) {
        return VoiceCallOutcome.fail('Panggilan tidak ditemukan atau sudah berakhir.');
      }
      final d = doc.data()!;
      if ((d['calleeUid'] as String?) != calleeUid) {
        return VoiceCallOutcome.fail('Panggilan ini bukan untuk akun Anda.');
      }
      if ((d['status'] as String?) != 'ringing') {
        return VoiceCallOutcome.fail('Panggilan sudah tidak aktif.');
      }

      final offerMap = d['offer'] as Map<String, dynamic>?;
      if (offerMap == null) {
        return VoiceCallOutcome.fail('Sinyal panggilan tidak lengkap. Coba minta panggilan ulang.');
      }
      final offer = RTCSessionDescription(
        offerMap['sdp'] as String,
        offerMap['type'] as String,
      );

      _currentOrderId = orderId;
      _localStream = await navigator.mediaDevices.getUserMedia({
        'audio': true,
        'video': false,
      });
      onLocalStream?.call(_localStream!);

      _peerConnection = await _createPeerConnection(orderId, calleeUid, false);
      _peerConnection!.addTrack(_localStream!.getAudioTracks()[0], _localStream!);
      await _peerConnection!.setRemoteDescription(offer);

      final answer = await _peerConnection!.createAnswer();
      await _peerConnection!.setLocalDescription(answer);

      await FirebaseFirestore.instance.collection(_collection).doc(orderId).update({
        'answer': {'type': answer.type, 'sdp': answer.sdp},
        'status': 'connected',
        'connectedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      _listenForIce(orderId);
      onCallStateChange?.call('connected');
      return VoiceCallOutcome.ok;
    } catch (e, st) {
      if (kDebugMode) debugPrint('VoiceCallService.acceptCall error: $e\n$st');
      await endCall(orderId);
      return VoiceCallOutcome.fail(_mapMediaError(e));
    }
  }

  /// Tolak panggilan.
  static Future<void> rejectCall(String orderId) async {
    await FirebaseFirestore.instance.collection(_collection).doc(orderId).update({
      'status': 'rejected',
      'updatedAt': FieldValue.serverTimestamp(),
    });
    _cleanup();
  }

  /// Akhiri panggilan.
  static Future<void> endCall(String orderId) async {
    try {
      await FirebaseFirestore.instance.collection(_collection).doc(orderId).update({
        'status': 'ended',
        'endedAt': FieldValue.serverTimestamp(),
      });
    } catch (_) {}
    _cleanup();
    onCallEnded?.call();
  }

  static void _cleanup() {
    _callSub?.cancel();
    _callSub = null;
    _iceSub?.cancel();
    _iceSub = null;
    _peerConnection?.close();
    _peerConnection = null;
    _localStream?.dispose();
    _localStream = null;
    _currentOrderId = null;
    _isMuted = false;
  }

  static Future<RTCPeerConnection> _createPeerConnection(
    String orderId,
    String myUid,
    bool isCaller,
  ) async {
    final iceServers = await _getIceServers();
    final pc = await createPeerConnection({'iceServers': iceServers});

    pc.onIceCandidate = (candidate) async {
      try {
        await FirebaseFirestore.instance
            .collection(_collection)
            .doc(orderId)
            .collection(_subIce)
            .add({
          'fromUid': myUid,
          'candidate': {
            'candidate': candidate.candidate,
            'sdpMid': candidate.sdpMid,
            'sdpMLineIndex': candidate.sdpMLineIndex,
          },
          'createdAt': FieldValue.serverTimestamp(),
        });
      } catch (_) {}
    };

    pc.onTrack = (event) {
      if (event.streams.isNotEmpty) {
        onRemoteStream?.call(event.streams[0]);
      }
    };

    pc.onConnectionState = (state) {
      if (state == RTCPeerConnectionState.RTCPeerConnectionStateFailed) {
        onConnectionError?.call(
          'Koneksi panggilan gagal. Periksa internet atau coba lagi dari area sinyal lebih baik.',
        );
        _cleanup();
        if (onConnectionError == null) {
          onCallEnded?.call();
        }
        return;
      }
      if (state == RTCPeerConnectionState.RTCPeerConnectionStateDisconnected ||
          state == RTCPeerConnectionState.RTCPeerConnectionStateClosed) {
        _cleanup();
        onCallEnded?.call();
      }
    };

    return pc;
  }

  static Future<List<Map<String, dynamic>>> _getIceServers() async {
    return AppConfigService.getVoiceCallIceServers();
  }

  static void _listenForAnswer(String orderId) {
    _callSub?.cancel();
    _callSub = FirebaseFirestore.instance
        .collection(_collection)
        .doc(orderId)
        .snapshots()
        .listen((snap) async {
      if (!snap.exists) return;
      final d = snap.data()!;
      final status = d['status'] as String?;
      if (status == 'rejected' || status == 'ended') {
        _cleanup();
        onCallEnded?.call();
        return;
      }
      final answerMap = d['answer'] as Map<String, dynamic>?;
      if (answerMap != null && _peerConnection != null) {
        try {
          final answer = RTCSessionDescription(
            answerMap['sdp'] as String,
            answerMap['type'] as String,
          );
          final desc = await _peerConnection!.getRemoteDescription();
          if (desc == null) {
            await _peerConnection!.setRemoteDescription(answer);
            onCallStateChange?.call('connected');
          }
        } catch (_) {}
      }
    });
  }

  static void _listenForIce(String orderId) {
    final myUid = FirebaseAuth.instance.currentUser?.uid;
    if (myUid == null) return;

    _iceSub?.cancel();
    _iceSub = FirebaseFirestore.instance
        .collection(_collection)
        .doc(orderId)
        .collection(_subIce)
        .orderBy('createdAt')
        .snapshots()
        .listen((snap) async {
      for (final doc in snap.docs) {
        final d = doc.data();
        if ((d['fromUid'] as String?) == myUid) continue;
        final candMap = d['candidate'] as Map<String, dynamic>?;
        if (candMap != null && _peerConnection != null) {
          try {
            final candidate = RTCIceCandidate(
              candMap['candidate'] as String,
              candMap['sdpMid'] as String? ?? '',
              candMap['sdpMLineIndex'] as int? ?? 0,
            );
            await _peerConnection!.addCandidate(candidate);
          } catch (_) {}
        }
      }
    });
  }

  /// Stream panggilan masuk untuk [myUid].
  static Stream<Map<String, dynamic>?> streamIncomingCall(String myUid) {
    return FirebaseFirestore.instance
        .collection(_collection)
        .where('calleeUid', isEqualTo: myUid)
        .where('status', isEqualTo: 'ringing')
        .snapshots()
        .map((snap) {
      if (snap.docs.isEmpty) return null;
      final doc = snap.docs.first;
      return {'orderId': doc.id, ...doc.data()};
    });
  }
}
