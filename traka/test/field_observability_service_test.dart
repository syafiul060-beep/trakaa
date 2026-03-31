import 'package:flutter_test/flutter_test.dart';
import 'package:traka/services/field_observability_service.dart';

void main() {
  group('FieldObservabilityService.tabNameFromIndex', () {
    test('maps 0–4 to stable ids', () {
      expect(FieldObservabilityService.tabNameFromIndex(0), 'home_map');
      expect(FieldObservabilityService.tabNameFromIndex(1), 'schedule_or_pesan');
      expect(FieldObservabilityService.tabNameFromIndex(2), 'chat');
      expect(FieldObservabilityService.tabNameFromIndex(3), 'orders');
      expect(FieldObservabilityService.tabNameFromIndex(4), 'profile');
    });

    test('unknown index is prefixed', () {
      expect(FieldObservabilityService.tabNameFromIndex(9), 'unknown_9');
    });
  });
}
