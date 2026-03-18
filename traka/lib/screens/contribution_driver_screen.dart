import 'dart:async';

import 'package:flutter/material.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

import '../services/app_config_service.dart';
import '../services/payment_context_service.dart';
import '../widgets/contribution_tariff_dialog.dart';
import '../widgets/traka_l10n_scope.dart';
import '../services/driver_contribution_service.dart';
import 'payment_history_screen.dart';
import '../services/route_session_service.dart';
import '../services/route_notification_service.dart';

/// Product ID untuk kontribusi gabungan. Harus sama dengan di Google Play Console.
/// Sesuai RANCANGAN_KONTRIBUSI_OPTIMAL.md: 5k–50k untuk mengurangi overpay.
const String kContributionProductId = 'traka_driver_dues_7500';
const List<String> kDriverDuesProductIds = [
  'traka_driver_dues_5000',
  'traka_driver_dues_7500',
  'traka_driver_dues_10000',
  'traka_driver_dues_12500',
  'traka_driver_dues_15000',
  'traka_driver_dues_20000',
  'traka_driver_dues_25000',
  'traka_driver_dues_30000',
  'traka_driver_dues_40000',
  'traka_driver_dues_50000',
];
const List<int> kDriverDuesAmounts = [5000, 7500, 10000, 12500, 15000, 20000, 25000, 30000, 40000, 50000];

/// Pilih product ID untuk total Rupiah (bulatkan ke atas ke nominal terdekat).
String productIdForTotalRupiah(int totalRupiah) {
  for (var i = 0; i < kDriverDuesAmounts.length; i++) {
    if (kDriverDuesAmounts[i] >= totalRupiah) return kDriverDuesProductIds[i];
  }
  return kDriverDuesProductIds.last;
}

/// Ambil nominal Rupiah dari product ID (mis. traka_driver_dues_10000 → 10000).
int getProductAmountFromId(String productId) {
  final match = RegExp(r'traka_driver_dues_(\d+)').firstMatch(productId);
  if (match != null) return int.tryParse(match.group(1) ?? '0') ?? 0;
  return 0;
}

/// Ringkasan tarif untuk tampilan di info box.
class _TariffSummary {
  final int min;
  final int maxRute;
  final int t1;
  final int t2;
  final int t3;
  final int b1;
  final int b2;
  final int b3;
  final int contohTravel1;
  final int contohBarang;

  _TariffSummary({
    required this.min,
    required this.maxRute,
    required this.t1,
    required this.t2,
    required this.t3,
    required this.b1,
    required this.b2,
    required this.b3,
    required this.contohTravel1,
    required this.contohBarang,
  });
}

/// Halaman bayar kontribusi driver via Google Play (gabungan: travel + kirim barang + pelanggaran).
class ContributionDriverScreen extends StatefulWidget {
  const ContributionDriverScreen({super.key});

  @override
  State<ContributionDriverScreen> createState() =>
      _ContributionDriverScreenState();
}

class _ContributionDriverScreenState extends State<ContributionDriverScreen> {
  final InAppPurchase _iap = InAppPurchase.instance;
  StreamSubscription<List<PurchaseDetails>>? _purchaseSub;
  List<ProductDetails> _products = [];
  bool _loading = true;
  bool _purchasing = false;
  String? _error;
  DriverContributionStatus? _status;
  List<RouteSessionModel> _breakdownRouteSessions = [];

  @override
  void initState() {
    super.initState();
    PaymentContextService.setPaymentScreenActive(true);
    _listenContribution();
    _listenPurchases();
    _loadProducts();
  }

  void _listenContribution() {
    DriverContributionService.streamContributionStatus().listen((status) {
      if (mounted) {
        setState(() => _status = status);
        _loadBreakdownFromStatus(status);
        if (status.totalRupiah > 0) {
          final neededId = productIdForTotalRupiah(status.totalRupiah);
          if (_products.isEmpty || _products.first.id != neededId) {
            _loadProductsForTotal(status.totalRupiah);
          }
        }
      }
    });
  }

