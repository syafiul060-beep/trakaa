import 'dart:async';
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
      msg.contains('already exists')) {
    return true;
  }
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
    final dataStr = message.data.map((k, v) => MapEntry(k, v?.toString() ?? ''));
    // Panggilan suara: data-only dari server + notifikasi lokal (fullScreenIntent) agar
    // tidak tertunda saat Doze/layar mati (bukan hanya saat buka layar).
    if (dataStr['type'] == 'voice_call') {
      await FcmService.showVoiceCallBackgroundNotification(dataStr);
      return;
    }
    if (dataStr['type'] == 'chat') {
      await FcmService.showChatBackgroundNotification(dataStr);
      return;
    }
    if (dataStr['type'] == 'admin_verification') {
      final title = dataStr['title'] ?? 'Permintaan verifikasi';
      final body = dataStr['body'] ??
          'Admin meminta dokumen atau data tambahan. Buka Profil di aplikasi.';
      await RouteNotificationService.showAdminVerificationNotification(
        title: title,
        body: body,
      );
      return;
    }
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
  /// Saluran khusus panggilan (prioritas max + fullScreenIntent di background).
  static const String _voiceChannelId = 'traka_voice_calls';
  static const int _chatNotificationId = 2001;
  static const int _voiceNotificationIdBase = 3001;

  /// ID unik per order agar notifikasi chat tidak saling timpa antar pesanan.
  static int _notificationIdForChatOrder(String orderId) {
    if (orderId.isEmpty) return _chatNotificationId;
    return 2000000 + (orderId.hashCode.abs() % 500000);
  }

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
      final androidPlugin = _localNotifications
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      await androidPlugin?.createNotificationChannel(
        const AndroidNotificationChannel(
          _channelId,
          'Chat',
          description: 'Notifikasi chat dari penumpang',
          importance: Importance.max,
          enableVibration: true,
          playSound: true,
        ),
      );
      await androidPlugin?.createNotificationChannel(
        const AndroidNotificationChannel(
          _voiceChannelId,
          'Panggilan suara',
          description: 'Panggilan masuk dari penumpang atau driver',
          importance: Importance.max,
          enableVibration: true,
          playSound: true,
        ),
      );
    }
  }

  /// Dipanggil dari isolate background saat FCM data-only `type: chat` (Android).
  static Future<void> showChatBackgroundNotification(
    Map<String, String> data,
  ) async {
    if (!Platform.isAndroid) return;
    final title = data['title'] ?? data['senderName'] ?? 'Chat';
    final body = data['body'] ?? data['message'] ?? 'Pesan baru';
    final plugin = FlutterLocalNotificationsPlugin();
    const android = AndroidInitializationSettings(_notificationIcon);
    await plugin.initialize(const InitializationSettings(android: android));
    await plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
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
    final payloadStr = jsonEncode(data);
    final nid = _notificationIdForChatOrder(data['orderId'] ?? '');
    await plugin.show(
      nid,
      title,
      body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          'Chat',
          channelDescription: 'Notifikasi chat dari penumpang',
          importance: Importance.max,
          priority: Priority.max,
          visibility: NotificationVisibility.public,
          category: AndroidNotificationCategory.message,
          icon: _notificationIcon,
          enableVibration: true,
          playSound: true,
        ),
      ),
      payload: payloadStr,
    );
  }

  /// Dipanggil dari isolate background saat FCM data-only `type: voice_call` (Android).
  static Future<void> showVoiceCallBackgroundNotification(
    Map<String, String> data,
  ) async {
    if (!Platform.isAndroid) return;
    final title = data['title'] ?? 'Panggilan suara masuk';
    final body = data['body'] ??
        '${data['callerName'] ?? 'Pemanggil'} memanggil Anda. Buka aplikasi untuk menerima.';
    final plugin = FlutterLocalNotificationsPlugin();
    const android = AndroidInitializationSettings(_notificationIcon);
    await plugin.initialize(const InitializationSettings(android: android));
    await plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(
          const AndroidNotificationChannel(
            _voiceChannelId,
            'Panggilan suara',
            description: 'Panggilan masuk dari penumpang atau driver',
            importance: Importance.max,
            enableVibration: true,
            playSound: true,
          ),
        );
    final payloadStr = jsonEncode(data);
    final orderId = data['orderId'] ?? '';
    final nid = _voiceNotificationIdBase +
        (orderId.isEmpty ? 0 : orderId.hashCode.abs() % 900000);
    await plugin.show(
      nid,
      title,
      body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          _voiceChannelId,
          'Panggilan suara',
          channelDescription: 'Panggilan masuk dari penumpang atau driver',
          importance: Importance.max,
          priority: Priority.max,
          visibility: NotificationVisibility.public,
          category: AndroidNotificationCategory.call,
          fullScreenIntent: true,
          icon: _notificationIcon,
          enableVibration: true,
          playSound: true,
          ongoing: false,
          autoCancel: true,
        ),
      ),
      payload: payloadStr,
    );
  }

  static Future<void> _showChatForegroundNotification(
    Map<String, String> dataStr,
  ) async {
    if (!Platform.isAndroid) return;
    try {
      await RouteNotificationService.requestPermissionIfNeeded();
    } catch (_) {}
    final title = dataStr['title'] ?? dataStr['senderName'] ?? 'Chat';
    final body = dataStr['body'] ?? dataStr['message'] ?? 'Pesan baru';
    final payloadStr = jsonEncode(dataStr);
    final nid = _notificationIdForChatOrder(dataStr['orderId'] ?? '');
    await _localNotifications.show(
      nid,
      title,
      body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          'Chat',
          channelDescription: 'Notifikasi chat dari penumpang',
          importance: Importance.max,
          priority: Priority.max,
          visibility: NotificationVisibility.public,
          category: AndroidNotificationCategory.message,
          icon: _notificationIcon,
          enableVibration: true,
          playSound: true,
        ),
      ),
      payload: payloadStr,
    );
  }

  static Future<void> _showVoiceCallForegroundNotification(
    Map<String, String> dataStr,
  ) async {
    if (!Platform.isAndroid) return;
    try {
      await RouteNotificationService.requestPermissionIfNeeded();
    } catch (_) {}
    final title = dataStr['title'] ?? 'Panggilan suara masuk';
    final body = dataStr['body'] ??
        '${dataStr['callerName'] ?? 'Pemanggil'} memanggil Anda. Buka aplikasi untuk menerima.';
    final payloadStr = jsonEncode(dataStr);
    final orderId = dataStr['orderId'] ?? '';
    final nid = _voiceNotificationIdBase +
        (orderId.isEmpty ? 0 : orderId.hashCode.abs() % 900000);
    await _localNotifications.show(
      nid,
      title,
      body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          _voiceChannelId,
          'Panggilan suara',
          channelDescription: 'Panggilan masuk dari penumpang atau driver',
          importance: Importance.max,
          priority: Priority.max,
          visibility: NotificationVisibility.public,
          category: AndroidNotificationCategory.call,
          fullScreenIntent: false,
          icon: _notificationIcon,
          enableVibration: true,
          playSound: true,
          ongoing: false,
          autoCancel: true,
        ),
      ),
      payload: payloadStr,
    );
  }

  static void _onMessageForeground(RemoteMessage message) {
    try {
      final data = message.data;
      final dataStr = data.map((k, v) => MapEntry(k, v?.toString() ?? ''));
      if (dataStr['type'] == 'voice_call') {
        unawaited(_showVoiceCallForegroundNotification(dataStr));
        return;
      }
      if (dataStr['type'] == 'chat') {
        unawaited(_showChatForegroundNotification(dataStr));
        return;
      }
      if (dataStr['type'] == 'admin_verification') {
        final notification = message.notification;
        final title = notification?.title ??
            data['title'] ??
            'Permintaan verifikasi';
        final body = notification?.body ??
            data['body'] ??
            'Buka Profil untuk melengkapi data.';
        unawaited(
          RouteNotificationService.showAdminVerificationNotification(
            title: title,
            body: body,
          ),
        );
        return;
      }
      final notification = message.notification;
      final title = notification?.title ??
          data['passengerName'] ??
          data['title'] ??
          data['senderName'] ??
          'Chat';
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
    int? notificationId,
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
      final nid = notificationId ?? _chatNotificationId;
      await _localNotifications.show(
        nid,
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
