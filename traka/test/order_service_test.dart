import 'package:flutter_test/flutter_test.dart';

import 'package:traka/models/order_model.dart';
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

    group('passenger home blocking (travel)', () {
      OrderModel o({
        required String orderType,
        required String status,
        String driverUid = 'd',
        String id = 't',
      }) {
        return OrderModel(
          id: id,
          passengerUid: 'p',
          driverUid: driverUid,
          routeJourneyNumber: 'r',
          passengerName: 'P',
          originText: 'A',
          destText: 'B',
          status: status,
          driverAgreed: false,
          passengerAgreed: false,
          orderType: orderType,
          chatHiddenByPassenger: false,
          chatHiddenByDriver: false,
          chatHiddenByReceiver: false,
        );
      }

      test('travel pending_agreement does not block home map', () {
        expect(
          OrderService.isTravelOrderBlockingPassengerHomeMap(
            o(orderType: OrderModel.typeTravel, status: OrderService.statusPendingAgreement),
          ),
          false,
        );
      });

      test('travel picked_up blocks home map', () {
        expect(
          OrderService.isTravelOrderBlockingPassengerHomeMap(
            o(orderType: OrderModel.typeTravel, status: OrderService.statusPickedUp),
          ),
          true,
        );
      });

      test('travel agreed blocks home map', () {
        expect(
          OrderService.isTravelOrderBlockingPassengerHomeMap(
            o(orderType: OrderModel.typeTravel, status: OrderService.statusAgreed),
          ),
          true,
        );
      });

      test('travel completed does not block', () {
        expect(
          OrderService.isTravelOrderBlockingPassengerHomeMap(
            o(orderType: OrderModel.typeTravel, status: OrderService.statusCompleted),
          ),
          false,
        );
      });

      test('travel cancelled does not block', () {
        expect(
          OrderService.isTravelOrderBlockingPassengerHomeMap(
            o(orderType: OrderModel.typeTravel, status: OrderService.statusCancelled),
          ),
          false,
        );
      });

      test('kirim_barang agreed does not block passenger home', () {
        expect(
          OrderService.isTravelOrderBlockingPassengerHomeMap(
            o(orderType: OrderModel.typeKirimBarang, status: OrderService.statusAgreed),
          ),
          false,
        );
      });

      test('passengerOrdersContainBlockingTravel is true if any travel agreed or picked_up', () {
        expect(
          OrderService.passengerOrdersContainBlockingTravel([
            o(orderType: OrderModel.typeKirimBarang, status: OrderService.statusAgreed),
            o(orderType: OrderModel.typeTravel, status: OrderService.statusPendingAgreement),
          ]),
          false,
        );
        expect(
          OrderService.passengerOrdersContainBlockingTravel([
            o(orderType: OrderModel.typeKirimBarang, status: OrderService.statusAgreed),
            o(orderType: OrderModel.typeTravel, status: OrderService.statusAgreed),
          ]),
          true,
        );
      });

      test('isOrderAgreedOrPickedUp true for both types', () {
        expect(
          OrderService.isOrderAgreedOrPickedUp(
            o(orderType: OrderModel.typeTravel, status: OrderService.statusAgreed),
          ),
          true,
        );
        expect(
          OrderService.isOrderAgreedOrPickedUp(
            o(orderType: OrderModel.typeKirimBarang, status: OrderService.statusPickedUp),
          ),
          true,
        );
        expect(
          OrderService.isOrderAgreedOrPickedUp(
            o(orderType: OrderModel.typeTravel, status: OrderService.statusPendingAgreement),
          ),
          false,
        );
      });

      test('travelAgreedDriverUidsFromOrders', () {
        final agreed = o(
          orderType: OrderModel.typeTravel,
          status: OrderService.statusAgreed,
          driverUid: 'd1',
        );
        expect(
          OrderService.travelAgreedDriverUidsFromOrders([agreed]),
          {'d1'},
        );
        expect(
          OrderService.travelAgreedDriverUidsFromOrders([
            o(
              orderType: OrderModel.typeKirimBarang,
              status: OrderService.statusAgreed,
              driverUid: 'x',
            ),
          ]),
          isEmpty,
        );
      });

      test('isPassengerTravelPendingLockedOtherDriver', () {
        final agreed = o(
          orderType: OrderModel.typeTravel,
          status: OrderService.statusAgreed,
          driverUid: 'd1',
        );
        final pendingOther = o(
          id: 't2',
          orderType: OrderModel.typeTravel,
          status: OrderService.statusPendingAgreement,
          driverUid: 'd2',
        );
        final pendingSame = o(
          id: 't3',
          orderType: OrderModel.typeTravel,
          status: OrderService.statusPendingAgreement,
          driverUid: 'd1',
        );
        expect(
          OrderService.isPassengerTravelPendingLockedOtherDriver(
            pendingOther,
            OrderService.travelAgreedDriverUidsFromOrders([agreed]),
          ),
          true,
        );
        expect(
          OrderService.isPassengerTravelPendingLockedOtherDriver(
            pendingSame,
            OrderService.travelAgreedDriverUidsFromOrders([agreed]),
          ),
          false,
        );
        expect(
          OrderService.isPassengerTravelPendingLockedOtherDriver(
            o(
              orderType: OrderModel.typeKirimBarang,
              status: OrderService.statusPendingAgreement,
              driverUid: 'd2',
            ),
            OrderService.travelAgreedDriverUidsFromOrders([agreed]),
          ),
          false,
        );
      });
    });
  });
}
