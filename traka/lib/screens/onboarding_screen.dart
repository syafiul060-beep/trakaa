import 'dart:async';

import 'package:flutter/material.dart';

import '../models/user_role.dart';
import '../services/performance_trace_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../widgets/app_update_wrapper.dart';
import '../widgets/traka_l10n_scope.dart';
import 'driver_screen.dart';
import 'penumpang_screen.dart';

const _prefOnboardingSeen = 'traka_onboarding_seen';

/// Intro screens untuk pengguna baru (faceVerificationUrl kosong).
/// Ditampilkan sekali setelah login pertama.
class OnboardingScreen extends StatefulWidget {
  final String role;

  const OnboardingScreen({super.key, required this.role});

  static Future<bool> hasSeenOnboarding() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_prefOnboardingSeen) ?? false;
  }

  static Future<void> markOnboardingSeen() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefOnboardingSeen, true);
  }

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _pageController = PageController();
  int _currentPage = 0;

  @override
  void initState() {
    super.initState();
    unawaited(PerformanceTraceService.stopStartupToInteractive());
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _onDone() async {
    await OnboardingScreen.markOnboardingSeen();
    if (!mounted) return;
    if (widget.role == UserRole.penumpang.firestoreValue) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) => const AppUpdateWrapper(child: PenumpangScreen()),
        ),
      );
    } else {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) => const AppUpdateWrapper(child: DriverScreen()),
        ),
      );
    }
  }

  List<({String title, String body, IconData icon})> _getPages(BuildContext context) {
    final l10n = TrakaL10n.of(context);
    return [
      (title: l10n.onboardingWelcome, body: l10n.onboardingWelcomeBody, icon: Icons.directions_bus),
      (title: l10n.onboardingVerify, body: l10n.onboardingVerifyBody, icon: Icons.verified_user),
      (title: l10n.onboardingReady, body: l10n.onboardingReadyBody, icon: Icons.rocket_launch),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final pages = _getPages(context);
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: PageView.builder(
                controller: _pageController,
                onPageChanged: (i) => setState(() => _currentPage = i),
                itemCount: pages.length,
                itemBuilder: (_, i) {
                  final p = pages[i];
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          p.icon,
                          size: 80,
                          color: colorScheme.primary,
                        ),
                        const SizedBox(height: 32),
                        Text(
                          p.title,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            color: colorScheme.onSurface,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          p.body,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 16,
                            height: 1.5,
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(24),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: List.generate(
                      pages.length,
                      (i) => Container(
                        margin: const EdgeInsets.symmetric(horizontal: 4),
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: i == _currentPage
                              ? colorScheme.primary
                              : colorScheme.outline.withValues(alpha: 0.4),
                        ),
                      ),
                    ),
                  ),
                  FilledButton(
                    onPressed: _onDone,
                    child: Text(
                      _currentPage < pages.length - 1
                          ? TrakaL10n.of(context).next
                          : TrakaL10n.of(context).start,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
