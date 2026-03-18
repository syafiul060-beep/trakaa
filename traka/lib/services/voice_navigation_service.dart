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
    final prefs = await SharedPreferences.getInstance();
    _muted = prefs.getBool(_prefKeyMuted) ?? true; // Default: mute
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

  /// Bicara instruksi navigasi (hanya jika tidak mute).
  Future<void> speak(String instruction, String distanceText) async {
    if (_muted) return;
    await init();
    final text = '$distanceText. $instruction';
    await _tts.speak(text);
  }

  /// Stop suara yang sedang berbicara.
  Future<void> stop() async {
    await _tts.stop();
  }
}
