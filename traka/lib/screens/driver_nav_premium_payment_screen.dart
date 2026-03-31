import 'dart:async';

import 'package:flutter/material.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

import '../services/app_config_service.dart';
import '../services/driver_nav_premium_payment_service.dart';
import '../services/driver_nav_premium_service.dart';
import '../services/payment_context_service.dart';
import '../services/route_notification_service.dart';
import '../widgets/traka_l10n_scope.dart';
import '../widgets/traka_loading_indicator.dart';
import 'payment_history_screen.dart';

/// Bayar navigasi premium per rute (setelah selesai kerja) via Google Play.
class DriverNavPremiumPaymentScreen extends StatefulWidget {
  const DriverNavPremiumPaymentScreen({
    super.key,
    this.routeJourneyNumber,
    this.navPremiumScope,
    this.routeDistanceMeters,
    this.prepayActivation = false,
  });

  /// Nomor rute untuk riwayat; boleh kosong (diambil dari hutang lokal).
  final String? routeJourneyNumber;

  /// `dalamProvinsi` | `antarProvinsi` | `dalamNegara` — menentukan SKU & tarif.
  final String? navPremiumScope;

  /// Jarak rute Directions (meter) untuk tier tarif jarak; opsional.
  final int? routeDistanceMeters;

  /// true = bayar dulu untuk mengaktifkan premium di sesi kerja (bukan hutang pasca-rute).
  final bool prepayActivation;

  @override
  State<DriverNavPremiumPaymentScreen> createState() =>
      _DriverNavPremiumPaymentScreenState();
}

