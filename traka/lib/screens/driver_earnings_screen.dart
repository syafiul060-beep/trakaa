import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';

import '../services/driver_earnings_pdf_service.dart';
import '../theme/app_theme.dart';
import '../services/driver_earnings_service.dart';
import '../widgets/contribution_tariff_dialog.dart';
import '../widgets/traka_l10n_scope.dart';
import 'payment_history_screen.dart';

/// Nama bulan Indonesia.
const List<String> _monthNames = [
  'Januari', 'Februari', 'Maret', 'April', 'Mei', 'Juni',
  'Juli', 'Agustus', 'September', 'Oktober', 'November', 'Desember',
];

/// Halaman pendapatan driver, potongan kontribusi, dan pelanggaran.
/// Akses dari Profil driver (menu seperti Riwayat Pembayaran).
class DriverEarningsScreen extends StatefulWidget {
  const DriverEarningsScreen({super.key});

  @override
  State<DriverEarningsScreen> createState() => _DriverEarningsScreenState();
}

class _DriverEarningsScreenState extends State<DriverEarningsScreen> {
  Map<String, dynamic>? _data;
  List<DriverEarningsOrderItem> _monthlyEarnings = [];
  List<DriverContributionItem> _monthlyContributions = [];
  List<DriverViolationItem> _monthlyViolations = [];
  bool _loading = true;
  bool _loadingMonthly = false;
  bool _loadingPdf = false;
  String? _error;
  int _selectedYear = DateTime.now().year;
  int _selectedMonth = DateTime.now().month;
  String? _driverName;

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
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) {
        if (mounted) {
          setState(() {
            _data = {
              'total': 0.0, 'today': 0.0, 'week': 0.0, 'count': 0,
              'contributionPaid': 0.0, 'violationPaid': 0.0,
              'violationCount': 0, 'outstandingViolation': 0.0,
            };
            _loading = false;
          });
        }
        return;
      }
      // Ambil displayName dari users
      final userDoc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
      final displayName = userDoc.data()?['displayName'] as String?;
      _driverName = (displayName?.trim().isNotEmpty == true) ? displayName : FirebaseAuth.instance.currentUser?.displayName ?? 'Driver';

      final total = await DriverEarningsService.getTotalEarnings(uid);
      final today = await DriverEarningsService.getTodayEarnings(uid);
      final week = await DriverEarningsService.getWeekEarnings(uid);
      final count = await DriverEarningsService.getCompletedTripCount(uid);
      final contributionPaid = await DriverEarningsService.getTotalContributionPaid(uid);
      final violationPaid = await DriverEarningsService.getTotalViolationPaid(uid);
      final violationCount = await DriverEarningsService.getViolationCount(uid);
      final outstandingViolation = await DriverEarningsService.getOutstandingViolationFee(uid);
      if (mounted) {
        setState(() {
          _data = {
            'total': total,
            'today': today,
            'week': week,
            'count': count,
            'contributionPaid': contributionPaid,
            'violationPaid': violationPaid,
            'violationCount': violationCount,
            'outstandingViolation': outstandingViolation,
          };
          _loading = false;
        });
        _loadMonthlyData();
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

  Future<void> _loadMonthlyData() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    setState(() => _loadingMonthly = true);
    try {
      final earnings = await DriverEarningsService.getEarningsByMonth(uid, _selectedYear, _selectedMonth);
      final contributions = await DriverEarningsService.getContributionsByMonth(uid, _selectedYear, _selectedMonth);
      final violations = await DriverEarningsService.getViolationsByMonth(uid, _selectedYear, _selectedMonth);
      if (mounted) {
        setState(() {
          _monthlyEarnings = earnings;
          _monthlyContributions = contributions;
          _monthlyViolations = violations;
          _loadingMonthly = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _monthlyEarnings = [];
          _monthlyContributions = [];
          _monthlyViolations = [];
          _loadingMonthly = false;
        });
      }
    }
  }

  Future<void> _downloadPdf() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    setState(() => _loadingPdf = true);
    try {
      final doc = await DriverEarningsPdfService.generateReport(
        driverName: _driverName ?? 'Driver',
        year: _selectedYear,
        month: _selectedMonth,
        earnings: _monthlyEarnings,
        contributions: _monthlyContributions,
        violations: _monthlyViolations,
      );
      final monthName = _monthNames[_selectedMonth - 1];
      final filename = 'laporan_pendapatan_${_selectedYear}_${_selectedMonth.toString().padLeft(2, '0')}_$monthName.pdf';
      final file = await DriverEarningsPdfService.savePdfToFile(doc, name: filename);
      if (!mounted) return;
      final l10n = TrakaL10n.of(context);
      await showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        builder: (ctx) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(l10n.pdfReportReadyTitle, style: Theme.of(ctx).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
                const SizedBox(height: 6),
                Text(l10n.pdfReportReadyHint, style: TextStyle(fontSize: 13, color: Theme.of(ctx).colorScheme.onSurfaceVariant)),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: () async {
                    Navigator.of(ctx).pop();
                    final r = await DriverEarningsPdfService.openPdfFile(file);
                    if (!mounted) return;
                    if (r.type != ResultType.done) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(l10n.failedToOpenPdf(r.message))),
                      );
                    }
                  },
                  icon: const Icon(Icons.open_in_new),
                  label: Text(l10n.viewPdf),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: () async {
                    Navigator.of(ctx).pop();
                    await DriverEarningsPdfService.sharePdfFile(file);
                  },
                  icon: const Icon(Icons.share),
                  label: Text(l10n.share),
                ),
              ],
            ),
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(TrakaL10n.of(context).failedToCreatePdf(e))),
        );
      }
    } finally {
      if (mounted) setState(() => _loadingPdf = false);
    }
  }

  String _fmt(int n) =>
      n.toString().replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]}.');

  String _fmtDate(DateTime dt) {
    final d = dt.day.toString().padLeft(2, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final y = dt.year;
    return '$d/$m/$y';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(TrakaL10n.of(context).driverEarningsTitle),
        actions: [
          IconButton(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const PaymentHistoryScreen(isDriver: true),
                ),
              );
            },
            icon: const Icon(Icons.receipt_long),
            tooltip: TrakaL10n.of(context).paymentHistory,
          ),
          IconButton(
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: _loading && _data == null
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
                          style: TextStyle(color: Theme.of(context).colorScheme.error),
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
              : RefreshIndicator(
                  onRefresh: _load,
                  child: SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(16),
                    child: _buildContent(),
                  ),
                ),
    );
  }

  Widget _buildContent() {
    final d = _data;
    if (d == null) return const SizedBox.shrink();
    final total = (d['total'] as num?)?.toDouble() ?? 0;
    final today = (d['today'] as num?)?.toDouble() ?? 0;
    final week = (d['week'] as num?)?.toDouble() ?? 0;
    final count = (d['count'] as num?)?.toInt() ?? 0;
    final contributionPaid = (d['contributionPaid'] as num?)?.toDouble() ?? 0;
    final violationPaid = (d['violationPaid'] as num?)?.toDouble() ?? 0;
    final violationCount = (d['violationCount'] as num?)?.toInt() ?? 0;
    final outstandingViolation = (d['outstandingViolation'] as num?)?.toDouble() ?? 0;
    final hasActivity = count > 0 || contributionPaid > 0 || violationPaid > 0 || violationCount > 0;

    if (!hasActivity) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 48),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.account_balance_wallet_outlined,
                size: 64,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              const SizedBox(height: 16),
              Text(
                TrakaL10n.of(context).driverEarningsEmpty,
                style: TextStyle(
                  fontSize: 16,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
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
                        'Jenis harga kontribusi',
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
          ),
        ),
      );
    }

    final totalEarningsMonth = _monthlyEarnings.fold<double>(0, (s, e) => s + e.amountRupiah);
    final totalContribMonth = _monthlyContributions.fold<double>(0, (s, c) => s + c.amountRupiah);
    final totalViolMonth = _monthlyViolations.fold<double>(0, (s, v) => s + v.amountRupiah);
    final totalDeductionsMonth = totalContribMonth + totalViolMonth;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          onTap: () => showContributionTariffDialog(context),
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
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
                const SizedBox(width: 4),
                Icon(Icons.touch_app, size: 18, color: Theme.of(context).colorScheme.primary),
              ],
            ),
          ),
        ),
        // Ringkasan singkat
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.account_balance_wallet, color: Colors.green.shade700),
                    const SizedBox(width: 8),
                    Text(
                      TrakaL10n.of(context).driverEarningsTitle,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(TrakaL10n.of(context).today, style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant)),
                        Text('Rp ${_fmt(today.round())}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                      ],
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(TrakaL10n.of(context).thisWeek, style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant)),
                        Text('Rp ${_fmt(week.round())}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                const Divider(),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(TrakaL10n.of(context).driverEarningsTotal(count), style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant)),
                    Text('Rp ${_fmt(total.round())}', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.green.shade700)),
                  ],
                ),
                if (contributionPaid > 0 || violationPaid > 0 || outstandingViolation > 0) ...[
                  const Divider(),
                  const SizedBox(height: 8),
                  Text(TrakaL10n.of(context).driverEarningsDeductionsPaid, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Theme.of(context).colorScheme.onSurfaceVariant)),
                  if (contributionPaid > 0) Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text(TrakaL10n.of(context).contribution, style: const TextStyle(fontSize: 13)), Text('Rp ${_fmt(contributionPaid.round())}', style: const TextStyle(fontSize: 13))]),
                  if (violationPaid > 0) Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text(TrakaL10n.of(context).driverEarningsViolationCount(violationCount), style: const TextStyle(fontSize: 13)), Text('Rp ${_fmt(violationPaid.round())}', style: const TextStyle(fontSize: 13))]),
                  if (outstandingViolation > 0) Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text(TrakaL10n.of(context).driverEarningsOutstanding, style: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.error)), Text('Rp ${_fmt(outstandingViolation.round())}', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Theme.of(context).colorScheme.error))]),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),

        // Pilih bulan & Unduh PDF
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Laporan per Bulan', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Theme.of(context).colorScheme.onSurface)),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<int>(
                        key: ValueKey<int>(_selectedMonth),
                        initialValue: _selectedMonth,
                        decoration: InputDecoration(labelText: 'Bulan', border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppTheme.radiusSm))),
                        items: List.generate(12, (i) => DropdownMenuItem(value: i + 1, child: Text(_monthNames[i]))),
                        onChanged: (v) {
                          if (v != null) {
                            setState(() => _selectedMonth = v);
                            _loadMonthlyData();
                          }
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: DropdownButtonFormField<int>(
                        key: ValueKey<int>(_selectedYear),
                        initialValue: _selectedYear,
                        decoration: InputDecoration(labelText: 'Tahun', border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppTheme.radiusSm))),
                        items: List.generate(5, (i) {
                          final y = DateTime.now().year - 2 + i;
                          return DropdownMenuItem(value: y, child: Text('$y'));
                        }),
                        onChanged: (v) {
                          if (v != null) {
                            setState(() => _selectedYear = v);
                            _loadMonthlyData();
                          }
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: (_loadingPdf || totalEarningsMonth <= 0) ? null : _downloadPdf,
                    icon: _loadingPdf ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.picture_as_pdf),
                    label: Text(_loadingPdf ? TrakaL10n.of(context).driverEarningsPdfMaking : TrakaL10n.of(context).driverEarningsPdfButtonLabel),
                  ),
                ),
                if (totalEarningsMonth <= 0)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      'Unduh PDF hanya tersedia jika ada pendapatan di bulan terpilih.',
                      style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant),
                    ),
                  ),
                const SizedBox(height: 8),
                Text(
                  'Dokumen PDF dapat digunakan sebagai bukti pendapatan. Diverifikasi oleh Aplikasi Traka.',
                  style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),

        // Detail per bulan
        Text('Detail ${_monthNames[_selectedMonth - 1]} $_selectedYear', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Theme.of(context).colorScheme.onSurface)),
        const SizedBox(height: 8),

        if (_loadingMonthly)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: CircularProgressIndicator()),
          )
        else ...[
        // Tabel pendapatan
        if (_monthlyEarnings.isNotEmpty) ...[
          _buildSectionTitle('A. Pendapatan dari Perjalanan'),
          Card(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                columns: const [
                  DataColumn(label: Text('No')),
                  DataColumn(label: Text('Tanggal')),
                  DataColumn(label: Text('No. Pesanan')),
                  DataColumn(label: Text('Jenis')),
                  DataColumn(label: Text('Rute')),
                  DataColumn(label: Text('Nominal', textAlign: TextAlign.right)),
                ],
                rows: [
                  ..._monthlyEarnings.asMap().entries.map((e) {
                    final o = e.value;
                    return DataRow(cells: [
                      DataCell(Text('${e.key + 1}')),
                      DataCell(Text(_fmtDate(o.completedAt))),
                      DataCell(Text(o.orderNumber)),
                      DataCell(Text(o.typeLabel)),
                      DataCell(Text(o.routeText, maxLines: 2, overflow: TextOverflow.ellipsis)),
                      DataCell(Text('Rp ${_fmt(o.amountRupiah.round())}', textAlign: TextAlign.right)),
                    ]);
                  }),
                  DataRow(
                    cells: [
                      const DataCell(Text('Subtotal', style: TextStyle(fontWeight: FontWeight.bold))),
                      const DataCell(Text('')),
                      const DataCell(Text('')),
                      const DataCell(Text('')),
                      const DataCell(Text('')),
                      DataCell(Text('Rp ${_fmt(totalEarningsMonth.round())}', textAlign: TextAlign.right, style: const TextStyle(fontWeight: FontWeight.bold))),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
        ],

        // Tabel potongan
        if (_monthlyContributions.isNotEmpty || _monthlyViolations.isNotEmpty) ...[
          _buildSectionTitle('B. Potongan'),
          if (_monthlyContributions.isNotEmpty) ...[
            const Text('Kontribusi:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
            Card(
              child: DataTable(
                columns: const [
                  DataColumn(label: Text('Tanggal')),
                  DataColumn(label: Text('Ref')),
                  DataColumn(label: Text('Nominal', textAlign: TextAlign.right)),
                ],
                rows: [
                  ..._monthlyContributions.map((c) => DataRow(cells: [
                    DataCell(Text(_fmtDate(c.paidAt))),
                    DataCell(Text(c.orderId ?? '-')),
                    DataCell(Text('Rp ${_fmt(c.amountRupiah.round())}', textAlign: TextAlign.right)),
                  ])),
                ],
              ),
            ),
            const SizedBox(height: 8),
          ],
          if (_monthlyViolations.isNotEmpty) ...[
            const Text('Pelanggaran:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
            Card(
              child: DataTable(
                columns: const [
                  DataColumn(label: Text('Tanggal')),
                  DataColumn(label: Text('No. Pesanan')),
                  DataColumn(label: Text('Nominal', textAlign: TextAlign.right)),
                ],
                rows: [
                  ..._monthlyViolations.map((v) => DataRow(cells: [
                    DataCell(Text(_fmtDate(v.paidAt))),
                    DataCell(Text(v.orderId ?? '-')),
                    DataCell(Text('Rp ${_fmt(v.amountRupiah.round())}', textAlign: TextAlign.right)),
                  ])),
                ],
              ),
            ),
            const SizedBox(height: 8),
          ],
          Card(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Total Potongan:', style: TextStyle(fontWeight: FontWeight.bold)),
                  Text('Rp ${_fmt(totalDeductionsMonth.round())}', style: const TextStyle(fontWeight: FontWeight.bold)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
        ],

        if (_monthlyEarnings.isEmpty && _monthlyContributions.isEmpty && _monthlyViolations.isEmpty)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                'Tidak ada data untuk ${_monthNames[_selectedMonth - 1]} $_selectedYear.',
                style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(title, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Theme.of(context).colorScheme.onSurface)),
    );
  }
}
