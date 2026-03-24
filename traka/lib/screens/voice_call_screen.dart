import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

import '../services/voice_call_ringtone_service.dart';
import '../services/voice_call_service.dart';

/// Layar panggilan suara in-app (outgoing, incoming, active).
class VoiceCallScreen extends StatefulWidget {
  const VoiceCallScreen({
    super.key,
    required this.orderId,
    required this.remoteUid,
    required this.remoteName,
    this.remotePhotoUrl,
    required this.isCaller,
    this.callerName,
  });

  final String orderId;
  final String remoteUid;
  final String remoteName;
  final String? remotePhotoUrl;
  final bool isCaller;
  /// Nama pemanggil (untuk startCall). Jika null, pakai "Saya".
  final String? callerName;

  @override
  State<VoiceCallScreen> createState() => _VoiceCallScreenState();
}

class _VoiceCallScreenState extends State<VoiceCallScreen> {
  String _status = 'ringing'; // ringing | connecting | connected | ended
  bool _hasPopped = false;
  bool _isMuted = false;
  Timer? _ringingTimeoutTimer;
  Timer? _vibrationTimer;
  static const Duration _ringingTimeout = Duration(seconds: 45);
  static const Duration _vibrationInterval = Duration(milliseconds: 1500);

  @override
  void initState() {
    super.initState();
    VoiceCallService.onCallStateChange = _onCallStateChange;
    VoiceCallService.onCallEnded = _onCallEnded;
    VoiceCallService.onMuteChange = _onMuteChange;
    VoiceCallService.onConnectionError = (msg) {
      Future.microtask(() => _showFailureAndExit('Panggilan terputus', msg));
    };

    if (widget.isCaller) {
      _startCall();
      _startRingingTimeout();
    } else {
      _startIncomingVibration();
      _startIncomingRingtone();
      _verifyCallStillRinging();
    }
  }

  void _onMuteChange(bool muted) {
    if (mounted) setState(() => _isMuted = muted);
  }

  /// Cek apakah panggilan masih ringing (mis. dibuka dari tap notifikasi yang tertunda).
  Future<void> _verifyCallStillRinging() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('voice_calls')
          .doc(widget.orderId)
          .get();
      if (!mounted) return;
      final status = doc.data()?['status'] as String?;
      if (status != 'ringing') {
        if (mounted) Navigator.of(context).pop();
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _ringingTimeoutTimer?.cancel();
    _vibrationTimer?.cancel();
    _stopRingtone();
    VoiceCallService.onCallStateChange = null;
    VoiceCallService.onCallEnded = null;
    VoiceCallService.onMuteChange = null;
    VoiceCallService.onConnectionError = null;
    super.dispose();
  }

  void _startIncomingRingtone() {
    VoiceCallRingtoneService.play();
  }

  void _stopRingtone() {
    VoiceCallRingtoneService.stop();
  }

  void _startIncomingVibration() {
    HapticFeedback.mediumImpact();
    _vibrationTimer?.cancel();
    _vibrationTimer = Timer.periodic(_vibrationInterval, (_) {
      if (!mounted || _status != 'ringing') {
        _vibrationTimer?.cancel();
        return;
      }
      HapticFeedback.mediumImpact();
    });
  }

  void _startRingingTimeout() {
    _ringingTimeoutTimer?.cancel();
    _ringingTimeoutTimer = Timer(_ringingTimeout, () {
      if (mounted && _status == 'ringing' && widget.isCaller) {
        VoiceCallService.endCall(widget.orderId);
      }
    });
  }

