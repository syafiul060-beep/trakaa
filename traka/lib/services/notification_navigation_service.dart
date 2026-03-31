import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../models/user_role.dart';
import '../screens/admin_chat_screen.dart';
import '../screens/chat_driver_screen.dart';
import '../screens/chat_room_penumpang_screen.dart';
import '../screens/contribution_driver_screen.dart';
import '../screens/voice_call_screen.dart';
import 'order_service.dart';

/// Service untuk menangani navigasi saat pengguna tap notifikasi.
/// Mendukung: chat, payment_reminder (kontribusi/pelanggaran), admin_verification.
class NotificationNavigationService {
  NotificationNavigationService._();

  static Map<String, String>? _pendingData;

  /// Callback dari [PenumpangScreen]/[DriverScreen] — buka tab Profil (index 4).
  static void Function()? _openProfileTab;
  static void registerOpenProfileTab(void Function() fn) {
    _openProfileTab = fn;
  }

  static void unregisterOpenProfileTab() {
    _openProfileTab = null;
  }

  /// Simpan data notifikasi untuk navigasi nanti (saat app belum siap).
  static void setPending(Map<String, String> data) {
    _pendingData = Map.from(data);
  }

  /// Cek dan jalankan navigasi tertunda. Dipanggil saat home screen (Driver/Penumpang) mount.
  static void maybeExecutePendingNavigation(BuildContext context) {
    final data = _pendingData;
    if (data == null || data.isEmpty) return;
    _pendingData = null;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (context.mounted) _navigateFromNotificationData(context, data);
    });
  }

  /// Handle tap notifikasi. Bisa dipanggil langsung (app sudah di home) atau simpan untuk nanti.
  static void handleNotificationTap(Map<String, String> data, {BuildContext? context}) {
    if (context != null && context.mounted) {
      _navigateFromNotificationData(context, data);
    } else {
      setPending(data);
    }
  }

  static Future<void> _navigateFromNotificationData(
    BuildContext context,
    Map<String, String> data,
  ) async {
    final type = data['type'];
    if (type == null) return;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    if (type == 'admin_support') {
      if (!context.mounted) return;
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => const AdminChatScreen(),
        ),
      );
      return;
    }

    final role = await _getUserRole(user.uid);
    if (role == null) return;

    if (!context.mounted) return;

    switch (type) {
      case 'chat':
        await _navigateToChat(context, data, role);
        break;
      case 'order':
      case 'order_agreed':
        await _navigateToChat(context, data, role);
        break;
      case 'payment_reminder':
        _navigateToPaymentReminder(context, data, role);
        break;
      case 'admin_verification':
        _openProfileTab?.call();
        break;
      case 'voice_call':
        _navigateToVoiceCall(context, data);
        break;
      default:
        break;
    }
  }

  static Future<UserRole?> _getUserRole(String uid) async {
    try {
      final doc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
      final r = doc.data()?['role'] as String?;
      return r?.toUserRoleOrNull;
    } catch (_) {
      return null;
    }
  }

  static Future<void> _navigateToChat(
    BuildContext context,
    Map<String, String> data,
    UserRole role,
  ) async {
    final orderId = data['orderId'];
    if (orderId == null || orderId.isEmpty) return;

    if (role == UserRole.driver) {
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => ChatDriverScreen(orderId: orderId),
        ),
      );
      return;
    }

    // Penumpang: butuh driverUid, driverName dari order
    final driverUid = data['driverUid'];
    final driverName = data['driverName'] ?? 'Driver';
    if (driverUid != null && driverUid.isNotEmpty) {
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => ChatRoomPenumpangScreen(
            orderId: orderId,
            driverUid: driverUid,
            driverName: driverName,
          ),
        ),
      );
      return;
    }

    // Fallback: fetch order untuk dapat driverUid, lalu ambil driverName dari users
    try {
      final order = await OrderService.getOrderById(orderId);
      if (order == null || !context.mounted) return;
      String driverName = 'Driver';
      try {
        final userDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(order.driverUid)
            .get();
        final dn = userDoc.data()?['displayName'] as String?;
        if (dn != null && dn.trim().isNotEmpty) driverName = dn.trim();
      } catch (_) {}
      if (!context.mounted) return;
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => ChatRoomPenumpangScreen(
            orderId: orderId,
            driverUid: order.driverUid,
            driverName: driverName,
          ),
        ),
      );
    } catch (_) {}
  }

  static void _navigateToVoiceCall(BuildContext context, Map<String, String> data) {
    final orderId = data['orderId'];
    final callerUid = data['callerUid'];
    final callerName = data['callerName'] ?? 'Pemanggil';
    if (orderId == null || orderId.isEmpty || callerUid == null || callerUid.isEmpty) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => VoiceCallScreen(
          orderId: orderId,
          remoteUid: callerUid,
          remoteName: callerName,
          remotePhotoUrl: null,
          isCaller: false,
        ),
      ),
    );
  }

  static void _navigateToPaymentReminder(
    BuildContext context,
    Map<String, String> data,
    UserRole role,
  ) {
    if (role != UserRole.driver) return;
    final paymentType = data['paymentType'] ?? 'kontribusi';
    if (paymentType == 'kontribusi' || paymentType == 'pelanggaran') {
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => const ContributionDriverScreen(),
        ),
      );
    }
  }

  /// Parse payload string (JSON) dari local notification.
  static Map<String, String>? parsePayload(String? payloadStr) {
    if (payloadStr == null || payloadStr.isEmpty) return null;
    try {
      final decoded = jsonDecode(payloadStr);
      if (decoded is! Map) return null;
      return decoded.map((k, v) => MapEntry(k.toString(), v?.toString() ?? ''));
    } catch (_) {
      return null;
    }
  }
}
