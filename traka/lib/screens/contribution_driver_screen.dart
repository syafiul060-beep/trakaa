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
import '../services/app_analytics_service.dart';

/// Product ID untuk kontribusi gabungan. Harus sama dengan di Google Play Console.
/// Tier kontribusi 5k–200k; ID harus sama dengan Play Console.
const String kContributionProductId = 'traka_driver_dues_7500';
const List<String> kDriverDuesProductIds = [
  'traka_driver_dues_5000',
  'traka_driver_dues_7500',
  'traka_driver_dues_10000',
  'traka_driver_dues_12500',
  'traka_driver_dues_15000',
  'traka_driver_dues_17500',
  'traka_driver_dues_20000',
  'traka_driver_dues_25000',
  'traka_driver_dues_30000',
  'traka_driver_dues_40000',
  'traka_driver_dues_50000',
  'traka_driver_dues_60000',
  'traka_driver_dues_75000',
  'traka_driver_dues_100000',
];
const List<int> kDriverDuesAmounts = [
  5000,
  7500,
  10000,
  12500,
  15000,
  17500,
  20000,
  25000,
  30000,
  40000,
  50000,
  60000,
  75000,
  100000,
  150000,
  200000,
];

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

enum _ContributionErrKind {
  none,
  storeUnavailable,
  productNotConfigured,
  paymentFailed,
  incompletePurchase,
  verifyFailed,
  generic,
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
  DriverContributionStatus? _status;
  List<RouteSessionModel> _breakdownRouteSessions = [];
  _TariffSummary? _tariffSummary;
  _ContributionErrKind _errKind = _ContributionErrKind.none;
  String? _errProductId;
  int? _errAmountRupiah;
  String? _errDetail;