  Future<void> _showFailureAndExit(String title, String message) async {
    if (!mounted) return;
    final settingsHint = message.toLowerCase().contains('pengaturan');
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          if (settingsHint)
            TextButton(
              onPressed: () async {
                Navigator.pop(ctx);
                await openAppSettings();
              },
              child: const Text('Buka pengaturan'),
            ),
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('OK'),
          ),
        ],
      ),
    );
    if (mounted) {
      _hasPopped = true;
      Navigator.of(context).pop();
    }
  }

  Future<void> _startCall() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      _onCallEnded();
      return;
    }
    final outcome = await VoiceCallService.startCall(
      orderId: widget.orderId,
      callerUid: uid,
      calleeUid: widget.remoteUid,
      callerName: widget.callerName ?? 'Saya',
      calleeName: widget.remoteName,
    );
    if (!outcome.success && mounted) {
      await _showFailureAndExit(
        'Panggilan tidak dapat dilanjutkan',
        outcome.message ?? 'Terjadi kesalahan. Coba lagi atau gunakan chat.',
      );
    }
  }

  Future<void> _acceptCall() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      _onCallEnded();
      return;
    }
    final outcome = await VoiceCallService.acceptCall(
      orderId: widget.orderId,
      calleeUid: uid,
    );
    if (!outcome.success && mounted) {
      await _showFailureAndExit(
        'Panggilan tidak dapat dilanjutkan',
        outcome.message ?? 'Terjadi kesalahan. Coba lagi atau gunakan chat.',
      );
    }
  }

  void _onCallStateChange(String status) {
    if (status == 'connected') {
      _ringingTimeoutTimer?.cancel();
      _vibrationTimer?.cancel();
      _stopRingtone();
      _isMuted = VoiceCallService.isMuted;
    }
    if (mounted) setState(() => _status = status);
  }

  void _onCallEnded() {
    if (!_hasPopped && mounted) {
      _hasPopped = true;
      Navigator.of(context).pop();
    }
  }

  Future<void> _hangUp() async {
    HapticFeedback.mediumImpact();
    await VoiceCallService.endCall(widget.orderId);
    // endCall() memanggil onCallEnded yang sudah pop – jangan double pop
  }

  Future<void> _rejectCall() async {
    HapticFeedback.mediumImpact();
    _stopRingtone();
    await VoiceCallService.rejectCall(widget.orderId);
    // rejectCall tidak memanggil onCallEnded, jadi pop di sini
    if (mounted) Navigator.of(context).pop();
  }

  void _toggleMute() {
    HapticFeedback.mediumImpact();
    VoiceCallService.setMuted(!VoiceCallService.isMuted);
  }

  String get _statusLabel {
    switch (_status) {
      case 'ringing':
        return widget.isCaller ? 'Memanggil...' : 'Panggilan masuk';
      case 'connecting':
        return 'Menghubungkan...';
      case 'connected':
        return 'Terhubung';
      default:
        return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 48),
            // Avatar & nama
            CircleAvatar(
              radius: 56,
              backgroundColor: colorScheme.surfaceContainerHighest,
              backgroundImage: widget.remotePhotoUrl != null &&
                      widget.remotePhotoUrl!.isNotEmpty
                  ? NetworkImage(widget.remotePhotoUrl!)
                  : null,
              child: widget.remotePhotoUrl == null ||
                      widget.remotePhotoUrl!.isEmpty
                  ? Icon(
                      Icons.person,
                      size: 56,
                      color: colorScheme.onSurfaceVariant,
                    )
                  : null,
            ),
            const SizedBox(height: 24),
            Text(
              widget.remoteName,
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: colorScheme.onSurface,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              _statusLabel,
              style: TextStyle(
                fontSize: 16,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 28),
              child: Text(
                'Panggilan lewat aplikasi Traka. Nomor HP tidak ditampilkan ke lawan bicara.',
                style: TextStyle(
                  fontSize: 12,
                  height: 1.35,
                  color: colorScheme.onSurfaceVariant.withValues(alpha: 0.9),
                ),
                textAlign: TextAlign.center,
              ),
            ),
            const Spacer(),
            // Tombol
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  if (!widget.isCaller && _status == 'ringing') ...[
                    _buildActionButton(
                      icon: Icons.call_end,
                      label: 'Tolak',
                      color: Colors.red,
                      onTap: _rejectCall,
                    ),
                    _buildActionButton(
                      icon: Icons.call,
                      label: 'Terima',
                      color: Colors.green,
                      onTap: _acceptCall,
                    ),
                  ] else ...[
                    if (_status == 'connected')
                      _buildActionButton(
                        icon: _isMuted ? Icons.mic_off : Icons.mic,
                        label: _isMuted ? 'Buka' : 'Bisukan',
                        color: _isMuted ? Colors.orange : colorScheme.onSurfaceVariant,
                        onTap: _toggleMute,
                      ),
                    _buildActionButton(
                      icon: Icons.call_end,
                      label: 'Tutup',
                      color: Colors.red,
                      onTap: _hangUp,
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 48),
          ],
        ),
      ),
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Material(
          color: color.withValues(alpha: 0.2),
          shape: const CircleBorder(),
          child: InkWell(
            onTap: onTap,
            customBorder: const CircleBorder(),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Icon(icon, size: 32, color: color),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          label,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: Theme.of(context).colorScheme.onSurface,
          ),
        ),
      ],
    );
  }
}
