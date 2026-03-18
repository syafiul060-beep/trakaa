import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../services/driver_contribution_service.dart';
import '../services/payment_history_service.dart';
import '../widgets/contribution_tariff_dialog.dart';
import '../widgets/traka_l10n_scope.dart';
import 'contribution_driver_screen.dart';
import 'driver_earnings_screen.dart';

/// Halaman riwayat pembayaran via Google Play (Lacak Driver, Lacak Barang, Pelanggaran).
/// Akses dari Profil penumpang/driver.
class PaymentHistoryScreen extends StatefulWidget {
  const PaymentHistoryScreen({super.key, this.isDriver = false});

  /// true jika dibuka dari profil driver. Untuk driver: empty state tampil "Pembayaran kontribusi dan pelanggaran".
  final bool isDriver;

  @override
  State<PaymentHistoryScreen> createState() => _PaymentHistoryScreenState();
}

class _PaymentHistoryScreenState extends State<PaymentHistoryScreen> {
  List<PaymentRecord> _records = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list = await PaymentHistoryService.getPaymentHistory();
      if (mounted) {
        setState(() {
          _records = list;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  String _formatRupiah(double rp) {
    return 'Rp ${rp.toStringAsFixed(0).replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]}.')}';
  }

  String _formatDate(DateTime dt) {
    final d = dt.day.toString().padLeft(2, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final y = dt.year;
    final h = dt.hour.toString().padLeft(2, '0');
    final min = dt.minute.toString().padLeft(2, '0');
    return '$d/$m/$y $h:$min';
  }

  String _formatRupiahInt(int n) {
    return n.toString().replaceAllMapped(
        RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]}.');
  }

  String _buildContributionSubtitle(PaymentRecord r) {
    final dateStr = _formatDate(r.paidAt);
    final b = r.contributionBreakdown;
    if (b != null && b.hasAny) {
      final parts = <String>[];
      if (b.travelRupiah > 0) parts.add('Travel Rp ${_formatRupiahInt(b.travelRupiah)}');
      if (b.barangRupiah > 0) parts.add('Barang Rp ${_formatRupiahInt(b.barangRupiah)}');
      if (b.violationRupiah > 0) parts.add('Denda Rp ${_formatRupiahInt(b.violationRupiah)}');
      return '$dateStr\n${parts.join('  •  ')}';
    }
    return '$dateStr\nGabungan travel, kirim barang, pelanggaran';
  }

  void _showStruk(PaymentRecord record) {
    String detailSection = '';
    if (record.type == PaymentType.contribution) {
      final b = record.contributionBreakdown;
      if (b != null && b.hasAny) {
        detailSection = '''
Rincian:
  • Travel (antar kota): Rp ${_formatRupiahInt(b.travelRupiah)}
  • Kirim barang: Rp ${_formatRupiahInt(b.barangRupiah)}
  • Denda pelanggaran: Rp ${_formatRupiahInt(b.violationRupiah)}

''';
      } else if (record.description != null) {
        detailSection = 'Detail: ${record.description}\n\n';
      }
    } else if (record.description != null) {
      detailSection = 'Detail: ${record.description}\n\n';
    }
    final struk = '''
STRUK PEMBAYARAN TRAKA
======================

Jenis: ${record.typeLabel}
Nominal: ${_formatRupiah(record.amountRupiah)}
Waktu: ${_formatDate(record.paidAt)}

$detailSection${record.orderNumber != null ? 'No. Pesanan: ${record.orderNumber}\n' : ''}${record.orderId != null ? 'ID: ${record.orderId}\n' : ''}

Pembayaran via Google Play
''';
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Struk Pembayaran',
                style: Theme.of(ctx).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Theme.of(ctx).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: SelectableText(
                  struk,
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 13,
                    color: Theme.of(ctx).colorScheme.onSurface,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => Navigator.pop(ctx),
                      icon: const Icon(Icons.close),
                      label: Text(TrakaL10n.of(context).close),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () async {
                        await Share.share(
                          struk,
                          subject: 'Struk Traka - ${record.typeLabel}',
                        );
                        if (ctx.mounted) Navigator.pop(ctx);
                      },
                      icon: const Icon(Icons.share),
                      label: const Text('Bagikan'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  IconData _iconForType(PaymentType type) {
    switch (type) {
      case PaymentType.lacakDriver:
        return Icons.location_on;
      case PaymentType.lacakBarang:
        return Icons.local_shipping;
      case PaymentType.violation:
        return Icons.warning_amber;
      case PaymentType.contribution:
        return Icons.payments;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(TrakaL10n.of(context).paymentHistory),
        actions: [
          if (widget.isDriver)
            IconButton(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const DriverEarningsScreen(),
                  ),
                );
              },
              icon: const Icon(Icons.account_balance_wallet),
              tooltip: TrakaL10n.of(context).driverEarningsTitle,
            ),
          IconButton(
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _error!,
                          style: TextStyle(color: Colors.red.shade700),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 16),
                        FilledButton.icon(
                          onPressed: _load,
                          icon: const Icon(Icons.refresh),
                          label: Text(TrakaL10n.of(context).retry),
                        ),
                      ],
                    ),
                  ),
                )
              : _records.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.receipt_long,
                              size: 64,
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant,
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'Belum ada riwayat pembayaran',
                              style: TextStyle(
                                fontSize: 16,
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant,
                              ),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              widget.isDriver
                                  ? TrakaL10n.of(context).paymentHistoryEmptyDriver
                                  : TrakaL10n.of(context).paymentHistoryEmptyPassenger,
                              style: TextStyle(
                                fontSize: 13,
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant,
                              ),
                              textAlign: TextAlign.center,
                            ),
                            if (widget.isDriver) ...[
                              const SizedBox(height: 12),
                              InkWell(
                                onTap: () => showContributionTariffDialog(context),
                                borderRadius: BorderRadius.circular(8),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(Icons.info_outline, size: 20, color: Theme.of(context).colorScheme.primary),
                                      const SizedBox(width: 8),
                                      Text(
                                        TrakaL10n.of(context).contributionTariffButtonLabel,
                                        style: TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w600,
                                          color: Theme.of(context).colorScheme.primary,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    )
                  : Column(
                      children: [
                        if (widget.isDriver) ...[
                          StreamBuilder<DriverContributionStatus>(
                            stream: DriverContributionService.streamContributionStatus(),
                            builder: (context, contribSnap) {
                              final status = contribSnap.data;
                              final mustPay = status?.mustPayContribution ?? false;
                              if (!mustPay) return const SizedBox.shrink();
                              final total = status?.totalRupiah ?? 0;
                              final fmt = (int n) => n.toString().replaceAllMapped(
                                  RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]}.');
                              final t = status?.contributionTravelRupiah ?? 0;
                              final b = status?.contributionBarangRupiah ?? 0;
                              final v = (status?.outstandingViolationFee ?? 0).round();
                              return Container(
                                width: double.infinity,
                                margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: Colors.orange.shade50,
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: Colors.orange.shade200),
                                ),
                                child: InkWell(
                                  onTap: () async {
                                    await Navigator.of(context).push(
                                      MaterialPageRoute(
                                        builder: (_) => const ContributionDriverScreen(),
                                      ),
                                    );
                                    if (context.mounted) _load();
                                  },
                                  borderRadius: BorderRadius.circular(8),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Icon(Icons.payment, size: 20, color: Colors.orange.shade800),
                                          const SizedBox(width: 8),
                                          Text(
                                            'Estimasi bayar: Rp ${fmt(total)}',
                                            style: TextStyle(
                                              fontWeight: FontWeight.w600,
                                              fontSize: 13,
                                              color: Colors.orange.shade900,
                                            ),
                                          ),
                                        ],
                                      ),
                                      if (t > 0 || b > 0 || v > 0) ...[
                                        const SizedBox(height: 4),
                                        Text(
                                          [
                                            if (t > 0) 'Travel Rp ${fmt(t)}',
                                            if (b > 0) 'Barang Rp ${fmt(b)}',
                                            if (v > 0) 'Denda Rp ${fmt(v)}',
                                          ].join('  •  '),
                                          style: TextStyle(fontSize: 11, color: Colors.orange.shade800),
                                        ),
                                      ],
                                      const SizedBox(height: 4),
                                      Text(
                                        'Ketuk untuk bayar via Google Play',
                                        style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.primary),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                          InkWell(
                            onTap: () => showContributionTariffDialog(context),
                            borderRadius: BorderRadius.circular(8),
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.info_outline, size: 20, color: Theme.of(context).colorScheme.primary),
                                  const SizedBox(width: 8),
                                  Text(
                                    TrakaL10n.of(context).contributionTariffButtonLabel,
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                      color: Theme.of(context).colorScheme.primary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                        Expanded(
                          child: RefreshIndicator(
                      onRefresh: _load,
                      child: ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: _records.length,
                        itemBuilder: (context, index) {
                          final r = _records[index];
                          return Card(
                            margin: const EdgeInsets.only(bottom: 12),
                            child: ListTile(
                              leading: CircleAvatar(
                                backgroundColor: Theme.of(context)
                                    .colorScheme
                                    .primaryContainer,
                                child: Icon(
                                  _iconForType(r.type),
                                  color: Theme.of(context).colorScheme.primary,
                                ),
                              ),
                              title: Text(
                                r.typeLabel,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              subtitle: Text(
                                r.type == PaymentType.contribution
                                    ? _buildContributionSubtitle(r)
                                    : _formatDate(r.paidAt),
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurfaceVariant,
                                ),
                                maxLines: 4,
                              ),
                              trailing: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text(
                                    _formatRupiah(r.amountRupiah),
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 14,
                                    ),
                                  ),
                                  Text(
                                    'Struk',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: Theme.of(context)
                                          .colorScheme
                                          .primary,
                                    ),
                                  ),
                                ],
                              ),
                              onTap: () => _showStruk(r),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                ],
              ),
    );
  }
}
