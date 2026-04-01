import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

import '../services/app_analytics_service.dart';
import '../theme/app_interaction_styles.dart';
import '../services/payment_context_service.dart';
import '../services/violation_payment_service.dart';
import '../widgets/traka_l10n_scope.dart';
import '../services/violation_service.dart';
import 'payment_history_screen.dart';
import '../theme/traka_snackbar.dart';

/// Product ID: traka_violation_fee_5k (Rp 5.000), traka_violation_fee_10k (Rp 10.000), dll.
/// Format singkat agar selaras dengan lacak_barang (10k, 15k, 25k).
String violationFeeProductId(int amountRupiah) {
  if (amountRupiah >= 1000 && amountRupiah % 1000 == 0) {
    return 'traka_violation_fee_${amountRupiah ~/ 1000}k';
  }
  return 'traka_violation_fee_$amountRupiah';
}

/// Halaman bayar pelanggaran (tidak scan barcode) via Google Play.
/// Penumpang wajib bayar sebelum bisa cari travel lagi.
class ViolationPayScreen extends StatefulWidget {
  const ViolationPayScreen({super.key});

  @override
  State<ViolationPayScreen> createState() => _ViolationPayScreenState();
}

class _ViolationPayScreenState extends State<ViolationPayScreen> {
  final InAppPurchase _iap = InAppPurchase.instance;
  StreamSubscription<List<PurchaseDetails>>? _purchaseSub;
  List<ProductDetails> _products = [];
  bool _loading = true;
  bool _purchasing = false;
  String? _error;
  double _outstandingFee = 0;
  int _outstandingCount = 0;
  int _feePerViolation = 5000;

  @override
  void initState() {
    super.initState();
    PaymentContextService.setPaymentScreenActive(true);
    _listenPurchases();
    _loadConfigAndProducts();
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
          setState(() {
            _purchasing = false;
            _error = purchase.error?.message ?? 'Pembayaran gagal';
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
      await ViolationPaymentService.verifyViolationPayment(
        purchaseToken: token,
        productId: purchase.productID,
      );
      await _iap.completePurchase(purchase);
      if (mounted) {
        setState(() => _purchasing = false);
        final navigator = Navigator.of(context);
        ScaffoldMessenger.of(context).showSnackBar(
          TrakaSnackBar.success(context, Text(TrakaL10n.of(context).paymentSuccessSearchTravel), action: SnackBarAction(
              label: TrakaL10n.of(context).viewPaymentHistory,
              onPressed: () {
                navigator.push(
                  MaterialPageRoute(
                    builder: (_) => const PaymentHistoryScreen(),
                  ),
                );
              },
            )),
        );
        await _loadOutstanding();
        if (_outstandingFee <= 0) {
          if (mounted) navigator.pop();
        }
      }
    } catch (e) {
      AppAnalyticsService.logPaymentVerifyRejected(
        flow: 'violation',
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

  Future<void> _loadConfigAndProducts() async {
    _feePerViolation = await ViolationService.getViolationFeeRupiah();
    if (mounted) setState(() {});
    await _loadOutstanding();
    await _loadProducts();
  }

  Future<void> _loadOutstanding() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final fee = await ViolationService.getOutstandingViolationFee(user.uid);
    final count = await ViolationService.getOutstandingViolationCount(user.uid);
    if (mounted) {
      setState(() {
        _outstandingFee = fee;
        _outstandingCount = count;
      });
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
    final productId = violationFeeProductId(_feePerViolation);
    try {
      final response = await _iap.queryProductDetails({productId});
      if (response.notFoundIDs.isNotEmpty) {
        if (mounted) {
          setState(() {
            _loading = false;
            _error =
                'Produk pelanggaran Rp $_feePerViolation belum dikonfigurasi di Play Console (ID: $productId)';
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
          'Anda akan membayar $priceLabel untuk denda pelanggaran (tidak scan barcode). '
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
        title: const Text('Bayar Pelanggaran'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 16),
            Icon(
              Icons.warning_amber_rounded,
              size: 64,
              color: Colors.orange.shade700,
            ),
            const SizedBox(height: 16),
            Text(
              'Pelanggaran: Tidak Scan Barcode',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              _products.isNotEmpty && _products.first.price.isNotEmpty
                  ? 'Perjalanan terkonfirmasi otomatis tanpa scan barcode (berdasarkan lokasi). Sesuai Ketentuan Layanan, dikenakan biaya ${_products.first.price} per pelanggaran.'
                  : 'Perjalanan terkonfirmasi otomatis tanpa scan barcode (berdasarkan lokasi). Sesuai Ketentuan Layanan, dikenakan biaya per pelanggaran.',
              style: TextStyle(fontSize: 14, color: Theme.of(context).colorScheme.onSurfaceVariant),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            if (_outstandingFee > 0)
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  children: [
                    Text(
                      'Total belum dibayar: Rp ${_outstandingFee.toStringAsFixed(0)}',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.orange.shade900,
                      ),
                    ),
                    if (_outstandingCount > 0)
                      Text(
                        '$_outstandingCount pelanggaran',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.orange.shade800,
                        ),
                      ),
                  ],
                ),
              ),
            const SizedBox(height: 8),
            Text(
              _products.isNotEmpty && _products.first.price.isNotEmpty
                  ? 'Bayar ${_products.first.price} per pelanggaran via Google Play. Setelah bayar, Anda dapat mencari travel lagi.'
                  : 'Bayar per pelanggaran via Google Play. Setelah bayar, Anda dapat mencari travel lagi.',
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
                    style: AppInteractionStyles.elevatedPrimary(
                      backgroundColor: Theme.of(context).colorScheme.primary,
                      foregroundColor: Theme.of(context).colorScheme.onPrimary,
                      shadowTint: Theme.of(context).colorScheme.primary,
                    ).copyWith(
                      padding: WidgetStateProperty.all(
                        const EdgeInsets.symmetric(vertical: 16),
                      ),
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
            if (_outstandingFee > 0 && _outstandingCount > 1)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                  _products.isNotEmpty && _products.first.price.isNotEmpty
                      ? 'Anda punya $_outstandingCount pelanggaran. Bayar satu per satu (${_products.first.price} tiap kali).'
                      : 'Anda punya $_outstandingCount pelanggaran. Bayar satu per satu.',
                  style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
                  textAlign: TextAlign.center,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
