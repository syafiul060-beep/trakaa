import 'dart:async';

import 'package:flutter/material.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

import '../models/order_model.dart';
import '../widgets/traka_l10n_scope.dart';
import '../services/app_analytics_service.dart';
import '../services/app_config_service.dart';
import '../services/passenger_track_payment_service.dart';
import '../services/payment_context_service.dart';
import '../services/route_notification_service.dart';
import 'cek_lokasi_driver_screen.dart';
import 'payment_history_screen.dart';

/// Product ID: traka_lacak_driver_3000 (Rp 3000) atau traka_lacak_driver_{amount} untuk nominal lain.
/// Catatan: traka_lacak_driver tidak bisa dipakai jika pernah dihapus di Play Console.
String lacakDriverProductId(int amountRupiah) =>
    'traka_lacak_driver_$amountRupiah';

/// Halaman bayar Lacak Driver (Rp 3000) via Google Play.
/// Dibuka dari Data Order saat penumpang klik "Lacak Driver" dan belum bayar.
class LacakDriverPaymentScreen extends StatefulWidget {
  const LacakDriverPaymentScreen({
    super.key,
    required this.order,
  });

  final OrderModel order;

  @override
  State<LacakDriverPaymentScreen> createState() =>
      _LacakDriverPaymentScreenState();
}

class _LacakDriverPaymentScreenState extends State<LacakDriverPaymentScreen> {
  final InAppPurchase _iap = InAppPurchase.instance;
  StreamSubscription<List<PurchaseDetails>>? _purchaseSub;
  List<ProductDetails> _products = [];
  bool _loading = true;
  bool _purchasing = false;
  String? _error;
  int _feeRupiah = 3000;

  @override
  void initState() {
    super.initState();
    PaymentContextService.setPaymentScreenActive(true);
    _listenPurchases();
    _loadConfigAndProducts();
  }

  Future<void> _loadConfigAndProducts() async {
    _feeRupiah = await AppConfigService.getLacakDriverFeeRupiah();
    if (mounted) setState(() {});
    await _loadProducts();
  }

  void _listenPurchases() {
    _purchaseSub = _iap.purchaseStream.listen(
      _onPurchaseUpdate,
      onDone: () => _purchaseSub?.cancel(),
      onError: (e) {
        if (mounted) {
          setState(() {
            _error = e.toString();
            _purchasing = false;
          });
        }
      },
    );
  }

  void _onPurchaseUpdate(List<PurchaseDetails> purchases) {
    for (final purchase in purchases) {
      if (purchase.status == PurchaseStatus.pending) {
        if (mounted) setState(() => _purchasing = true);
        continue;
      }
      if (purchase.status == PurchaseStatus.error) {
        if (mounted) {
          final msg = purchase.error?.message ?? 'Pembayaran gagal';
          final isNotFound = msg.toLowerCase().contains('not found') ||
              msg.toLowerCase().contains('tidak dapat ditemukan');
          setState(() {
            _purchasing = false;
            _error = isNotFound
                ? 'Produk Lacak Driver belum dikonfigurasi di Google Play Console. '
                    'Buat produk dengan ID: traka_lacak_driver_3000 (Rp 3000). Lihat docs/UPDATE_HARGA_GOOGLE_BILLING.md'
                : msg;
          });
        }
        continue;
      }
      if (purchase.status == PurchaseStatus.purchased ||
          purchase.status == PurchaseStatus.restored) {
        _verifyAndComplete(purchase);
        continue;
      }
      if (purchase.status == PurchaseStatus.canceled) {
        if (mounted) setState(() => _purchasing = false);
      }
    }
  }

