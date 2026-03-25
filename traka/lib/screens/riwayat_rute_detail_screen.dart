import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../models/order_model.dart';
import '../services/app_config_service.dart';
import '../services/chat_service.dart';
import '../services/driver_schedule_service.dart';
import '../services/order_receipt_pdf_flow.dart';
import '../services/order_service.dart';
import '../widgets/traka_l10n_scope.dart';
import 'driver_earnings_screen.dart';
import 'payment_history_screen.dart';

/// Halaman detail satu rute di Riwayat: daftar order completed (penumpang/barang yang sudah dijemput dan diantar).
class RiwayatRuteDetailScreen extends StatefulWidget {
  const RiwayatRuteDetailScreen({
    super.key,
    required this.routeOriginText,
    required this.routeDestText,
    required this.routeJourneyNumber,
    this.scheduleId,
    this.endedAt,
    this.showAllCompleted = false,
    this.orders,
    this.isContributionPaid = false,
  });

  final String routeOriginText;
  final String routeDestText;
  final String routeJourneyNumber;
  /// Untuk rute terjadwal: agar penumpang per jadwal tampil.
  final String? scheduleId;
  final DateTime? endedAt;
  /// true = tampilkan semua pesanan selesai (fallback untuk riwayat lama tanpa sesi rute).
  final bool showAllCompleted;
  /// Jika diset, pakai daftar order ini (untuk riwayat lama per rute).
  final List<OrderModel>? orders;
  /// true = kontribusi rute ini sudah dibayar (lunas).
  final bool isContributionPaid;

  @override
  State<RiwayatRuteDetailScreen> createState() =>
      _RiwayatRuteDetailScreenState();
}

class _RiwayatRuteDetailScreenState extends State<RiwayatRuteDetailScreen> {
  final Map<String, Map<String, dynamic>> _passengerInfoCache = {};
  String? _loadingReceiptPdfOrderId;

  Future<void> _loadPassengerInfoIfNeeded(List<OrderModel> orders) async {
    final uids = orders
        .where((o) =>
            (o.passengerName.trim().isEmpty ||
                o.passengerPhotoUrl == null ||
                o.passengerPhotoUrl!.trim().isEmpty) &&
            o.passengerUid.isNotEmpty)
        .map((o) => o.passengerUid)
        .where((uid) => !_passengerInfoCache.containsKey(uid))
        .toSet();
    if (uids.isEmpty) return;
    final newInfo = <String, Map<String, dynamic>>{};
    for (final uid in uids) {
      try {
        final info = await ChatService.getUserInfo(uid)
            .timeout(const Duration(seconds: 5));
        newInfo[uid] = info;
      } catch (_) {
        newInfo[uid] = {
          'displayName': null,
          'photoUrl': null,
          'verified': false,
        };
      }
    }
    if (!mounted) return;
    setState(() {
      _passengerInfoCache.addAll(newInfo);
    });
  }

  static String _formatDate(DateTime? d) {
    if (d == null) return '-';
    return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
  }

