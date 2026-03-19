import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import '../app_navigator.dart';
import '../firebase_options.dart';
import '../utils/app_logger.dart';
import 'notification_navigation_service.dart';
import 'route_notification_service.dart';

/// Handler untuk pesan FCM saat app di background/terminated (harus top-level).
/// Untuk data-only message, tampilkan notifikasi lokal.
bool _isDuplicateAppError(Object e) {
  final msg = e.toString().toLowerCase();
  if (msg.contains('duplicate-app') ||
      msg.contains('core/duplicate-app') ||
      msg.contains('already exists')) return true;
  try {
    final code = (e as dynamic).code as String?;
    return code?.toLowerCase() == 'duplicate-app' ||
        code?.toLowerCase() == 'core/duplicate-app';
  } catch (_) {
    return false;
  }
}

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  try {
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
    }
  } catch (e) {
    if (!_isDuplicateAppError(e)) rethrow;
  }
  try {
    // Jika pesan punya notification payload, sistem Android menampilkan otomatis.
    if (message.notification != null) return;
    final data = message.data;
    final title = data['passengerName'] ?? data['title'] ?? 'Traka';
    final body = data['body'] ?? data['message'] ?? 'Pesan baru';
    await _showBackgroundNotification(title, body);
  } catch (e, st) {
    if (kDebugMode) {
      debugPrint('[FCM] Background handler error: $e');
      debugPrint('[FCM] stack: $st');
    }
  }
}

/// Icon notifikasi: siluet mobil (putih, monokrom) untuk status bar.
const String _notificationIcon = '@drawable/ic_notification';

Future<void> _showBackgroundNotification(String title, String body) async {
  if (!Platform.isAndroid) return;
  const channelId = 'traka_chat';
  const channelName = 'Chat';
  final plugin = FlutterLocalNotificationsPlugin();
  const android = AndroidInitializationSettings(_notificationIcon);
  await plugin.initialize(const InitializationSettings(android: android));
  await plugin
      .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>()
      ?.createNotificationChannel(
        const AndroidNotificationChannel(
          channelId,
          channelName,
          description: 'Notifikasi chat dari penumpang',
          importance: Importance.max,
          enableVibration: true,
          playSound: true,
        ),
      );
  await plugin.show(
    2001,
    title,
    body,
    const NotificationDetails(
      android: AndroidNotificationDetails(
        channelId,
        channelName,
        channelDescription: 'Notifikasi chat dari penumpang',
        importance: Importance.max,
        priority: Priority.max,
        visibility: NotificationVisibility.public,
        icon: _notificationIcon,
        enableVibration: true,
        playSound: true,
      ),
    ),
  );
}

/// Service FCM: simpan token ke Firestore, tampilkan notifikasi saat foreground.
class FcmService {
  static const String _channelId = 'traka_chat';
  static const int _chatNotificationId = 2001;

  static final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();

  static bool _initialized = false;

