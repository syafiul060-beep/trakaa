import 'package:flutter/foundation.dart'
    show TargetPlatform, debugPrint, defaultTargetPlatform, kIsWeb;
import 'package:flutter_tts/flutter_tts.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Layanan suara untuk panduan navigasi turn-by-turn.
/// Mendukung mute/unmute dengan persistensi.
///
/// Catatan: Jangan set flag «siap» sebelum `await` konfigurasi TTS selesai — bila tidak,
/// pemanggil kedua bisa lolos lebih dulu dan `speak()` jalan sebelum bahasa terpasang (suara bisu).
class VoiceNavigationService {
  VoiceNavigationService._();
  static final VoiceNavigationService _instance = VoiceNavigationService._();
  static VoiceNavigationService get instance => _instance;

  static const _prefKeyMuted = 'traka_voice_nav_muted';

  final FlutterTts _tts = FlutterTts();
  bool _muted = false;
  bool _engineReady = false;
  Future<void>? _initInFlight;

  bool get muted => _muted;

  /// Siapkan mesin TTS; aman dipanggil berkali-kali dan paralel (satu未来 yang dibagi).
  Future<void> init() async {
    if (_engineReady) return;
    try {
      await (_initInFlight ??= _configureOnce());
      _engineReady = true;
    } catch (e, st) {
      _initInFlight = null;
      debugPrint('VoiceNavigationService.init failed: $e\n$st');
    }
  }

  Future<void> _configureOnce() async {
    await _tts.setSpeechRate(0.48);
    await _tts.setVolume(1.0);
    await _tts.setPitch(1.0);
    await _tts.setQueueMode(1);
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
    try {
      final dynamic idResult = await _tts.setLanguage('id-ID');
      final idFailed =
          idResult == false || idResult == 0 || idResult == '0';
      if (idFailed) {
        await _tts.setLanguage('en-US');
      }
    } catch (_) {
      try {
        await _tts.setLanguage('en-US');
      } catch (_) {}
    }
    final prefs = await SharedPreferences.getInstance();
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
    final text = sentence.trim();
    if (text.isEmpty) return;
    await init();
    if (!_engineReady) return;
    try {
      await _tts.stop();
      await _tts.speak(text);
    } catch (e, st) {
      debugPrint('VoiceNavigationService.speakCue: $e\n$st');
    }
  }

  /// Pola "lead. sisanya" (mis. jarak lalu pesan hampir sampai).
  Future<void> speakWithLead(String lead, String rest) async {
    if (_muted) return;
    await init();
    if (!_engineReady) return;
    final a = lead.trim();
    final b = rest.trim();
    if (a.isEmpty && b.isEmpty) return;
    try {
      await _tts.stop();
      await _tts.speak('$a. $b');
    } catch (e, st) {
      debugPrint('VoiceNavigationService.speakWithLead: $e\n$st');
    }
  }

  /// Satu kalimat ringkas (mis. kickoff tanpa step Directions).
  Future<void> speakSummary(String sentence) async {
    if (_muted) return;
    final text = sentence.trim();
    if (text.isEmpty) return;
    await init();
    if (!_engineReady) return;
    try {
      await _tts.stop();
      await _tts.speak(text);
    } catch (e, st) {
      debugPrint('VoiceNavigationService.speakSummary: $e\n$st');
    }
  }

  /// Stop suara yang sedang berbicara.
  Future<void> stop() async {
    try {
      await _tts.stop();
    } catch (_) {}
  }
}