  Future<void> _verifyAndComplete(PurchaseDetails purchase) async {
    final token = purchase.verificationData.serverVerificationData;
    if (token.isEmpty) {
      if (mounted) {
        setState(() {
          _purchasing = false;
          _error = 'Data pembayaran tidak lengkap';
        });
      }
      return;
    }
    try {
      await PassengerTrackPaymentService.verifyPassengerTrackPayment(
        purchaseToken: token,
        orderId: widget.order.id,
        productId: purchase.productID,
      );
      await _iap.completePurchase(purchase);
      if (mounted) {
        setState(() => _purchasing = false);
        final navigator = Navigator.of(context);
        RouteNotificationService.showPaymentNotification(
          title: 'Lacak Driver',
          body: 'Pembayaran berhasil. Anda dapat melacak driver.',
        );
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(TrakaL10n.of(context).paymentSuccessTrackDriver),
            backgroundColor: Colors.green,
            action: SnackBarAction(
              label: TrakaL10n.of(context).viewPaymentHistory,
              textColor: Colors.white,
              onPressed: () {
                navigator.push(
                  MaterialPageRoute(
                    builder: (_) => const PaymentHistoryScreen(),
                  ),
                );
              },
            ),
          ),
        );
        navigator.pushReplacement(
          MaterialPageRoute<void>(
            builder: (_) => CekLokasiDriverScreen(
              orderId: widget.order.id,
              order: widget.order,
            ),
          ),
        );
      }
    } catch (e) {
      AppAnalyticsService.logPaymentTrackDriver(success: false);
      AppAnalyticsService.logPaymentVerifyRejected(
        flow: 'lacak_driver',
        detail: e.toString(),
      );
      if (mounted) {
        setState(() {
          _purchasing = false;
          _error = e.toString();
        });
      }
    }
  }

  Future<void> _loadProducts() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final available = await _iap.isAvailable();
    if (!available) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'Toko aplikasi tidak tersedia';
        });
      }
      return;
    }
    final productId = lacakDriverProductId(_feeRupiah);
    try {
      final response = await _iap.queryProductDetails({productId});
      if (response.notFoundIDs.isNotEmpty) {
        if (mounted) {
          setState(() {
            _loading = false;
            _error =
                'Produk Lacak Driver Rp $_feeRupiah belum dikonfigurasi di Play Console (ID: $productId)';
          });
        }
        return;
      }
      if (mounted) {
        setState(() {
          _products = response.productDetails;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = e.toString();
        });
      }
    }
  }

  Future<void> _confirmAndBuy(BuildContext context) async {
    if (_products.isEmpty) {
      await _loadProducts();
      if (_products.isEmpty) return;
    }
    if (!context.mounted) return;
    final product = _products.first;
    final priceLabel = product.price.isNotEmpty ? product.price : 'nominal';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Konfirmasi Pembayaran'),
        content: Text(
          'Anda akan membayar $priceLabel untuk melacak posisi driver di peta. '
          'Pembayaran melalui Google Play. Lanjutkan?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Lanjutkan'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await _buy();
  }

  Future<void> _buy() async {
    if (_products.isEmpty) return;
    final product = _products.first;
    setState(() {
      _purchasing = true;
      _error = null;
    });
    final param = PurchaseParam(productDetails: product);
    await _iap.buyConsumable(purchaseParam: param);
  }

  @override
  void dispose() {
    PaymentContextService.setPaymentScreenActive(false);
    _purchaseSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Bayar Lacak Driver'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 16),
            Icon(
              Icons.directions_car,
              size: 64,
              color: Colors.green.shade700,
            ),
            const SizedBox(height: 16),
            Text(
              'Lacak Driver',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              _products.isNotEmpty && _products.first.price.isNotEmpty
                  ? 'Untuk melacak posisi driver di peta, bayar ${_products.first.price} per pesanan via Google Play.'
                  : 'Untuk melacak posisi driver di peta, bayar per pesanan via Google Play.',
              style: TextStyle(fontSize: 14, color: Theme.of(context).colorScheme.onSurfaceVariant),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Pembayaran berlaku sampai driver memindai barcode Anda atau terkonfirmasi otomatis.',
              style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
              textAlign: TextAlign.center,
            ),
            if (_error != null) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  _error!,
                  style: TextStyle(color: Colors.red.shade800),
                ),
              ),
            ],
            const SizedBox(height: 32),
            if (_loading)
              const Center(child: CircularProgressIndicator())
            else if (_products.isNotEmpty)
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_products.first.price.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Text(
                        'Harga di Google Play: ${_products.first.price}',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  FilledButton.icon(
                    onPressed: _purchasing ? null : () => _confirmAndBuy(context),
                    icon: _purchasing
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.payment),
                    label: Text(
                      _purchasing
                          ? 'Memproses...'
                          : _products.first.price.isNotEmpty
                              ? 'Bayar ${_products.first.price} via Google Play'
                              : 'Bayar via Google Play',
                    ),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      backgroundColor: Colors.green.shade700,
                    ),
                  ),
                ],
              )
            else
              OutlinedButton.icon(
                onPressed: _loadProducts,
                icon: const Icon(Icons.refresh),
                label: const Text('Muat ulang produk'),
              ),
          ],
        ),
      ),
    );
  }
}
