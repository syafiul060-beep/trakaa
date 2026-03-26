import 'dart:async';
import 'dart:io' show HttpException;

import 'services/performance_trace_service.dart';
import 'dart:ui' show PlatformDispatcher;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:provider/provider.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:firebase_performance/firebase_performance.dart';
import 'package:flutter/foundation.dart' show Listenable, kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'firebase_options.dart';
import 'screens/login_screen.dart';
import 'screens/splash_screen_wrapper.dart';
import 'services/fake_gps_overlay_service.dart';
import 'services/route_notification_service.dart';
import 'services/fcm_service.dart';

import 'utils/app_logger.dart';
import 'services/map_style_service.dart';
import 'services/tile_layer_service.dart';
import 'services/theme_service.dart';
import 'l10n/app_localizations.dart';
import 'services/locale_service.dart';
import 'theme/app_theme.dart';
import 'widgets/app_update_wrapper.dart';
import 'widgets/fake_gps_overlay.dart';
import 'widgets/traka_l10n_scope.dart';
import 'app_navigator.dart';
import 'providers/app_config_provider.dart';
import 'services/voice_call_incoming_service.dart';
import 'services/auth_redirect_state.dart';
import 'services/lite_mode_service.dart';
import 'services/connectivity_service.dart';
import 'widgets/offline_banner.dart';
import 'services/biometric_lock_service.dart';
import 'services/car_icon_service.dart';
import 'widgets/biometric_lifecycle_handler.dart';
import 'widgets/biometric_lock_overlay.dart';
import 'config/traka_api_config.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Bersihkan cache icon mobil lama (transparansi, dll.)
  CarIconService.clearCache();

  // Lock orientasi portrait: HP landscape tetap tampil portrait (driver lebih aman)
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  } catch (e, st) {
    // Android native bisa auto-init Firebase dari google-services.json.
    // Jika duplicate-app, Firebase sudah ada — lanjut saja.
    if (_isDuplicateAppError(e)) {
      debugPrint('Firebase sudah di-init (native/duplicate): $e');
    } else {
      debugPrint('Firebase init error: $e');
      debugPrint('$st');
      runApp(_ErrorApp(message: 'Gagal memuat Firebase: $e'));
      return;
    }
  }

  if (kDebugMode) {
    debugPrint(
      '[Traka] Backend hybrid: aktif=${TrakaApiConfig.isApiEnabled} '
      '(TRAKA_USE_HYBRID + URL). Pinning=${TrakaApiConfig.isCertificatePinningEnabled}',
    );
  }

  await ThemeService.init();
  await LocaleService.init();
  // Harus sebelum Firestore.settings — cacheSize mengikuti deteksi RAM / preferensi lite.
  await LiteModeService.init();

  // Firestore cache: 100 MB standar, 50 MB saat mode lite (HP RAM < 3 GB)
  final firestore = FirebaseFirestore.instance;
  firestore.settings = Settings(
    persistenceEnabled: true,
    cacheSizeBytes: LiteModeService.firestoreCacheSizeBytes,
  );
  await TileLayerService.ensureInitialized();
  // Preload dark map style agar siap saat user pakai mode gelap
  await MapStyleService.loadDarkStyle();
  await MapStyleService.loadLightStyle();
  // Timer auto night: peta gelap jam 18:00–06:00
  MapStyleService.startNightModeTimer();

  FlutterError.onError = (details) {
    // Jangan laporkan error pemuatan gambar (403/404) ke Crashlytics – bukan crash fatal
    if (_isImageLoadError(details)) return;
    FirebaseCrashlytics.instance.recordFlutterFatalError(details);
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
    return true;
  };

  unawaited(PerformanceTraceService.startStartupToInteractive());

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AppConfigProvider()),
      ],
      child: const BiometricLifecycleHandler(child: TrakaApp()),
    ),
  );

  // Init Crashlytics di background
  FirebaseCrashlytics.instance.setCrashlyticsCollectionEnabled(true);

  // Firebase Performance Monitoring (Tahap 5)
  await FirebasePerformance.instance.setPerformanceCollectionEnabled(true);

  // Init di background (tidak blok tampilan)
  _initInBackground();

  // Tahap 2: authStateChanges – redirect ke Login saat user sign out (token invalid, dll.)
  _setupAuthStateListener();
}

/// Cek apakah error duplicate-app (Firebase sudah di-init native/plugin).
bool _isDuplicateAppError(Object e) {
  final msg = e.toString().toLowerCase();
  if (msg.contains('duplicate-app') ||
      msg.contains('core/duplicate-app') ||
      msg.contains('already exists')) {
    return true;
  }
  // PlatformException / FirebaseException punya .code
  try {
    final code = (e as dynamic).code as String?;
    return code?.toLowerCase() == 'duplicate-app' ||
        code?.toLowerCase() == 'core/duplicate-app';
  } catch (_) {
    return false;
  }
}

/// Cek apakah error dari pemuatan gambar (HttpException 4xx) – jangan laporkan ke Crashlytics.
bool _isImageLoadError(FlutterErrorDetails details) {
  if (details.exception is HttpException) return true;
  final msg = details.exception.toString().toLowerCase();
  final stack = details.stack?.toString().toLowerCase() ?? '';
  final isHttpError = msg.contains('httpexception') ||
      (msg.contains('statuscode') && (msg.contains('403') || msg.contains('404')));
  final isImagePath = stack.contains('imagestreamcompleter') ||
      stack.contains('multiimagestreamcompleter') ||
      stack.contains('image_stream');
  return isHttpError && isImagePath;
}

