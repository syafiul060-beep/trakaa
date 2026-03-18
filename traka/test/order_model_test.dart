import 'package:flutter_test/flutter_test.dart';

import 'package:traka/models/order_model.dart';

void main() {
  group('OrderModel', () {
    group('type constants', () {
      test('typeTravel is travel', () {
        expect(OrderModel.typeTravel, 'travel');
      });

      test('typeKirimBarang is kirim_barang', () {
        expect(OrderModel.typeKirimBarang, 'kirim_barang');
      });

      test('barangCategoryDokumen is dokumen', () {
        expect(OrderModel.barangCategoryDokumen, 'dokumen');
      });

      test('barangCategoryKargo is kargo', () {
        expect(OrderModel.barangCategoryKargo, 'kargo');
      });
    });

    group('isTravel and isKirimBarang getters', () {
      test('isTravel true when orderType is travel', () {
        final order = _createMinimalOrder(orderType: OrderModel.typeTravel);
        expect(order.isTravel, true);
        expect(order.isKirimBarang, false);
      });

      test('isKirimBarang true when orderType is kirim_barang', () {
        final order = _createMinimalOrder(orderType: OrderModel.typeKirimBarang);
        expect(order.isKirimBarang, true);
        expect(order.isTravel, false);
      });
    });
  });
}

OrderModel _createMinimalOrder({String orderType = OrderModel.typeTravel}) {
  return OrderModel(
    id: 'test-id',
    passengerUid: 'p1',
    driverUid: 'd1',
    routeJourneyNumber: 'r1',
    passengerName: 'Test',
    originText: 'A',
    destText: 'B',
    status: 'agreed',
    driverAgreed: true,
    passengerAgreed: true,
    driverCancelled: false,
    passengerCancelled: false,
    adminCancelled: false,
    orderType: orderType,
    chatHiddenByPassenger: false,
    chatHiddenByDriver: false,
    chatHiddenByReceiver: false,
  );
}
