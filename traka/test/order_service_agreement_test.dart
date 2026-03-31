import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:traka/models/order_model.dart';
import 'package:traka/services/order_number_service.dart';
import 'package:traka/services/order_service.dart';

void main() {
  const passengerUid = 'passenger_uid_test';
  const driverUid = 'driver_uid_test';
  const orderId = 'order_agreement_test';

  late FakeFirebaseFirestore firestore;

  void bindTestHarness({required String uid}) {
    OrderService.firestoreForTesting = firestore;
    OrderService.authForTesting = MockFirebaseAuth(
      signedIn: true,
      mockUser: MockUser(uid: uid),
    );
    OrderNumberService.generateOrderNumberOverride = () async => 'TRK-TEST-001';
  }

  tearDown(() {
    OrderService.firestoreForTesting = null;
    OrderService.authForTesting = null;
    OrderNumberService.generateOrderNumberOverride = null;
  });

  group('OrderService agreement (fake Firestore)', () {
    setUp(() {
      firestore = FakeFirebaseFirestore();
    });

    Future<void> seedDriverCapacityUser({int maxPassengers = 10}) async {
      await firestore.collection('users').doc(driverUid).set({
        'vehicleJumlahPenumpang': maxPassengers,
      });
    }

    test('setPassengerAgreed: driver belum setuju → hanya passengerAgreed', () async {
      bindTestHarness(uid: passengerUid);
      await firestore.collection('orders').doc(orderId).set({
        'passengerUid': passengerUid,
        'driverUid': driverUid,
        'driverAgreed': false,
        'passengerAgreed': false,
        'status': OrderService.statusPendingAgreement,
        'orderType': OrderModel.typeTravel,
      });

      final result = await OrderService.setPassengerAgreed(
        orderId,
        passengerLat: -0.1,
        passengerLng: 110.2,
        passengerLocationText: 'Jl. Uji',
      );

      expect(result.$1, true);
      expect(result.$2, isNull);
      expect(result.$3, true);

      final snap = await firestore.collection('orders').doc(orderId).get();
      final d = snap.data()!;
      expect(d['passengerAgreed'], true);
      expect(d['status'], OrderService.statusPendingAgreement);
    });

    test('setPassengerAgreed: idempoten saat sudah agreed', () async {
      bindTestHarness(uid: passengerUid);
      const barcode = 'TRAKA:$orderId:D:PICKUP:fixture';
      await firestore.collection('orders').doc(orderId).set({
        'passengerUid': passengerUid,
        'driverUid': driverUid,
        'driverAgreed': true,
        'passengerAgreed': true,
        'status': OrderService.statusAgreed,
        'orderType': OrderModel.typeTravel,
        'driverBarcodePickupPayload': barcode,
        'orderNumber': 'TRK-EXIST',
      });

      final result = await OrderService.setPassengerAgreed(
        orderId,
        passengerLat: 1,
        passengerLng: 2,
        passengerLocationText: 'x',
      );

      expect(result.$1, true);
      expect(result.$2, barcode);
      expect(result.$3, false);
    });

    test('setPassengerAgreed: driver setuju → status agreed + nomor + barcode', () async {
      bindTestHarness(uid: passengerUid);
      await seedDriverCapacityUser();
      await firestore.collection('orders').doc(orderId).set({
        'passengerUid': passengerUid,
        'driverUid': driverUid,
        'driverAgreed': true,
        'passengerAgreed': false,
        'status': OrderService.statusPendingAgreement,
        'orderType': OrderModel.typeTravel,
      });

      final result = await OrderService.setPassengerAgreed(
        orderId,
        passengerLat: -0.1,
        passengerLng: 110.2,
        passengerLocationText: 'Jl. Uji',
      );

      expect(result.$1, true);
      expect(result.$2, startsWith('TRAKA:$orderId:D:PICKUP:'));
      expect(result.$3, true);

      final snap = await firestore.collection('orders').doc(orderId).get();
      final d = snap.data()!;
      expect(d['status'], OrderService.statusAgreed);
      expect(d['orderNumber'], 'TRK-TEST-001');
      expect(d['passengerAgreed'], true);
      expect(d['passengerLocationText'], 'Jl. Uji');
    });

    test('setPassengerAgreed dua tahap: peek driver belum → lalu driver setuju', () async {
      bindTestHarness(uid: passengerUid);
      await seedDriverCapacityUser();
      await firestore.collection('orders').doc(orderId).set({
        'passengerUid': passengerUid,
        'driverUid': driverUid,
        'driverAgreed': false,
        'passengerAgreed': false,
        'status': OrderService.statusPendingAgreement,
        'orderType': OrderModel.typeTravel,
      });

      await OrderService.setPassengerAgreed(
        orderId,
        passengerLat: 1,
        passengerLng: 2,
        passengerLocationText: 'a',
      );

      await firestore.collection('orders').doc(orderId).update({
        'driverAgreed': true,
      });

      final result = await OrderService.setPassengerAgreed(
        orderId,
        passengerLat: 3,
        passengerLng: 4,
        passengerLocationText: 'b',
      );

      expect(result.$1, true);
      expect(result.$2, isNotNull);
      final snap = await firestore.collection('orders').doc(orderId).get();
      expect(snap.data()!['status'], OrderService.statusAgreed);
    });

    test('setDriverAgreed: set driverAgreed true', () async {
      bindTestHarness(uid: driverUid);
      await firestore.collection('orders').doc(orderId).set({
        'passengerUid': passengerUid,
        'driverUid': driverUid,
        'driverAgreed': false,
        'passengerAgreed': false,
        'status': OrderService.statusPendingAgreement,
        'orderType': OrderModel.typeTravel,
      });

      expect(await OrderService.setDriverAgreed(orderId), true);
      final d = (await firestore.collection('orders').doc(orderId).get()).data()!;
      expect(d['driverAgreed'], true);
    });

    test('setDriverAgreed: idempoten jika sudah true', () async {
      bindTestHarness(uid: driverUid);
      await firestore.collection('orders').doc(orderId).set({
        'passengerUid': passengerUid,
        'driverUid': driverUid,
        'driverAgreed': true,
        'status': OrderService.statusPendingAgreement,
        'orderType': OrderModel.typeTravel,
      });

      expect(await OrderService.setDriverAgreed(orderId), true);
    });

    test('setDriverAgreed: tolak status picked_up', () async {
      bindTestHarness(uid: driverUid);
      await firestore.collection('orders').doc(orderId).set({
        'passengerUid': passengerUid,
        'driverUid': driverUid,
        'driverAgreed': false,
        'status': OrderService.statusPickedUp,
        'orderType': OrderModel.typeTravel,
      });

      expect(await OrderService.setDriverAgreed(orderId), false);
    });

    test('setDriverAgreedPrice: selalu tulis harga', () async {
      bindTestHarness(uid: driverUid);
      await firestore.collection('orders').doc(orderId).set({
        'passengerUid': passengerUid,
        'driverUid': driverUid,
        'driverAgreed': true,
        'agreedPrice': 50000.0,
        'status': OrderService.statusPendingAgreement,
        'orderType': OrderModel.typeTravel,
      });

      expect(await OrderService.setDriverAgreedPrice(orderId, 75000), true);
      final d = (await firestore.collection('orders').doc(orderId).get()).data()!;
      expect(d['agreedPrice'], 75000);
      expect(d['driverAgreed'], true);
    });

    test('setPassengerAgreed: tolak jika status completed', () async {
      bindTestHarness(uid: passengerUid);
      await firestore.collection('orders').doc(orderId).set({
        'passengerUid': passengerUid,
        'driverUid': driverUid,
        'driverAgreed': true,
        'passengerAgreed': false,
        'status': OrderService.statusCompleted,
        'orderType': OrderModel.typeTravel,
      });

      final result = await OrderService.setPassengerAgreed(
        orderId,
        passengerLat: 1,
        passengerLng: 2,
        passengerLocationText: 'x',
      );
      expect(result.$1, false);
    });
  });
}