  Future<void> _loadProductsForTotal(int totalRupiah) async {
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
    final productId = productIdForTotalRupiah(totalRupiah);
    try {
      final response = await _iap.queryProductDetails({productId});
      if (response.notFoundIDs.isNotEmpty) {
        if (mounted) {
          setState(() {
            _loading = false;
            _error =
                'Produk belum dikonfigurasi di Play Console (ID: $productId). Buat produk untuk Rp ${totalRupiah.toString().replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]}.')}';
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

  void _loadBreakdownFromStatus(DriverContributionStatus status) {
    if (mounted) setState(() => _breakdownRouteSessions = status.unpaidRouteSessions);
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
    final orderId = purchase.purchaseID;
    if (token.isEmpty || (orderId?.isEmpty ?? true)) {
      if (mounted) {
        setState(() {
          _purchasing = false;
          _error = 'Data pembayaran tidak lengkap';
        });
      }
      return;
    }
    try {
      await DriverContributionService.verifyContributionPayment(
        purchaseToken: token,
        orderId: orderId!,
        productId: purchase.productID,
      );
      await _iap.completePurchase(purchase);
      if (mounted) {
        setState(() => _purchasing = false);
        final navigator = Navigator.of(context);
        RouteNotificationService.showPaymentNotification(
          title: 'Kontribusi',
          body: 'Kontribusi berhasil. Anda dapat menerima order dan balas chat.',
        );
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text(
              'Kontribusi berhasil. Anda dapat menerima order dan balas chat.',
            ),
            backgroundColor: Colors.green,
            action: SnackBarAction(
              label: TrakaL10n.of(context).viewPaymentHistory,
              textColor: Colors.white,
              onPressed: () {
                navigator.push(
                  MaterialPageRoute(
                    builder: (_) => const PaymentHistoryScreen(isDriver: true),
                  ),
                );
              },
            ),
          ),
        );
        navigator.pop(true);
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
    await _loadProductsForTotal(_status?.totalRupiah ?? 5000);
  }

  static Future<_TariffSummary> _loadTariffSummary() async {
    final min = await AppConfigService.getMinKontribusiTravelRupiah();
    final maxRute = await AppConfigService.getMaxKontribusiTravelPerRuteRupiah() ?? 30000;
    final t1 = await AppConfigService.getTarifKontribusiTravelPerKm(1);
    final t2 = await AppConfigService.getTarifKontribusiTravelPerKm(2);
    final t3 = await AppConfigService.getTarifKontribusiTravelPerKm(3);
    final b1 = await AppConfigService.getTarifBarangPerKm(1);
    final b2 = await AppConfigService.getTarifBarangPerKm(2);
    final b3 = await AppConfigService.getTarifBarangPerKm(3);
    const contohTravelKm = 50;
    final byDist = (contohTravelKm * t1).round();
    final contohTravel1 = byDist > min ? byDist : min;
    const contohBarangKm = 30;
    final contohBarang = contohBarangKm * b1;
    return _TariffSummary(
      min: min,
      maxRute: maxRute,
      t1: t1,
      t2: t2,
      t3: t3,
      b1: b1,
      b2: b2,
      b3: b3,
      contohTravel1: contohTravel1,
      contohBarang: contohBarang,
    );
  }

  static Widget _buildTariffSection(
    BuildContext context,
    String title,
    String desc,
    String example,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: Theme.of(context).colorScheme.primary,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          desc,
          style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 2),
        Text(
          example,
          style: TextStyle(
            fontSize: 11,
            fontStyle: FontStyle.italic,
            color: Theme.of(context).colorScheme.onSurface,
          ),
        ),
      ],
    );
  }

  Future<void> _confirmAndBuy(BuildContext context) async {
    if (_products.isEmpty) {
      await _loadProducts();
      if (_products.isEmpty) return;
    }
    final product = _products.first;
    final priceLabel = product.price.isNotEmpty ? product.price : 'nominal';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Konfirmasi Pembayaran'),
        content: Text(
          'Anda akan membayar $priceLabel untuk kewajiban driver (travel + kirim barang + pelanggaran). '
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
    await _iap.buyNonConsumable(purchaseParam: param);
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
        title: const Text('Bayar Kontribusi Traka'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 16),
            Icon(
              Icons.volunteer_activism,
              size: 64,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: 16),
            Text(
              'Bayar Kewajiban Driver',
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Bayar kontribusi travel, kirim barang, dan denda pelanggaran (jika ada) sekaligus via Google Play.',
              style: TextStyle(fontSize: 14, color: Theme.of(context).colorScheme.onSurfaceVariant),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            FutureBuilder<_TariffSummary>(
              future: _loadTariffSummary(),
              builder: (context, snap) {
                final fmt = (int n) => n.toString().replaceAllMapped(
                    RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]}.');
                return InkWell(
                  onTap: () => showContributionTariffDialog(context),
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.2),
                        width: 1,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.info_outline, size: 20, color: Theme.of(context).colorScheme.primary),
                            const SizedBox(width: 8),
                            Text(
                              'Panduan Tarif Kontribusi',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                color: Theme.of(context).colorScheme.onSurface,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        if (snap.hasData) ...[
                          _buildTariffSection(
                            context,
                            'Travel (antar kota)',
                            'Tarif per km: dalam provinsi Rp ${fmt(snap.data!.t1)}, antar provinsi Rp ${fmt(snap.data!.t2)}, lintas pulau Rp ${fmt(snap.data!.t3)}. Min Rp ${fmt(snap.data!.min)}, max Rp ${fmt(snap.data!.maxRute)} per rute.',
                            'Contoh: 50 km dalam provinsi, 1 penumpang → Rp ${fmt(snap.data!.contohTravel1)}',
                          ),
                          const SizedBox(height: 10),
                          _buildTariffSection(
                            context,
                            'Kirim barang',
                            'Tarif per km: dalam provinsi Rp ${fmt(snap.data!.b1)}, antar provinsi Rp ${fmt(snap.data!.b2)}, lintas pulau Rp ${fmt(snap.data!.b3)}.',
                            'Contoh: 30 km dalam provinsi → Rp ${fmt(snap.data!.contohBarang)}',
                          ),
                        ] else
                          Text(
                            'Memuat tarif...',
                            style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
                          ),
                        const SizedBox(height: 6),
                        Text(
                          'Ketuk untuk detail lengkap dan contoh',
                          style: TextStyle(
                            fontSize: 11,
                            color: Theme.of(context).colorScheme.primary,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
            if (_status != null) ...[
              const SizedBox(height: 24),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (_status!.contributionTravelRupiah > 0) ...[
                        Text(
                          'Kontribusi travel: Rp ${_status!.contributionTravelRupiah.toString().replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]}.')}',
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        Text(
                          'Dihitung dari jarak × tarif per km (dalam provinsi Rp 90/km, antar provinsi Rp 110/km, lintas pulau Rp 140/km). Max Rp 30.000 per rute.',
                          style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant),
                        ),
                        const SizedBox(height: 4),
                      ],
                      if (_status!.contributionBarangRupiah > 0) ...[
                        Text(
                          'Kontribusi kirim barang: Rp ${_status!.contributionBarangRupiah.toString().replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]}.')}',
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        Text(
                          'Dihitung dari jarak × tarif per km (dalam provinsi Rp 15/km, antar provinsi Rp 35/km, lintas pulau Rp 50/km).',
                          style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant),
                        ),
                        const SizedBox(height: 4),
                      ],
                      if (_status!.outstandingViolationFee > 0) ...[
                        Text(
                          'Denda pelanggaran: Rp ${_status!.outstandingViolationFee.round().toString().replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]}.')}',
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 4),
                      ],
                      const Divider(),
                      Text(
                        'Total: Rp ${_status!.totalRupiah.toString().replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]}.')}',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Total kontribusi travel (rute belum lunas): Rp ${_status!.unpaidTravelRupiah.toString().replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]}.')}',
                        style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
                      ),
                      Text(
                        'Rute lunas: ${_status!.unpaidRouteSessions.isEmpty ? "Semua" : "Ada ${_status!.unpaidRouteSessions.length} belum"}',
                        style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
                      ),
                      if (_breakdownRouteSessions.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Text(
                          'Rute belum lunas:',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 12,
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                        ),
                        ..._breakdownRouteSessions.map((s) {
                          final rpStr = s.contributionRupiah.toString().replaceAllMapped(
                              RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]}.');
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 2),
                            child: Text(
                              '• ${s.routeOriginText} → ${s.routeDestText}: Rp $rpStr',
                              style: TextStyle(
                                fontSize: 11,
                                color: Theme.of(context).colorScheme.onSurfaceVariant,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          );
                        }),
                      ],
                    ],
                  ),
                ),
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
              const Center(child: CircularProgressIndicator())
            else if (_products.isNotEmpty && (_status?.mustPayContribution ?? false) && (_status?.totalRupiah ?? 0) > 0)
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_products.first.price.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(
                        'Harga di Google Play: ${_products.first.price}',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  if ((_status?.totalRupiah ?? 0) > 0 &&
                      _products.isNotEmpty &&
                      getProductAmountFromId(_products.first.id) > (_status?.totalRupiah ?? 0))
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(
                        'Kewajiban Rp ${(_status!.totalRupiah).toString().replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]}.')}. Bayar nominal terdekat (produk Play punya harga tetap).',
                        style: TextStyle(
                          fontSize: 11,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
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
                    ),
                  ),
                ],
              )
            else if ((_status?.mustPayContribution ?? false) && (_status?.totalRupiah ?? 0) > 0 && _products.isEmpty)
              OutlinedButton.icon(
                onPressed: _loadProducts,
                icon: const Icon(Icons.refresh),
                label: const Text('Muat ulang produk'),
              )
            else if (_status != null && !_status!.mustPayContribution)
              Text(
                'Tidak ada kewajiban yang perlu dibayar.',
                style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
              ),
          ],
        ),
      ),
    );
  }
}
