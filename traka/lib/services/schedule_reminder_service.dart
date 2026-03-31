import 'dart:async';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest_all.dart' as tz_data;

import 'route_notification_service.dart';
import 'driver_schedule_service.dart';

/// Notifikasi pengingat jadwal driver: 1 jam sebelum keberangkatan.
class ScheduleReminderService {
  static const int _reminderNotificationIdBase = 5000;
  static const int _reminderMinutesBefore = 60;

  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  static bool _tzInitialized = false;

  static void _ensureTimezone() {
    if (_tzInitialized) return;
    tz_data.initializeTimeZones();
    tz.setLocalLocation(tz.getLocation('Asia/Jakarta'));
    _tzInitialized = true;
  }

  /// Jadwalkan pengingat untuk jadwal driver yang akan datang.
  /// Dipanggil setelah load jadwal atau simpan jadwal baru.
  static Future<void> scheduleRemindersForDriver(String driverUid) async {
    if (!Platform.isAndroid) return;
    _ensureTimezone();
    await RouteNotificationService.init();
    await RouteNotificationService.requestPermissionIfNeeded();

    try {
      List<Map<String, dynamic>> list;
      try {
        list = await DriverScheduleService.readSchedulesRawFromServer(
          driverUid,
        ).timeout(const Duration(seconds: 10));
      } on TimeoutException {
        final cached = await DriverScheduleService.tryReadSchedulesRawFromCache(
          driverUid,
        );
        if (cached == null) return;
        list = cached;
      } catch (_) {
        final cached = await DriverScheduleService.tryReadSchedulesRawFromCache(
          driverUid,
        );
        if (cached == null) return;
        list = cached;
      }

      if (list.isEmpty) {
        await cancelAllReminders();
        return;
      }

      await cancelAllReminders();
      final now = DateTime.now();
      final todayStart = DateTime(now.year, now.month, now.day);

      for (var i = 0; i < list.length; i++) {
        final map = list[i];
        final dateStamp = map['date'] as Timestamp?;
        final depStamp = map['departureTime'] as Timestamp?;
        if (dateStamp == null || depStamp == null) continue;

        final dep = depStamp.toDate();
        final scheduleDate = DateTime(dep.year, dep.month, dep.day);
        if (scheduleDate.isBefore(todayStart)) continue;
        if (dep.isBefore(now)) continue;

        final reminderAt = dep.subtract(const Duration(minutes: _reminderMinutesBefore));
        if (reminderAt.isBefore(now)) continue;

        final origin = (map['origin'] as String?) ?? '';
        final dest = (map['destination'] as String?) ?? '';
        final routeText = origin.isNotEmpty && dest.isNotEmpty
            ? '$origin → $dest'
            : 'Jadwal';

        final tzReminder = tz.TZDateTime.from(reminderAt, tz.local);
        final id = _reminderNotificationIdBase + i;

        await _plugin.zonedSchedule(
          id: id,
          scheduledDate: tzReminder,
          notificationDetails: NotificationDetails(
            android: AndroidNotificationDetails(
              'traka_schedule_reminder',
              'Pengingat Jadwal',
              channelDescription: 'Notifikasi pengingat jadwal keberangkatan driver',
              importance: Importance.high,
              priority: Priority.high,
              icon: '@drawable/ic_notification',
            ),
          ),
          androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
          title: 'Pengingat Jadwal',
          body:
              '${dep.hour.toString().padLeft(2, '0')}:${dep.minute.toString().padLeft(2, '0')} — $routeText',
        );
      }
    } catch (_) {}
  }

  /// Batalkan semua pengingat jadwal driver.
  static Future<void> cancelAllReminders() async {
    for (var i = 0; i < 50; i++) {
      await _plugin.cancel(id: _reminderNotificationIdBase + i);
    }
  }
}