  static Future<void> init() async {
    if (_initialized) return;
    await FirebaseMessaging.instance.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
    await _setupLocalNotifications();
    await RouteNotificationService.requestPermissionIfNeeded();
    FirebaseMessaging.onMessage.listen(_onMessageForeground);
    // Tap notifikasi saat app di background
    FirebaseMessaging.onMessageOpenedApp.listen(_onNotificationOpenedApp);
    // Tap notifikasi saat app terminated (cold start)
    final initialMessage = await FirebaseMessaging.instance.getInitialMessage();
    if (initialMessage != null && initialMessage.data.isNotEmpty) {
      final data = initialMessage.data.map((k, v) => MapEntry(k, v?.toString() ?? ''));
      _handleNotificationData(data);
    }
    // Saat token FCM di-refresh (reinstall, clear data), update Firestore
    FirebaseMessaging.instance.onTokenRefresh.listen((_) async {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) await saveTokenForUser(user.uid);
    });
    _initialized = true;
  }

  static void _onNotificationOpenedApp(RemoteMessage message) {
    final data = message.data.map((k, v) => MapEntry(k, v?.toString() ?? ''));
    _handleNotificationData(data);
  }

  static void _handleNotificationData(Map<String, String> data) {
    final context = appNavigatorKey.currentContext;
    NotificationNavigationService.handleNotificationTap(
      data,
      context: context,
    );
  }

  static Future<void> _setupLocalNotifications() async {
    const android = AndroidInitializationSettings(_notificationIcon);
    const settings = InitializationSettings(android: android);
    await _localNotifications.initialize(
      settings,
      onDidReceiveNotificationResponse: (res) {
        final payload = NotificationNavigationService.parsePayload(res.payload);
        if (payload != null) _handleNotificationData(payload);
      },
    );
    if (Platform.isAndroid) {
      await _localNotifications
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.createNotificationChannel(
            const AndroidNotificationChannel(
              _channelId,
              'Chat',
              description: 'Notifikasi chat dari penumpang',
              importance: Importance.max,
              enableVibration: true,
              playSound: true,
            ),
          );
    }
  }

  static void _onMessageForeground(RemoteMessage message) {
    try {
      final notification = message.notification;
      final data = message.data;
      final title = notification?.title ?? data['passengerName'] ?? data['title'] ?? 'Chat';
      final body = notification?.body ?? data['body'] ?? data['message'] ?? 'Pesan baru';
      final payload = data.map((k, v) => MapEntry(k, v?.toString() ?? ''));
      _showLocalNotification(title, body, payload: payload.isNotEmpty ? payload : null);
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('[FCM] _onMessageForeground error: $e');
        debugPrint('[FCM] stack: $st');
      }
    }
  }

  static Future<void> _showLocalNotification(
    String title,
    String body, {
    Map<String, String>? payload,
  }) async {
    if (!Platform.isAndroid) return;
    try {
      await RouteNotificationService.requestPermissionIfNeeded();
    } catch (e) {
      if (kDebugMode) debugPrint('[FCM] requestPermissionIfNeeded error: $e');
    }
    const androidDetails = AndroidNotificationDetails(
      _channelId,
      'Chat',
      channelDescription: 'Notifikasi chat dari penumpang',
      importance: Importance.max,
      priority: Priority.max,
      visibility: NotificationVisibility.public,
      enableVibration: true,
      playSound: true,
      icon: _notificationIcon,
    );
    const details = NotificationDetails(android: androidDetails);
    try {
      final payloadStr = payload != null && payload.isNotEmpty
          ? jsonEncode(payload)
          : null;
      await _localNotifications.show(
        _chatNotificationId,
        title,
        body,
        details,
        payload: payloadStr,
      );
    } catch (e) {
      if (kDebugMode) debugPrint('[FCM] _showLocalNotification error: $e');
    }
  }

  /// Topic untuk broadcast notifikasi dari admin.
  static const String broadcastTopic = 'traka_broadcast';

  /// Dapatkan token FCM dan simpan ke users/{uid}/fcmToken. Panggil setelah login.
  /// Juga subscribe ke topic broadcast agar bisa terima notifikasi dari admin.
  /// Pakai set(merge) agar tidak gagal jika doc belum ada.
  static Future<void> saveTokenForUser(String uid) async {
    try {
      final token = await FirebaseMessaging.instance.getToken();
      if (token == null || uid.isEmpty) {
        if (kDebugMode) {
          debugPrint('[FCM] saveTokenForUser: token kosong atau uid kosong');
        }
        return;
      }
      await FirebaseFirestore.instance.collection('users').doc(uid).set({
        'fcmToken': token,
        'fcmTokenUpdatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      await FirebaseMessaging.instance.subscribeToTopic(broadcastTopic);
      if (kDebugMode) {
        debugPrint('[FCM] saveTokenForUser: berhasil simpan token untuk uid=$uid');
      }
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('[FCM] saveTokenForUser: gagal: $e');
        debugPrint('[FCM] saveTokenForUser: stack: $st');
      }
    }
  }

  /// Hapus token saat logout (opsional, agar driver tidak dapat notifikasi dari device lama).
  static Future<void> removeTokenForUser(String uid) async {
    try {
      if (uid.isEmpty) return;
      await FirebaseFirestore.instance.collection('users').doc(uid).update({
        'fcmToken': FieldValue.delete(),
        'fcmTokenUpdatedAt': FieldValue.delete(),
      });
    } catch (e, st) {
      logError('FcmService.removeTokenForUser', e, st);
    }
  }
}
