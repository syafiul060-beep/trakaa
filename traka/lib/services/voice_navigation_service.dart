import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:flutter_tts/flutter_tts.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Layanan suara untuk panduan navigasi turn-by-turn.
/// Mendukung mute/unmute dengan persistensi.
class VoiceNavigationService {
  VoiceNavigationService._();
  static final VoiceNavigationService _instance = VoiceNavigationService._();
  static VoiceNavigationService get instance => _instance;

  static const _prefKeyMuted = 'traka_voice_nav_muted';

  final FlutterTts _tts = FlutterTts();
  bool _muted = false;
  bool _initialized = false;

  bool get muted => _muted;

  /// Inisialisasi TTS dan muat preferensi mute.
  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;
    await _tts.setLanguage('id-ID');
    await _tts.setSpeechRate(0.5); // Sedikit lebih lambat agar jelas
    await _tts.setVolume(1.0);
    await _tts.setQueueMode(1); // Android: flush previous
    // iOS: turunkan volume audio lain saat TTS (mirip Google Maps).
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS) {
      try {
        await _tts.setIosAudioCategory(
          IosTextToSpeechAudioCategory.playback,
          const [
            IosTextToSpeechAudioCategoryOptions.duckOthers,
            IosTextToSpeechAudioCategoryOptions.defaultToSpeaker,
          ],
          IosTextToSpeechAudioMode.voicePrompt,
        );
      } catch (_) {}
    }
    final prefs = await SharedPreferences.getInstance();
    // Default: suara aktif (mirip app navigasi umum); user bisa mute dari overlay.
    _muted = prefs.getBool(_prefKeyMuted) ?? false;
  }

  /// Set mute dan simpan ke preferensi.
  Future<void> setMuted(bool value) async {
    if (_muted == value) return;
    _muted = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefKeyMuted, value);
  }

  /// Toggle mute.
  Future<void> toggleMuted() async {
    await setMuted(!_muted);
  }

  /// Satu frasa navigasi utuh — sama dengan teks utama di banner atas (hindari duplikasi jarak).
  Future<void> speakCue(String sentence) async {
    if (_muted) return;
    await init();
    await _tts.stop();
    await _tts.speak(sentence.trim());
  }

  /// Pola "lead. sisanya" (mis. jarak lalu pesan hampir sampai).
  Future<void> speakWithLead(String lead, String rest) async {
    if (_muted) return;
    await init();
    await _tts.stop();
    await _tts.speak('${lead.trim()}. ${rest.trim()}');
  }

  /// Satu kalimat ringkas (mis. kickoff tanpa step Directions).
  Future<void> speakSummary(String sentence) async {
    if (_muted) return;
    await init();
    await _tts.stop();
    await _tts.speak(sentence);
  }

  /// Stop suara yang sedang berbicara.
  Future<void> stop() async {
    await _tts.stop();
  }
}
