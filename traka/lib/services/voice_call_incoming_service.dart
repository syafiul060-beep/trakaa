import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../app_navigator.dart';
import '../screens/voice_call_screen.dart';

/// Service global untuk mendengarkan panggilan suara masuk di seluruh aplikasi.
/// Penerima akan melihat layar panggilan masuk walaupun tidak sedang di chat.
class VoiceCallIncomingService {
  VoiceCallIncomingService._();

  static StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _sub;
  static bool _showingIncoming = false;

  /// Mulai mendengarkan panggilan masuk untuk [uid].
  static void start(String uid) {
    stop();
    _sub = FirebaseFirestore.instance
        .collection('voice_calls')
        .where('calleeUid', isEqualTo: uid)
        .where('status', isEqualTo: 'ringing')
        .snapshots()
        .listen((snap) {
      if (_showingIncoming || snap.docs.isEmpty) return;
      final doc = snap.docs.first;
      final d = doc.data();
      final orderId = doc.id;
      final callerUid = d['callerUid'] as String?;
      final callerName = (d['callerName'] as String?) ?? 'Pemanggil';
      if (callerUid == null || callerUid.isEmpty) return;

      _showingIncoming = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final navigator = appNavigatorKey.currentState;
        if (navigator == null) {
          _showingIncoming = false;
          return;
        }
        navigator.push(
          MaterialPageRoute<void>(
            builder: (_) => VoiceCallScreen(
              orderId: orderId,
              remoteUid: callerUid,
              remoteName: callerName,
              remotePhotoUrl: null,
              isCaller: false,
            ),
          ),
        ).then((_) => _showingIncoming = false);
      });
    });
  }

  /// Hentikan listener.
  static void stop() {
    _sub?.cancel();
    _sub = null;
    _showingIncoming = false;
  }
}