/// Listener auth state: saat user berubah dari login → null, redirect ke LoginScreen.
/// Delay cukup lama saat user==null untuk hindari redirect salah saat:
/// - linkWithCredential (token refresh emit null sebentar)
/// - update email via Admin SDK (verifyAndUpdateProfileEmail) yang trigger token refresh lebih lama
void _setupAuthStateListener() {
  User? prevUser;
  FirebaseAuth.instance.authStateChanges().listen((user) {
    if (prevUser != null && user == null) {
      BiometricLockService.forceUnlock();
      VoiceCallIncomingService.stop();
      // Tunggu 3 detik: token refresh (linkWithCredential, update email, sign in) bisa emit null sementara
      Future<void>.delayed(const Duration(milliseconds: 3000), () {
        final current = FirebaseAuth.instance.currentUser;
        if (current != null) return; // User masih login, jangan redirect
        // Sudah di LoginScreen (mis. setelah registrasi)? Jangan replace — hindari loading berhenti & harus tap 2x
        if (AuthRedirectState.isOnLoginScreen) return;
        // Sedang verifikasi (upload foto, KTP, SIM)? Jangan redirect — hindari logout tiba-tiba
        if (AuthRedirectState.isInVerificationFlow) return;
        // Sedang proses login (tap Masuk)? Jangan redirect — hindari loading berhenti & harus tap 2x
        if (AuthRedirectState.isInLoginFlow) return;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          appNavigatorKey.currentState?.pushAndRemoveUntil(
            MaterialPageRoute<void>(
              builder: (_) => const AppUpdateWrapper(child: LoginScreen()),
            ),
            (route) => false,
          );
        });
      });
    }
    prevUser = user;
  });
}

/// Inisialisasi non-kritis di background setelah UI tampil.
void _initInBackground() {
  ConnectivityService.startListening();
  Future(() async {
    try {
      await FcmService.init();
    } catch (e, st) {
      logError('main._initInBackground FcmService', e, st);
    }
    try {
      await RouteNotificationService.init();
    } catch (e, st) {
      logError('main._initInBackground RouteNotificationService', e, st);
    }
  });
}

/// Tampilan error jika Firebase/init gagal (hindari layar hitam).
class _ErrorApp extends StatelessWidget {
  final String message;

  const _ErrorApp({required this.message});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations(locale: AppLocale.id);
    return MaterialApp(
      home: Scaffold(
        backgroundColor: Theme.of(context).colorScheme.surface,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.error_outline, size: 64, color: Colors.red),
                const SizedBox(height: 16),
                Text(
                  l10n.errorOccurred,
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                Text(
                  message,
                  style: const TextStyle(fontSize: 14),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                Text(
                  l10n.firebaseConfigHint,
                  style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class TrakaApp extends StatelessWidget {
  const TrakaApp({super.key});

  /// Satu listener untuk tema + locale — hindari nested [ValueListenableBuilder]
  /// yang memicu dua kali rebuild beruntun (risiko assertion `_dependents.isEmpty`).
  static final Listenable _themeAndLocale = Listenable.merge([
    ThemeService.themeModeNotifier,
    LocaleService.localeNotifier,
  ]);

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _themeAndLocale,
      builder: (context, _) {
        return MaterialApp(
          navigatorKey: appNavigatorKey,
          title: 'Traka Travel Kalimantan',
          debugShowCheckedModeBanner: false,
          supportedLocales: const [Locale('id', 'ID'), Locale('en')],
          locale: LocaleService.materialLocale,
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          localeResolutionCallback: (locale, supported) {
            if (locale != null && locale.languageCode == 'id') {
              return const Locale('id', 'ID');
            }
            return const Locale('id', 'ID');
          },
          theme: AppTheme.lightTheme,
          darkTheme: AppTheme.darkTheme,
          themeMode: ThemeService.themeModeNotifier.value,
          builder: (context, child) {
            final media = MediaQuery.of(context);
            final shortestSide = media.size.shortestSide;
            // Ukuran font tidak mengikuti pengaturan HP pengguna; hanya sesuaikan layar kecil.
            final scale = shortestSide < 340
                ? 0.88
                : shortestSide < 380
                    ? 0.92
                    : shortestSide < 420
                        ? 0.96
                        : 1.0;
            return MediaQuery(
              data: media.copyWith(
                textScaler: TextScaler.linear(scale),
              ),
              child: ValueListenableBuilder<bool>(
                valueListenable: FakeGpsOverlayService.fakeGpsDetected,
                builder: (context, showFakeGpsOverlay, _) {
                  return Stack(
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const OfflineBanner(),
                          Expanded(
                            child: TrakaL10n(
                              key: ValueKey<AppLocale>(LocaleService.current),
                              data: AppLocalizations(
                                locale: LocaleService.current,
                              ),
                              child: child!,
                            ),
                          ),
                        ],
                      ),
                      if (showFakeGpsOverlay)
                        const Positioned.fill(
                          child: FakeGpsOverlay(),
                        ),
                      const Positioned.fill(
                        child: BiometricLockOverlay(),
                      ),
                    ],
                  );
                },
              ),
            );
          },
          home: const SplashScreenWrapper(),
          routes: {'/login': (context) => const LoginScreen()},
        );
      },
    );
  }
}
