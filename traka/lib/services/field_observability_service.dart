import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';

/// Breadcrumb + custom keys Crashlytics untuk konteks lapangan (tab aktif, navigasi).
/// Membantu menginterpretasi crash/ANR trace di Firebase & Play Console.
class FieldObservabilityService {
  FieldObservabilityService._();

  /// Nama tab konsisten untuk log & custom key (0–4 = bottom nav utama).
  @visibleForTesting
  static String tabNameFromIndex(int index) {
    switch (index) {
      case 0:
        return 'home_map';
      case 1:
        return 'schedule_or_pesan';
      case 2:
        return 'chat';
      case 3:
        return 'orders';
      case 4:
        return 'profile';
      default:
        return 'unknown_$index';
    }
  }

  static void syncDriverHome({
    required int tabIndex,
    required bool routeNavActive,
    String? orderNavigationId,
  }) {
    final tab = tabNameFromIndex(tabIndex);
    final orderBit =
        orderNavigationId != null && orderNavigationId.isNotEmpty
            ? ' order=$orderNavigationId'
            : '';
    final line =
        '[Field] driver tab=$tab navigating=$routeNavActive$orderBit';
    if (kDebugMode) {
      debugPrint(line);
    }
    try {
      FirebaseCrashlytics.instance.log(line);
      FirebaseCrashlytics.instance.setCustomKey('driver_tab', tab);
      FirebaseCrashlytics.instance.setCustomKey('driver_route_nav', routeNavActive);
      FirebaseCrashlytics.instance.setCustomKey(
        'driver_order_nav_id',
        orderNavigationId ?? '',
      );
    } catch (_) {}
  }

  static void syncPassengerHome({
    required int tabIndex,
    required bool trackingDrivers,
  }) {
    final tab = tabNameFromIndex(tabIndex);
    final line =
        '[Field] passenger tab=$tab tracking_map=$trackingDrivers';
    if (kDebugMode) {
      debugPrint(line);
    }
    try {
      FirebaseCrashlytics.instance.log(line);
      FirebaseCrashlytics.instance.setCustomKey('passenger_tab', tab);
      FirebaseCrashlytics.instance.setCustomKey(
        'passenger_tracking_drivers',
        trackingDrivers,
      );
    } catch (_) {}
  }
}
