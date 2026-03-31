import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/user_role.dart';
import 'passenger_proximity_notification_service.dart';
import 'receiver_proximity_notification_service.dart';

/// Mengatur [PassengerProximityNotificationService] dan [ReceiverProximityNotificationService]
/// agar hanya berjalan untuk sesi **penumpang**, mengurangi subscribe Firestore saat login driver.
class RoleBasedProximitySession {
  RoleBasedProximitySession._();

  /// Sync dari string `role` dokumen Firestore (`penumpang` / `driver`).
  static void applyForFirestoreRole(String? role) {
    final r = (role ?? '').trim().toLowerCase();
    if (r == UserRole.penumpang.name) {
      PassengerProximityNotificationService.start();
      ReceiverProximityNotificationService.start();
    } else {
      PassengerProximityNotificationService.stop();
      ReceiverProximityNotificationService.stop();
    }
  }

  /// Untuk [authStateChanges]: baca `users/{uid}.role` lalu terapkan. Tanpa user → stop.
  static Future<void> applyForCurrentUserFromFirestore() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      PassengerProximityNotificationService.stop();
      ReceiverProximityNotificationService.stop();
      return;
    }
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get(const GetOptions(source: Source.serverAndCache))
          .timeout(const Duration(seconds: 6));
      final role = doc.data()?['role'] as String?;
      applyForFirestoreRole(role);
    } on TimeoutException {
      try {
        final doc = await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .get(const GetOptions(source: Source.cache))
            .timeout(const Duration(seconds: 2));
        final role = doc.data()?['role'] as String?;
        applyForFirestoreRole(role);
      } catch (_) {
        PassengerProximityNotificationService.stop();
        ReceiverProximityNotificationService.stop();
      }
    } catch (_) {
      try {
        final doc = await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .get(const GetOptions(source: Source.cache))
            .timeout(const Duration(seconds: 2));
        final role = doc.data()?['role'] as String?;
        applyForFirestoreRole(role);
      } catch (_) {
        PassengerProximityNotificationService.stop();
        ReceiverProximityNotificationService.stop();
      }
    }
  }
}
