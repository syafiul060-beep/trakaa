import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

import 'driver_contribution_service.dart';
import 'payment_context_service.dart';
import 'violation_payment_service.dart';

/// Service untuk memulihkan pembelian yang tertunda (belum di-acknowledge).
/// Menghindari refund otomatis Google dalam 3 hari saat app crash/tertutup sebelum completePurchase.
///
/// Hanya memulihkan: Kontribusi (traka_driver_dues_*), Pelanggaran (traka_violation_fee_*).
/// Lacak Driver dan Lacak Barang membutuhkan orderId dari context—ditangani di layar pembayaran masing-masing.
class PendingPurchaseRecoveryService {
  PendingPurchaseRecoveryService._();

  static bool _listenerStarted = false;
  static StreamSubscription<List<PurchaseDetails>>? _subscription;

  /// Mulai listener untuk pembelian tertunda. Panggil sekali saat user login ke home.
  static void startRecoveryListener() {
    if (_listenerStarted) return;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    _listenerStarted = true;
    final iap = InAppPurchase.instance;

    _subscription = iap.purchaseStream.listen(
      _onPurchaseUpdate,
      onDone: () {
        _listenerStarted = false;
        _subscription = null;
      },
      onError: (e) {
        if (kDebugMode) {
          debugPrint('PendingPurchaseRecoveryService: $e');
        }
        _listenerStarted = false;
        _subscription = null;
      },
    );
  }

  static void _onPurchaseUpdate(List<PurchaseDetails> purchases) {
    if (PaymentContextService.isPaymentScreenActive) return;
    for (final purchase in purchases) {
      if (purchase.status != PurchaseStatus.purchased &&
          purchase.status != PurchaseStatus.restored) {
        continue;
      }
      // Hanya proses produk yang bisa direcovery tanpa context (orderId)
      if (_isRecoverableProduct(purchase.productID)) {
        _tryRecoverPurchase(purchase);
      }
    }
  }

  static bool _isRecoverableProduct(String productId) {
    if (productId.startsWith('traka_driver_dues_')) return true;
    if (productId.startsWith('traka_violation_fee_')) return true;
    return false;
  }

  static Future<void> _tryRecoverPurchase(PurchaseDetails purchase) async {
    final token = purchase.verificationData.serverVerificationData;
    if (token.isEmpty) return;

    try {
      if (purchase.productID.startsWith('traka_driver_dues_')) {
        await _recoverContribution(purchase, token);
      } else if (purchase.productID.startsWith('traka_violation_fee_')) {
        await _recoverViolation(purchase, token);
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('PendingPurchaseRecoveryService recover error: $e');
      }
    }
  }

  static Future<void> _recoverContribution(
    PurchaseDetails purchase,
    String token,
  ) async {
    final orderId = purchase.purchaseID ?? '';
    if (orderId.isEmpty) return;

    await DriverContributionService.verifyContributionPayment(
      purchaseToken: token,
      orderId: orderId,
      productId: purchase.productID,
    );
    await InAppPurchase.instance.completePurchase(purchase);
    if (kDebugMode) {
      debugPrint('PendingPurchaseRecoveryService: Kontribusi berhasil direcovery');
    }
  }

  static Future<void> _recoverViolation(
    PurchaseDetails purchase,
    String token,
  ) async {
    await ViolationPaymentService.verifyViolationPayment(
      purchaseToken: token,
      productId: purchase.productID,
    );
    await InAppPurchase.instance.completePurchase(purchase);
    if (kDebugMode) {
      debugPrint('PendingPurchaseRecoveryService: Pelanggaran berhasil direcovery');
    }
  }

  /// Hentikan listener (mis. saat logout). Biasanya tidak perlu dipanggil.
  static void stopRecoveryListener() {
    _subscription?.cancel();
    _subscription = null;
    _listenerStarted = false;
  }
}
