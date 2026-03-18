/// Flag untuk menandakan layar pembayaran sedang aktif.
/// PendingPurchaseRecoveryService akan skip pemrosesan saat flag true,
/// agar layar pembayaran yang menangani (menghindari duplikasi verify).
class PaymentContextService {
  PaymentContextService._();

  static bool _paymentScreenActive = false;

  static bool get isPaymentScreenActive => _paymentScreenActive;

  static void setPaymentScreenActive(bool active) {
    _paymentScreenActive = active;
  }
}
