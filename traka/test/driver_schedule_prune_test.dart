import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:traka/services/driver_schedule_service.dart';

void main() {
  const driverUid = 'test_driver_prune';

  group('applySchedulePruneInMemory', () {
    test('keeps future in-window schedule when active set empty', () {
      final base = DateTime.now().add(const Duration(days: 2));
      final dateOnly = DateTime(base.year, base.month, base.day);
      final dep = DateTime(base.year, base.month, base.day, 14, 30);
      final sched = <String, dynamic>{
        'date': Timestamp.fromDate(dateOnly),
        'departureTime': Timestamp.fromDate(dep),
        'origin': 'Jakarta',
        'destination': 'Bandung',
      };
      final out = DriverScheduleService.applySchedulePruneInMemory(
        mapsList: [sched],
        driverUid: driverUid,
        activeScheduleIds: {},
      );
      expect(out, hasLength(1));
    });

    test('drops past departure without matching active order', () {
      final base = DateTime.now().subtract(const Duration(days: 12));
      final dateOnly = DateTime(base.year, base.month, base.day);
      final dep = DateTime(base.year, base.month, base.day, 8, 0);
      final sched = <String, dynamic>{
        'date': Timestamp.fromDate(dateOnly),
        'departureTime': Timestamp.fromDate(dep),
        'origin': 'Jakarta',
        'destination': 'Bandung',
      };
      final out = DriverScheduleService.applySchedulePruneInMemory(
        mapsList: [sched],
        driverUid: driverUid,
        activeScheduleIds: {},
      );
      expect(out, isEmpty);
    });

    test('keeps past departure when computed scheduleId is in active set', () {
      final base = DateTime.now().subtract(const Duration(days: 12));
      final dateOnly = DateTime(base.year, base.month, base.day);
      final dep = DateTime(base.year, base.month, base.day, 8, 0);
      final dateKey =
          '${dateOnly.year}-${dateOnly.month.toString().padLeft(2, '0')}-${dateOnly.day.toString().padLeft(2, '0')}';
      final (sid, _) = ScheduleIdUtil.build(
        driverUid,
        dateKey,
        dep.millisecondsSinceEpoch,
        'Jakarta',
        'Bandung',
      );
      final sched = <String, dynamic>{
        'date': Timestamp.fromDate(dateOnly),
        'departureTime': Timestamp.fromDate(dep),
        'origin': 'Jakarta',
        'destination': 'Bandung',
        'scheduleId': sid,
      };
      final out = DriverScheduleService.applySchedulePruneInMemory(
        mapsList: [sched],
        driverUid: driverUid,
        activeScheduleIds: {sid},
      );
      expect(out, hasLength(1));
    });

    test('activeScheduleIds null keeps prunable entries (ambiguous)', () {
      final base = DateTime.now().subtract(const Duration(days: 12));
      final dateOnly = DateTime(base.year, base.month, base.day);
      final dep = DateTime(base.year, base.month, base.day, 8, 0);
      final sched = <String, dynamic>{
        'date': Timestamp.fromDate(dateOnly),
        'departureTime': Timestamp.fromDate(dep),
        'origin': 'Jakarta',
        'destination': 'Bandung',
      };
      final out = DriverScheduleService.applySchedulePruneInMemory(
        mapsList: [sched],
        driverUid: driverUid,
        activeScheduleIds: null,
      );
      expect(out, hasLength(1));
    });

    test('drops calendar outside booking window without active order', () {
      final base = DateTime.now().add(const Duration(days: 30));
      final dateOnly = DateTime(base.year, base.month, base.day);
      final dep = DateTime(base.year, base.month, base.day, 10, 0);
      final sched = <String, dynamic>{
        'date': Timestamp.fromDate(dateOnly),
        'departureTime': Timestamp.fromDate(dep),
        'origin': 'A',
        'destination': 'B',
      };
      final out = DriverScheduleService.applySchedulePruneInMemory(
        mapsList: [sched],
        driverUid: driverUid,
        activeScheduleIds: {},
      );
      expect(out, isEmpty);
    });

    test('keeps prune candidate when departureTime is missing', () {
      final base = DateTime.now().subtract(const Duration(days: 40));
      final dateOnly = DateTime(base.year, base.month, base.day);
      final sched = <String, dynamic>{
        'date': Timestamp.fromDate(dateOnly),
        'origin': 'Jakarta',
        'destination': 'Bandung',
      };
      final out = DriverScheduleService.applySchedulePruneInMemory(
        mapsList: [sched],
        driverUid: driverUid,
        activeScheduleIds: {},
      );
      expect(out, hasLength(1));
    });
  });
}
