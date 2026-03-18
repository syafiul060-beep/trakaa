import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';

/// Memutar ringtone saat panggilan suara masuk.
/// Prioritas: asset assets/sounds/ringtone.mp3, fallback URL.
class VoiceCallRingtoneService {
  VoiceCallRingtoneService._();

  static final AudioPlayer _player = AudioPlayer();
  static bool _isPlaying = false;

  static Future<void> play() async {
    if (_isPlaying) return;
    try {
      _isPlaying = true;
      // Coba asset dulu
      try {
        await _player.setAsset('assets/sounds/ringtone.mp3');
      } catch (_) {
        // Fallback: URL ringtone (Mixkit, CC0)
        await _player.setUrl(
          'https://assets.mixkit.co/active_storage/sfx/2869-call-phone-ring-2869.mp3',
        );
      }
      await _player.setLoopMode(LoopMode.one);
      await _player.setVolume(1.0);
      await _player.play();
    } catch (e, st) {
      if (kDebugMode) debugPrint('VoiceCallRingtoneService.play: $e\n$st');
      _isPlaying = false;
    }
  }

  static Future<void> stop() async {
    if (!_isPlaying) return;
    try {
      await _player.stop();
      _isPlaying = false;
    } catch (e, st) {
      if (kDebugMode) debugPrint('VoiceCallRingtoneService.stop: $e\n$st');
      _isPlaying = false;
    }
  }
}
