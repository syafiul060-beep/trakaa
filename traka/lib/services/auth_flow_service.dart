import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../models/user_role.dart';
import 'fcm_service.dart';
import 'verification_service.dart';
import 'voice_call_incoming_service.dart';
import '../screens/driver_screen.dart';
import '../screens/onboarding_screen.dart';
import '../screens/penumpang_screen.dart';
import '../screens/reverify_face_screen.dart';
import '../widgets/app_update_wrapper.dart';

/// Service terpusat untuk alur auth: cek device conflict dan navigasi ke home.
/// Mengurangi duplikasi antara main.dart (cold start) dan login_screen (post login).
class AuthFlowService {
  AuthFlowService._();

  /// Cek apakah device ID saat ini sudah dipakai akun lain dengan role yang sama.
  /// Return true jika konflik (bukan akun ini yang pakai).
  static Future<bool> hasDeviceConflict(
    String uid,
    String? role,
    String? currentDeviceId,
  ) async {
    if (currentDeviceId == null ||
        currentDeviceId.isEmpty ||
        role == null) return false;
    final q = await FirebaseFirestore.instance
        .collection('users')
        .where('deviceId', isEqualTo: currentDeviceId)
        .where('role', isEqualTo: role)
        .limit(1)
        .get(GetOptions(source: Source.server));
    if (q.docs.isEmpty) return false;
    return q.docs.first.id != uid;
  }

  /// Navigasi ke home berdasarkan role dan data user.
  /// [skipReverifyCheck]: true untuk post-login (user baru verifikasi), false untuk cold start.
  static Future<void> navigateToHome(
    BuildContext context, {
    required String uid,
    required String role,
    required Map<String, dynamic> userData,
    bool skipReverifyCheck = false,
  }) async {
    final userRole = role.toUserRoleOrNull;
    if (userRole == null) return;

    FcmService.saveTokenForUser(uid);
    VoiceCallIncomingService.start(uid);

    final faceUrl = (userData['faceVerificationUrl'] as String?)?.trim();
    final hasFacePhoto = faceUrl != null && faceUrl.isNotEmpty;
    final seenOnboarding = await OnboardingScreen.hasSeenOnboarding();
    final needsReverify =
        !skipReverifyCheck && VerificationService.needsFaceReverify(userData);

    if (!context.mounted) return;

    ScaffoldMessenger.of(context).hideCurrentSnackBar();

    if (!hasFacePhoto && !seenOnboarding) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) => AppUpdateWrapper(
            child: OnboardingScreen(role: userRole.firestoreValue),
          ),
        ),
      );
    } else if (hasFacePhoto && needsReverify) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) => AppUpdateWrapper(
            child: ReverifyFaceScreen(
              role: userRole.firestoreValue,
              onSuccess: () {
                if (!context.mounted) return;
                if (userRole == UserRole.penumpang) {
                  Navigator.of(context).pushReplacement(
                    MaterialPageRoute<void>(
                      builder: (_) =>
                          const AppUpdateWrapper(child: PenumpangScreen()),
                    ),
                  );
                } else {
                  Navigator.of(context).pushReplacement(
                    MaterialPageRoute<void>(
                      builder: (_) =>
                          const AppUpdateWrapper(child: DriverScreen()),
                    ),
                  );
                }
              },
            ),
          ),
        ),
      );
    } else if (userRole == UserRole.penumpang) {
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
}