  static String _fmt(int n) =>
      n.toString().replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]}.');

  /// Harga pesanan (pendapatan driver dari penumpang): agreedPrice, fallback tripFareRupiah (travel).
  int _getOrderFareRupiah(OrderModel order) {
    final price = (order.agreedPrice ?? 0).round();
    if (price > 0) return price;
    if (order.orderType == OrderModel.typeTravel) {
      return (order.tripFareRupiah ?? 0).round();
    }
    return 0;
  }

  /// Widget Harga pesanan per order.
  Widget _buildHargaPesanan(OrderModel order) {
    final fare = _getOrderFareRupiah(order);
    if (fare <= 0) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Text(
        'Harga pesanan: Rp ${_fmt(fare)}',
        style: TextStyle(
          fontSize: 12,
          color: Theme.of(context).colorScheme.primary,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  /// Rincian Kontribusi Aplikasi: travel = jarak × tarif/km; kirim barang = jarak × tarif/km.
  List<Widget> _buildKontribusiRincian(OrderModel order) {
    if (order.orderType == OrderModel.typeKirimBarang) {
      final total = (order.tripBarangFareRupiah ?? 0).round();
      final totalStr = total.toString().replaceAllMapped(
          RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]}.');
      return [
        Text(
          total > 0
              ? 'Kontribusi Aplikasi : Rp $totalStr'
              : 'Kontribusi Aplikasi : (Dihitung saat barang diterima)',
          style: TextStyle(
            fontSize: 12,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w600,
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Text(
            '(Jarak × tarif per km, tier provinsi. Bayar via Google Play)',
            style: TextStyle(
              fontSize: 10,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ];
    }
    // Travel
    final contrib = (order.tripTravelContributionRupiah ?? 0).round();
    final totalPenumpang = order.totalPenumpang;
    // Order lama: tripTravelContributionRupiah = 0 → hitung dari jarak (totalPenumpang × (jarak × tarif, min Rp 5.000))
    if (contrib == 0 && totalPenumpang > 0) {
      return [
        FutureBuilder<int?>(
          future: OrderService.getTripTravelContributionForDisplay(order),
          builder: (context, snap) {
            final c = snap.data ?? 0;
            final cStr = c.toString().replaceAllMapped(
                RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]}.');
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Kontribusi Aplikasi : Rp $cStr',
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    c > 0
                        ? '(totalPenumpang × (jarak × tarif per km, min Rp 5.000). Bayar via Google Play)'
                        : '(Dihitung saat order selesai: totalPenumpang × (jarak × tarif, min Rp 5.000))',
                    style: TextStyle(
                      fontSize: 10,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                if (c > 0)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      'Rincian: $totalPenumpang penumpang × (jarak × tarif, min Rp 5.000) = Rp $cStr',
                      style: TextStyle(
                        fontSize: 10,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ];
    }
    final contribStr = contrib.toString().replaceAllMapped(
        RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]}.');
    final widgets = <Widget>[
      Text(
        'Kontribusi Aplikasi : Rp $contribStr',
        style: TextStyle(
          fontSize: 12,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
          fontWeight: FontWeight.w600,
        ),
      ),
      Padding(
        padding: const EdgeInsets.only(top: 2),
        child: Text(
          contrib > 0
              ? '(totalPenumpang × (jarak × tarif per km, min Rp 5.000). Bayar via Google Play)'
              : '(Dihitung saat order selesai: totalPenumpang × (jarak × tarif, min Rp 5.000))',
          style: TextStyle(
            fontSize: 10,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    ];
    if (contrib > 0 && totalPenumpang > 0) {
      final basePerPenumpang = (contrib / totalPenumpang).round();
      final baseStr = basePerPenumpang.toString().replaceAllMapped(
          RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]}.');
      widgets.add(
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Text(
            'Rincian: $totalPenumpang penumpang × Rp $baseStr (dari jarak) = Rp $contribStr',
            style: TextStyle(
              fontSize: 10,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      );
    }
    return widgets;
  }

  /// Hitung ringkasan pendapatan rute dari daftar order.
  Future<({
    int pendapatanTravel,
    int pendapatanBarang,
    int kontribusi,
    int pelanggaran,
    int totalBersih,
  })> _computeRingkasanPendapatan(List<OrderModel> orders) async {
    int pendapatanTravel = 0;
    int pendapatanBarang = 0;
    int kontribusiTravel = 0;
    int kontribusiBarang = 0;
    int pelanggaran = 0;

    for (final o in orders) {
      if (o.orderType == OrderModel.typeTravel) {
        pendapatanTravel += _getOrderFareRupiah(o);
        final c = (o.tripTravelContributionRupiah ?? 0).round();
        if (c == 0 && o.totalPenumpang > 0) {
          final d = await OrderService.getTripTravelContributionForDisplay(o);
          kontribusiTravel += d ?? 0;
        } else {
          kontribusiTravel += c;
        }
        pelanggaran += (o.driverViolationFee ?? 0).round();
      } else if (o.orderType == OrderModel.typeKirimBarang) {
        pendapatanBarang += _getOrderFareRupiah(o);
        kontribusiBarang += (o.tripBarangFareRupiah ?? 0).round();
      }
    }

    final maxTravel = await AppConfigService.getMaxKontribusiTravelPerRuteRupiah();
    final cappedTravel = maxTravel != null && kontribusiTravel > maxTravel
        ? maxTravel
        : kontribusiTravel;
    final totalKontribusi = cappedTravel + kontribusiBarang;
    final subtotal = pendapatanTravel + pendapatanBarang;
    final totalBersih = subtotal - totalKontribusi - pelanggaran;

    return (
      pendapatanTravel: pendapatanTravel,
      pendapatanBarang: pendapatanBarang,
      kontribusi: totalKontribusi,
      pelanggaran: pelanggaran,
      totalBersih: totalBersih,
    );
  }

  Widget _buildRingkasanPendapatanCard(List<OrderModel> orders) {
    return FutureBuilder<({
      int pendapatanTravel,
      int pendapatanBarang,
      int kontribusi,
      int pelanggaran,
      int totalBersih,
    })>(
      future: _computeRingkasanPendapatan(orders),
      builder: (context, snap) {
        if (!snap.hasData) {
          return Card(
            margin: const EdgeInsets.only(bottom: 12),
            child: const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator()),
            ),
          );
        }
        final r = snap.data!;
        final hasAny = r.pendapatanTravel > 0 ||
            r.pendapatanBarang > 0 ||
            r.kontribusi > 0 ||
            r.pelanggaran > 0;

        if (!hasAny && r.totalBersih == 0) return const SizedBox.shrink();

        return Card(
          margin: const EdgeInsets.only(bottom: 24, top: 4),
          color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.3),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Ringkasan Pendapatan Rute',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
                const SizedBox(height: 12),
                if (r.pendapatanTravel > 0)
                  _buildSummaryRow('Pendapatan travel', r.pendapatanTravel, false),
                if (r.pendapatanBarang > 0)
                  _buildSummaryRow('Pendapatan kirim barang', r.pendapatanBarang, false),
                if (r.pendapatanTravel > 0 || r.pendapatanBarang > 0) ...[
                  _buildSummaryRow(
                    'Subtotal pendapatan',
                    r.pendapatanTravel + r.pendapatanBarang,
                    false,
                    bold: true,
                  ),
                  const SizedBox(height: 4),
                ],
                if (r.kontribusi > 0)
                  _buildSummaryRow('Kontribusi aplikasi', -r.kontribusi, true),
                if (r.pelanggaran > 0)
                  _buildSummaryRow('Pelanggaran', -r.pelanggaran, true),
                const Divider(height: 24),
                _buildSummaryRow(
                  'Total pendapatan bersih',
                  r.totalBersih,
                  false,
                  bold: true,
                ),
                const SizedBox(height: 16),
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    TextButton.icon(
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const PaymentHistoryScreen(isDriver: true),
                          ),
                        );
                      },
                      icon: const Icon(Icons.receipt_long, size: 18),
                      label: const Text('Riwayat Pembayaran'),
                    ),
                    TextButton.icon(
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const DriverEarningsScreen(),
                          ),
                        );
                      },
                      icon: const Icon(Icons.account_balance_wallet, size: 18),
                      label: Text(TrakaL10n.of(context).driverEarningsTitle),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildSummaryRow(String label, int amount, bool isNegative, {bool bold = false}) {
    final display = isNegative ? -amount : amount;
    final prefix = amount < 0 ? '-' : '';
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: bold ? FontWeight.bold : FontWeight.w500,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
          Text(
            '$prefix Rp ${_fmt(display.abs())}',
            style: TextStyle(
              fontSize: 13,
              fontWeight: bold ? FontWeight.bold : FontWeight.w500,
              color: amount < 0
                  ? Colors.red.shade700
                  : Theme.of(context).colorScheme.onSurface,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Detail Rute'),
        elevation: 0,
        actions: [
          if (widget.isContributionPaid)
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.check_circle, color: Colors.green.shade700, size: 22),
                  const SizedBox(width: 4),
                  Text(
                    'Lunas',
                    style: TextStyle(
                      color: Colors.green.shade700,
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!widget.showAllCompleted)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.routeOriginText.isNotEmpty
                          ? widget.routeOriginText
                          : 'Lokasi awal',
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Icon(
                        Icons.arrow_downward,
                        size: 20,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    Text(
                      widget.routeDestText.isNotEmpty
                          ? widget.routeDestText
                          : 'Tujuan',
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (widget.endedAt != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        'Selesai: ${_formatDate(widget.endedAt)}',
                        style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                    if (widget.routeJourneyNumber.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        'No. Rute: ${widget.routeJourneyNumber}',
                        style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          )
          else
            Padding(
              padding: const EdgeInsets.all(16),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    'Semua pesanan selesai (riwayat lama)',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ),
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              'Penumpang yang sudah sampai tujuan',
              style: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: widget.orders != null
                ? Builder(
                    builder: (context) {
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        _loadPassengerInfoIfNeeded(widget.orders!);
                      });
                      return _buildOrdersList(widget.orders!);
                    },
                  )
                : FutureBuilder<List<OrderModel>>(
                    future: widget.showAllCompleted
                        ? OrderService.getAllCompletedOrdersForDriver()
                        : OrderService.getCompletedOrdersForRoute(
                            widget.routeJourneyNumber,
                            scheduleId: widget.scheduleId,
                            legacyScheduleId: widget.scheduleId != null
                                ? ScheduleIdUtil.toLegacy(widget.scheduleId!)
                                : null,
                          ),
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      final orderList = snapshot.data ?? [];
                      if (orderList.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.inbox,
                          size: 48,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'Tidak ada pesanan selesai untuk rute ini',
                          style: TextStyle(
                            fontSize: 14,
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  );
                }
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  _loadPassengerInfoIfNeeded(orderList);
                });
                return _buildOrdersList(orderList);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOrdersList(List<OrderModel> orderList) {
    if (orderList.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.inbox,
              size: 48,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 12),
            Text(
              'Tidak ada pesanan selesai untuk rute ini',
              style: TextStyle(
                fontSize: 14,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.symmetric(
        horizontal: 16,
        vertical: 8,
      ),
      itemCount: orderList.length + 1,
      itemBuilder: (context, index) {
        if (index == orderList.length) {
          return _buildRingkasanPendapatanCard(orderList);
        }
        final order = orderList[index];
        final info = _passengerInfoCache[order.passengerUid];
        final passengerName = order.passengerName.trim().isNotEmpty
            ? order.passengerName
            : (info?['displayName'] as String?)?.trim().isNotEmpty == true
                ? (info!['displayName'] as String)
                : 'Penumpang';
        final passengerPhotoUrl = (order.passengerPhotoUrl != null &&
                order.passengerPhotoUrl!.trim().isNotEmpty)
            ? order.passengerPhotoUrl
            : info?['photoUrl'] as String?;
        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ListTile(
                leading: CircleAvatar(
                  backgroundColor:
                      Theme.of(context).colorScheme.surfaceContainerHighest,
                  backgroundImage: (passengerPhotoUrl != null &&
                          passengerPhotoUrl.isNotEmpty)
                      ? CachedNetworkImageProvider(passengerPhotoUrl)
                      : null,
                  child: (passengerPhotoUrl == null || passengerPhotoUrl.isEmpty)
                      ? Icon(Icons.person,
                          color: Theme.of(context).colorScheme.onSurfaceVariant)
                      : null,
                ),
                title: Text(
                  passengerName,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (order.orderNumber != null)
                      Text(
                        'No. Pesanan: ${order.orderNumber}',
                        style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    Text(
                      '${order.originText} → ${order.destText}',
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (order.tripDistanceKm != null)
                      Text(
                        'Jarak: ${order.tripDistanceKm!.toStringAsFixed(1)} km',
                        style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    _buildHargaPesanan(order),
                    ..._buildKontribusiRincian(order),
                    Text(
                      order.orderType == OrderModel.typeKirimBarang
                          ? 'Kirim barang'
                          : (order.totalPenumpang == 1
                              ? 'Penumpang sendiri'
                              : 'Penumpang (${order.totalPenumpang} orang)'),
                      style: TextStyle(
                        fontSize: 11,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              if (OrderReceiptPdfFlow.canDriverIssue(order))
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: OutlinedButton.icon(
                      onPressed: _loadingReceiptPdfOrderId == order.id
                          ? null
                          : () => OrderReceiptPdfFlow.issueAsDriver(
                                host: this,
                                order: order,
                                setLoadingOrderId: (id) => setState(
                                  () => _loadingReceiptPdfOrderId = id,
                                ),
                              ),
                      icon: _loadingReceiptPdfOrderId == order.id
                          ? SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Theme.of(context).colorScheme.primary,
                              ),
                            )
                          : const Icon(Icons.picture_as_pdf_outlined),
                      label: Text(
                        TrakaL10n.of(context).onlineReceiptAndPdfButton,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
                  },
    );
  }
}