class _DriverNavPremiumPaymentScreenState
    extends State<DriverNavPremiumPaymentScreen> {
  final InAppPurchase _iap = InAppPurchase.instance;
  StreamSubscription<List<PurchaseDetails>>? _purchaseSub;
  List<ProductDetails> _products = [];
  bool _loading = true;
  bool _purchasing = false;
  String? _error;
  int _feeRupiah = 100000;
  String? _resolvedJourney;
  String? _resolvedScope;
  int? _resolvedDistanceM;

  @override
  void initState() {
    super.initState();
    PaymentContextService.setPaymentScreenActive(true);
    _listenPurchases();
    _loadConfigAndProducts();
  }

  Future<void> _loadConfigAndProducts() async {
    if (widget.prepayActivation) {
      _resolvedJourney = widget.routeJourneyNumber?.trim().isNotEmpty == true
          ? widget.routeJourneyNumber!.trim()
          : null;
      _resolvedScope = widget.navPremiumScope?.trim().isNotEmpty == true
          ? widget.navPremiumScope!.trim()
          : null;
      _resolvedDistanceM = widget.routeDistanceMeters;
    } else {
      _resolvedJourney = widget.routeJourneyNumber?.trim().isNotEmpty == true
          ? widget.routeJourneyNumber!.trim()
          : await DriverNavPremiumService.owedRouteJourneyNumber();
      _resolvedScope = widget.navPremiumScope?.trim().isNotEmpty == true
          ? widget.navPremiumScope!.trim()
          : await DriverNavPremiumService.owedNavPremiumScope();
      _resolvedDistanceM = widget.routeDistanceMeters ??
          await DriverNavPremiumService.owedRouteDistanceMeters();
    }
    _feeRupiah = await AppConfigService.getDriverNavPremiumFeeForRoute(
      navPremiumScope: _resolvedScope,
      routeDistanceMeters: _resolvedDistanceM,
    );
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
          setState(() {
            _purchasing = false;
            _error = purchase.error?.message ?? 'Pembayaran gagal';
          });
        }
        continue;
      }
      if (purchase.status == PurchaseStatus.purchased ||
          purchase.status == PurchaseStatus.restored) {
        unawaited(_verifyAndComplete(purchase));
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
      await DriverNavPremiumPaymentService.verifyPayment(
        purchaseToken: token,
        productId: purchase.productID,
        routeJourneyNumber: _resolvedJourney,
        navPremiumScope: _resolvedScope,
        routeDistanceMeters: _resolvedDistanceM,
      );
      await _iap.completePurchase(purchase);
      await DriverNavPremiumService.clearOwed();
      if (mounted) {
        setState(() => _purchasing = false);
        RouteNotificationService.showPaymentNotification(
          title: 'Navigasi premium',
          body: 'Pembayaran berhasil.',
        );
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Pembayaran navigasi premium berhasil.'),
            backgroundColor: Colors.green,
            action: SnackBarAction(
              label: TrakaL10n.of(context).viewPaymentHistory,
              textColor: Colors.white,
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const PaymentHistoryScreen(),
                  ),
                );
              },
            ),
          ),
        );
        Navigator.of(context).pop(true);
      }
    } catch (e) {
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
    final productId = driverNavPremiumProductId(_feeRupiah);
    try {
      final response = await _iap.queryProductDetails({productId});
      if (response.notFoundIDs.isNotEmpty) {
        if (mounted) {
          setState(() {
            _loading = false;
            _error =
                'Produk belum dikonfigurasi di Play Console (ID: $productId, Rp $_feeRupiah).';
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
    final body = widget.prepayActivation
        ? 'Anda membayar $priceLabel untuk mengaktifkan navigasi premium sekarang. '
            'Pembayaran melalui Google Play.'
        : 'Anda membayar $priceLabel untuk navigasi premium pada rute yang baru selesai. '
            'Pembayaran melalui Google Play.';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Konfirmasi'),
        content: Text(body),
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

  String _scopeLabel(String? s) {
    switch (s) {
      case 'dalamProvinsi':
        return 'Dalam provinsi';
      case 'antarProvinsi':
        return 'Antar provinsi (satu pulau)';
      case 'dalamNegara':
        return 'Seluruh Indonesia';
      default:
        return '—';
    }
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
        title: Text(
          widget.prepayActivation
              ? 'Aktivasi navigasi premium'
              : 'Bayar navigasi premium',
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 16),
            Icon(
              Icons.workspace_premium,
              size: 64,
              color: Colors.amber.shade800,
            ),
            const SizedBox(height: 16),
            Text(
              'Navigasi premium',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              widget.prepayActivation
                  ? 'Lanjutkan pembayaran di Google Play. Setelah berhasil, navigasi premium '
                      'langsung aktif untuk sesi kerja ini. '
                      'Manfaat: tampilan navigasi lebih lengkap (mis. snap ke jalan) sesuai kebijakan peta.'
                  : 'Biaya ini untuk satu rute selesai di mana Anda mengaktifkan mode premium. '
                      'Ke depan: snap ke jalan & fitur navigasi lanjutan (selaras kebijakan peta).',
              style: TextStyle(
                fontSize: 14,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            if (_resolvedJourney != null && _resolvedJourney!.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                'Rute: $_resolvedJourney',
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
            ],
            if (_resolvedScope != null && _resolvedScope!.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                'Jenis rute: ${_scopeLabel(_resolvedScope)}',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Theme.of(context).colorScheme.primary,
                ),
                textAlign: TextAlign.center,
              ),
            ],
            if (_resolvedDistanceM != null && _resolvedDistanceM! > 0) ...[
              const SizedBox(height: 4),
              Text(
                'Perkiraan jarak rute: ${(_resolvedDistanceM! / 1000).toStringAsFixed(1)} km',
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
            ],
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
              trakaPageLoadingCenter()
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
                    onPressed: _purchasing
                        ? null
                        : () {
                            if (widget.prepayActivation) {
                              unawaited(_buy());
                            } else {
                              unawaited(_confirmAndBuy(context));
                            }
                          },
                    icon: _purchasing
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: TrakaLoadingIndicator(
                              size: 22,
                              variant: TrakaLoadingVariant.onLightSurface,
                            ),
                          )
                        : const Icon(Icons.payment),
                    label: Text(
                      _purchasing
                          ? 'Memproses...'
                          : _products.first.price.isNotEmpty
                              ? 'Bayar ${_products.first.price}'
                              : 'Bayar via Google Play',
                    ),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      backgroundColor: Colors.amber.shade800,
                      foregroundColor: Colors.white,
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
