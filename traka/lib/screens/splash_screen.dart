import 'package:flutter/material.dart';
import 'dart:async';

import 'package:google_fonts/google_fonts.dart';

import '../theme/app_theme.dart';

/// Splash screen dengan animasi bertahap: logo, TRAKA, Travel Kalimantan, One Touch Solution.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _logoFade;
  late Animation<double> _trakaFade;
  late Animation<Offset> _trakaSlide;
  late Animation<double> _subtitleFade;
  late Animation<double> _taglineFade;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      duration: const Duration(milliseconds: 1800),
      vsync: this,
    );

    _logoFade = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _controller, curve: const Interval(0, 0.25, curve: Curves.easeOut)),
    );
    _trakaFade = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _controller, curve: const Interval(0.15, 0.45, curve: Curves.easeOut)),
    );
    _trakaSlide = Tween<Offset>(
      begin: const Offset(0, 0.3),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _controller, curve: const Interval(0.15, 0.45, curve: Curves.easeOutCubic)));
    _subtitleFade = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _controller, curve: const Interval(0.35, 0.6, curve: Curves.easeOut)),
    );
    _taglineFade = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _controller, curve: const Interval(0.5, 0.75, curve: Curves.easeOut)),
    );

    _controller.forward();

    Timer(const Duration(milliseconds: 2500), () {
      if (mounted) {
        // Navigator di-handle dari main.dart (cek auth status)
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Logo Traka — fade in
            FadeTransition(
              opacity: _logoFade,
              child: Image.asset(
                'assets/images/logo_traka.png',
                width: 200,
                height: 200,
                fit: BoxFit.contain,
              ),
            ),
            const SizedBox(height: 32),
            // TRAKA — fade + slide up
            FadeTransition(
              opacity: _trakaFade,
              child: SlideTransition(
                position: _trakaSlide,
                child: Text(
                  'TRAKA',
                  style: GoogleFonts.poppins(
                    color: Colors.white,
                    fontSize: 44,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 10,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            // Travel Kalimantan — fade in
            FadeTransition(
              opacity: _subtitleFade,
              child: Text(
                'Travel Kalimantan',
                style: GoogleFonts.poppins(
                  color: Colors.white.withValues(alpha: 0.95),
                  fontSize: 22,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 2,
                ),
              ),
            ),
            const SizedBox(height: 6),
            // One Touch Solution — tagline, lebih kecil
            FadeTransition(
              opacity: _taglineFade,
              child: Text(
                'One Touch Solution',
                style: GoogleFonts.poppins(
                  color: Colors.white.withValues(alpha: 0.75),
                  fontSize: 14,
                  fontWeight: FontWeight.w400,
                  letterSpacing: 3,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),
            const SizedBox(height: 48),
            // Loading indicator
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
    );
  }
}