  static String _fmtRp(int n) =>
      n.toString().replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]}.');

  void _resetErr() {
    _errKind = _ContributionErrKind.none;
    _errProductId = null;
    _errAmountRupiah = null;
    _errDetail = null;
  }

  String? _errorMessage(BuildContext context) {
    final l = TrakaL10n.of(context);
    switch (_errKind) {
      case _ContributionErrKind.none:
        return null;
      case _ContributionErrKind.storeUnavailable:
        return l.contributionErrorStoreUnavailable;
      case _ContributionErrKind.productNotConfigured:
        return l.contributionErrorProductNotConfigured(_errProductId ?? '', _fmtRp(_errAmountRupiah ?? 0));
      case _ContributionErrKind.paymentFailed:
        if (_errDetail != null && _errDetail!.isNotEmpty) {
          return '${l.contributionErrorPaymentFailed} ($_errDetail)';
        }
        return l.contributionErrorPaymentFailed;
      case _ContributionErrKind.incompletePurchase:
        return l.contributionErrorIncompletePurchase;
      case _ContributionErrKind.verifyFailed:
        return l.contributionVerifyFailed(_errDetail ?? '');
      case _ContributionErrKind.generic:
        return _errDetail ?? l.errorOccurred;
    }
  }

  @override
  void initState() {
    super.initState();
    PaymentContextService.setPaymentScreenActive(true);
    _listenContribution();
    _listenPurchases();
    _loadProducts();
    _prefetchTariffSummary();
  }

  Future<void> _prefetchTariffSummary() async {
    final s = await _loadTariffSummary();
    if (mounted) setState(() => _tariffSummary = s);
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
      _resetErr();
    });
    final available = await _iap.isAvailable();
    if (!available) {
      if (mounted) {
        setState(() {
          _loading = false;
          _errKind = _ContributionErrKind.storeUnavailable;
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
            _errKind = _ContributionErrKind.productNotConfigured;
            _errProductId = productId;
            _errAmountRupiah = totalRupiah;
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
          _errKind = _ContributionErrKind.generic;
          _errDetail = e.toString();
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
            _errKind = _ContributionErrKind.generic;
            _errDetail = e.toString();
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
            _errKind = _ContributionErrKind.paymentFailed;
            _errDetail = purchase.error?.message;
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
          _errKind = _ContributionErrKind.incompletePurchase;
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
        final l10n = TrakaL10n.of(context);
        RouteNotificationService.showPaymentNotification(
          title: l10n.contributionNotificationTitle,
          body: l10n.contributionSuccessBody,
        );
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.contributionSuccessSnackBar),
            backgroundColor: Colors.green,
            action: SnackBarAction(
              label: l10n.viewPaymentHistory,
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
      AppAnalyticsService.logPaymentVerifyRejected(
        flow: 'contribution',
        detail: e.toString(),
      );
      if (mounted) {
        setState(() {
          _purchasing = false;
          _errKind = _ContributionErrKind.verifyFailed;
          _errDetail = e.toString();
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
      if (!mounted) return;
      if (_products.isEmpty) return;
    }
    if (!context.mounted) return;
    final product = _products.first;
    final l10n = TrakaL10n.of(context);
    final priceLabel = product.price.isNotEmpty ? product.price : l10n.contributionNominalWord;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final d = TrakaL10n.of(ctx);
        return AlertDialog(
          title: Text(d.contributionConfirmPaymentTitle),
          content: Text(d.contributionConfirmPaymentBody(priceLabel)),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(d.cancel),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(d.contributionDialogContinue),
            ),
          ],
        );
      },
    );
    if (confirmed != true || !mounted) return;
    await _buy();
  }

  Future<void> _buy() async {
    if (_products.isEmpty) return;
    final product = _products.first;
    setState(() {
      _purchasing = true;
      _resetErr();
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
    final l10n = TrakaL10n.of(context);
    final errText = _errorMessage(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.contributionPayScreenTitle),
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
              l10n.contributionPayScreenHeadline,
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              l10n.contributionPayScreenIntro,
              style: TextStyle(fontSize: 14, color: Theme.of(context).colorScheme.onSurfaceVariant),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            FutureBuilder<_TariffSummary>(
              future: _loadTariffSummary(),
              builder: (context, snap) {
                String fmt(int n) => n.toString().replaceAllMapped(
                    RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]}.');
                final loc = TrakaL10n.of(context);
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
                              loc.contributionGuideCardTitle,
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
                            loc.contributionGuideTravelTitle,
                            loc.contributionGuideTravelDesc(
                              fmt(snap.data!.t1),
                              fmt(snap.data!.t2),
                              fmt(snap.data!.t3),
                              fmt(snap.data!.min),
                              fmt(snap.data!.maxRute),
                            ),
                            loc.contributionGuideTravelExample(fmt(snap.data!.contohTravel1)),
                          ),
                          const SizedBox(height: 10),
                          _buildTariffSection(
                            context,
                            loc.contributionGuideGoodsTitle,
                            loc.contributionGuideGoodsDesc(
                              fmt(snap.data!.b1),
                              fmt(snap.data!.b2),
                              fmt(snap.data!.b3),
                            ),
                            loc.contributionGuideGoodsExample(fmt(snap.data!.contohBarang)),
                          ),
                        ] else
                          Text(
                            loc.contributionGuideLoadingTariffs,
                            style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
                          ),
                        const SizedBox(height: 6),
                        Text(
                          loc.contributionGuideTapFullDetail,
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
                          l10n.contributionLineTravelContribution(_fmtRp(_status!.contributionTravelRupiah)),
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        Text(
                          _tariffSummary == null
                              ? l10n.contributionTravelHintShort
                              : l10n.contributionTravelHintFull(
                                  _fmtRp(_tariffSummary!.t1),
                                  _fmtRp(_tariffSummary!.t2),
                                  _fmtRp(_tariffSummary!.t3),
                                  _fmtRp(_tariffSummary!.maxRute),
                                ),
                          style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant),
                        ),
                        const SizedBox(height: 4),
                      ],
                      if (_status!.contributionBarangRupiah > 0) ...[
                        Text(
                          l10n.contributionLineGoodsContribution(_fmtRp(_status!.contributionBarangRupiah)),
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        Text(
                          _tariffSummary == null
                              ? l10n.contributionGoodsHintShort
                              : l10n.contributionGoodsHintFull(
                                  _fmtRp(_tariffSummary!.b1),
                                  _fmtRp(_tariffSummary!.b2),
                                  _fmtRp(_tariffSummary!.b3),
                                ),
                          style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant),
                        ),
                        const SizedBox(height: 4),
                      ],
                      if (_status!.outstandingViolationFee > 0) ...[
                        Text(
                          l10n.contributionLineViolation(_fmtRp(_status!.outstandingViolationFee.round())),
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 4),
                      ],
                      const Divider(),
                      Text(
                        l10n.contributionTotalLine(_fmtRp(_status!.totalRupiah)),
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        l10n.contributionUnpaidTravelLine(_fmtRp(_status!.unpaidTravelRupiah)),
                        style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
                      ),
                      Text(
                        _status!.unpaidRouteSessions.isEmpty
                            ? l10n.contributionRoutesAllPaid
                            : l10n.contributionRoutesUnpaidCount(_status!.unpaidRouteSessions.length),
                        style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
                      ),
                      if (_breakdownRouteSessions.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Text(
                          l10n.contributionUnpaidRoutesHeader,
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 12,
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                        ),
                        ..._breakdownRouteSessions.map((s) {
                          final rpStr = _fmtRp(s.contributionRupiah);
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 2),
                            child: Text(
                              l10n.contributionRouteBullet(s.routeOriginText, s.routeDestText, rpStr),
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
            if (errText != null) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  errText,
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
                        l10n.contributionGooglePlayPrice(_products.first.price),
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
                        l10n.contributionPayObligationNearest(_fmtRp(_status!.totalRupiah)),
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
                          ? l10n.contributionProcessing
                          : _products.first.price.isNotEmpty
                              ? l10n.contributionPayWithPrice(_products.first.price)
                              : l10n.contributionPayGeneric,
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
                label: Text(l10n.contributionReloadProducts),
              )
            else if (_status != null && !_status!.mustPayContribution)
              Text(
                l10n.contributionNoObligation,
                style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
              ),
          ],
        ),
      ),
    );
  }
}
