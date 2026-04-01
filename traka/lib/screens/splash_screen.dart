import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../l10n/app_localizations.dart' show AppLocale;
import '../services/locale_service.dart';
import '../theme/app_theme.dart';

/// Splash screen dengan animasi bertahap: logo, TRAKA, Travel Kalimantan, One Touch Solution.
/// — Tombol Lewati: mempercepat animasi (navigasi tetap di [SplashScreenWrapper]).
/// — Mengikuti pengaturan sistem "kurangi animasi" bila aktif.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _logoFade;
  late Animation<double> _logoScale;
  late Animation<double> _trakaFade;
  late Animation<Offset> _trakaSlide;
  late Animation<double> _subtitleFade;
  late Animation<Offset> _subtitleSlide;
  late Animation<double> _taglineFade;

  bool _animationStarted = false;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    );

    _logoFade = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _controller, curve: const Interval(0, 0.28, curve: Curves.easeOut)),
    );
    _logoScale = Tween<double>(begin: 0.86, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: const Interval(0, 0.32, curve: Curves.easeOutCubic)),
    );
    _trakaFade = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _controller, curve: const Interval(0.14, 0.44, curve: Curves.easeOut)),
    );
    _trakaSlide = Tween<Offset>(
      begin: const Offset(0, 0.28),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _controller, curve: const Interval(0.14, 0.44, curve: Curves.easeOutCubic)));
    _subtitleFade = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _controller, curve: const Interval(0.34, 0.62, curve: Curves.easeOut)),
    );
    _subtitleSlide = Tween<Offset>(
      begin: const Offset(0, 0.2),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _controller, curve: const Interval(0.34, 0.62, curve: Curves.easeOutCubic)));
    _taglineFade = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _controller, curve: const Interval(0.5, 0.75, curve: Curves.easeOut)),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_animationStarted) return;
    _animationStarted = true;

    unawaited(
        precacheImage(const AssetImage('assets/images/traka_brand_logo.png'), context));

    if (MediaQuery.of(context).disableAnimations) {
      _controller.value = 1.0;
    } else {
      _controller.forward();
    }
  }

  void _skipAnimation() {
    if (!mounted || _controller.isCompleted) return;
    _controller.animateTo(
      1.0,
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String get _skipLabel =>
      LocaleService.current == AppLocale.id ? 'Lewati' : 'Skip';

  @override
  Widget build(BuildContext context) {
    final topPad = MediaQuery.paddingOf(context).top;
    return Scaffold(
      backgroundColor: AppTheme.brandSplashBackground,
      body: Stack(
        children: [
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: const Alignment(0, -0.25),
                  radius: 1.15,
                  colors: [
                    AppTheme.primary.withValues(alpha: 0.45),
                    AppTheme.brandSplashMid,
                    AppTheme.brandSplashBackground,
                  ],
                  stops: const [0.0, 0.45, 1.0],
                ),
              ),
            ),
          ),
          Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                FadeTransition(
                  opacity: _logoFade,
                  child: ScaleTransition(
                    scale: _logoScale,
                    child: Image.asset(
                      'assets/images/traka_brand_logo.png',
                      width: 300,
                      height: 300,
                      fit: BoxFit.contain,
                      filterQuality: FilterQuality.high,
                      gaplessPlayback: true,
                    ),
                  ),
                ),
                const SizedBox(height: 32),
                FadeTransition(
                  opacity: _trakaFade,
                  child: SlideTransition(
                    position: _trakaSlide,
                    child: Text(
                      'TRAKA',
                      style: GoogleFonts.plusJakartaSans(
                        color: Colors.white,
                        fontSize: 44,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 10,
                        height: 1.05,
                        shadows: [
                          Shadow(
                            color: AppTheme.primary.withValues(alpha: 0.55),
                            blurRadius: 24,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                FadeTransition(
                  opacity: _subtitleFade,
                  child: SlideTransition(
                    position: _subtitleSlide,
                    child: Text(
                      'Travel Kalimantan',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.poppins(
                        color: Colors.white.withValues(alpha: 0.95),
                        fontSize: 22,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 2.5,
                        height: 1.2,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                FadeTransition(
                  opacity: _taglineFade,
                  child: Text(
                    'One Touch Solution',
                    style: GoogleFonts.plusJakartaSans(
                      color: Colors.white.withValues(alpha: 0.78),
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      letterSpacing: 3,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ),
                const SizedBox(height: 48),
                FadeTransition(
                  opacity: _taglineFade,
                  child: const SizedBox(
                    width: 40,
                    height: 40,
                    child: CircularProgressIndicator(
                      strokeWidth: 3,
                      valueColor: AlwaysStoppedAnimation<Color>(AppTheme.primary),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Positioned(
            top: topPad + 4,
            right: 8,
            child: TextButton(
              onPressed: _skipAnimation,
              child: Text(
                _skipLabel,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.85),
                  fontWeight: FontWeight.w500,
                  fontSize: 15,
                  decoration: TextDecoration.underline,
                  decorationColor: Colors.white54,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
