import 'package:flutter_test/flutter_test.dart';
import 'package:traka/services/schedule_id_util.dart';

void main() {
  group('ScheduleIdUtil', () {
    test('tryParseDateKey reads date from new format', () {
      const uid = 'abcDriverUid123';
      const date = '2025-03-24';
      const legacy = '${uid}_${date}_1742784000000';
      const scheduleId = '${legacy}_hdeadbeef';
      expect(ScheduleIdUtil.tryParseDateKey(scheduleId), date);
      expect(ScheduleIdUtil.toLegacy(scheduleId), legacy);
    });

    test('tryParseDateKey reads legacy id without hash', () {
      const sid = 'abcDriverUid123_2025-12-01_1700000000000';
      expect(ScheduleIdUtil.tryParseDateKey(sid), '2025-12-01');
    });

    test('scheduleIdDateMatchesTodayWib when parse fails', () {
      expect(
        ScheduleIdUtil.scheduleIdDateMatchesTodayWib('not_a_valid_id', '2025-01-01'),
        isTrue,
      );
    });

    test('scheduleIdDateMatchesTodayWib compares to today string', () {
      const sid = 'u_2030-06-15_1';
      expect(
        ScheduleIdUtil.scheduleIdDateMatchesTodayWib(sid, '2030-06-15'),
        isTrue,
      );
      expect(
        ScheduleIdUtil.scheduleIdDateMatchesTodayWib(sid, '2030-06-16'),
        isFalse,
      );
    });

    test('empty scheduleId matches (no gate)', () {
      expect(
        ScheduleIdUtil.scheduleIdDateMatchesTodayWib('', '2025-01-01'),
        isTrue,
      );
    });
  });
}
