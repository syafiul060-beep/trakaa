import 'package:flutter_test/flutter_test.dart';

import 'package:traka/services/order_service.dart';

void main() {
  group('OrderService', () {
    group('status constants', () {
      test('status constants are defined correctly', () {
        expect(OrderService.statusAgreed, 'agreed');
        expect(OrderService.statusPickedUp, 'picked_up');
        expect(OrderService.statusCompleted, 'completed');
        expect(OrderService.statusPendingAgreement, 'pending_agreement');
        expect(OrderService.statusPendingReceiver, 'pending_receiver');
        expect(OrderService.statusCancelled, 'cancelled');
      });

      test('routeJourneyNumberScheduled is scheduled', () {
        expect(OrderService.routeJourneyNumberScheduled, 'scheduled');
      });
    });

    group('radius constants', () {
      test('radius constants are positive', () {
        expect(OrderService.radiusDekatMeter, greaterThan(0));
        expect(OrderService.radiusVoiceCallKm, greaterThan(0));
        expect(OrderService.radiusBerdekatanMeter, greaterThan(0));
        expect(OrderService.radiusMenjauhMeter, greaterThan(0));
      });
    });

    group('findUserByEmailOrPhone', () {
      test('returns null for empty input', () async {
        final result = await OrderService.findUserByEmailOrPhone('');
        expect(result, isNull);
      });

      test('returns null for whitespace-only input', () async {
        final result = await OrderService.findUserByEmailOrPhone('   ');
        expect(result, isNull);
      });
    });

    group('getRecentReceivers', () {
      test('returns empty list for empty passengerUid', () async {
        final result = await OrderService.getRecentReceivers('');
        expect(result, isEmpty);
      });
    });
  });
}
