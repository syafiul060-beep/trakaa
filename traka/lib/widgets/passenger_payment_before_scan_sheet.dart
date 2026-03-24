import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../config/traka_api_config.dart';
import '../models/order_model.dart';
import '../services/order_service.dart';
import '../services/traka_api_service.dart';

/// Alur bayar ke driver sebelum scan barcode (non-escrow). Butuh hybrid + API.
class PassengerPaymentBeforeScanSheet extends StatefulWidget {
  const PassengerPaymentBeforeScanSheet({super.key, required this.order});

  final OrderModel order;

  static Future<bool?> show(BuildContext context, {required OrderModel order}) {
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (ctx) => PassengerPaymentBeforeScanSheet(order: order),
    );
  }

  @override
  State<PassengerPaymentBeforeScanSheet> createState() =>
      _PassengerPaymentBeforeScanSheetState();
}

class _PassengerPaymentBeforeScanSheetState
    extends State<PassengerPaymentBeforeScanSheet> {
  bool _disclaimer = false;
  bool _loading = false;
  List<Map<String, dynamic>> _methods = [];
  String? _step; // null = pilih metode, 'detail' = tampil satu metode

  Map<String, dynamic>? _selected;

  @override
  void initState() {
    super.initState();
    if (!TrakaApiConfig.isApiEnabled) {
      _disclaimer = false;
    } else {
      _loadMethods();
    }
  }

  Future<void> _loadMethods() async {
    setState(() => _loading = true);
    final list =
        await TrakaApiService.getOrderDriverPaymentMethods(widget.order.id);
    if (mounted) {
      setState(() {
        _methods = list;
        _loading = false;
      });
    }
  }

  Future<void> _saveCash() async {
    setState(() => _loading = true);
    try {
      await OrderService.updatePassengerPayFlow(
        orderId: widget.order.id,
        passengerPayMethod: 'cash',
        setDisclaimer: true,
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (_) {
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Gagal menyimpan. Coba lagi.')),
        );
      }
    }
  }

  Future<void> _saveNonCash(String type, String methodId) async {
    setState(() => _loading = true);
    try {
      await OrderService.updatePassengerPayFlow(
        orderId: widget.order.id,
        passengerPayMethod: type,
        passengerPayMethodId: methodId,
        setDisclaimer: true,
        setMarkedPaid: true,
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (_) {
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Gagal menyimpan. Coba lagi.')),
        );
      }
    }
  }

  List<Map<String, dynamic>> _byType(String t) =>
      _methods.where((m) => m['type'] == t).toList();

  @override
  Widget build(BuildContext context) {
    final pad = MediaQuery.paddingOf(context);
    if (!TrakaApiConfig.isApiEnabled) {
      return Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 16,
          bottom: pad.bottom + 20,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Pembayaran ke driver',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),
            const Text(
              'Traka tidak menampung uang Anda. Konfirmasi pembayaran adalah kesepakatan Anda dengan driver.',
              style: TextStyle(fontSize: 14),
            ),
            const SizedBox(height: 16),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: _disclaimer,
              onChanged: (v) => setState(() => _disclaimer = v ?? false),
              title: const Text('Saya mengerti'),
            ),
            FilledButton(
              onPressed: !_disclaimer || _loading
                  ? null
                  : () async {
                      await _saveCash();
                    },
              child: _loading
                  ? const SizedBox(
                      height: 22,
                      width: 22,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Lanjut ke scan barcode'),
            ),
          ],
        ),
      );
    }

    if (_step == 'detail' && _selected != null) {
      final m = _selected!;
      final type = m['type'] as String? ?? '';
      final qrisUrl = m['qrisImageUrl'] as String?;
      return Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 16,
          bottom: pad.bottom + 20,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                IconButton(
                  onPressed: () => setState(() {
                    _step = null;
                    _selected = null;
                  }),
                  icon: const Icon(Icons.arrow_back),
                ),
                const Expanded(
                  child: Text(
                    'Instruksi bayar',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
            if (type == 'bank' || type == 'ewallet') ...[
              Text(
                type == 'bank'
                    ? (m['bankName'] as String? ?? 'Bank')
                    : (m['ewalletProvider'] as String? ?? 'E-wallet'),
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              SelectableText(
                m['accountNumber'] as String? ?? '-',
                style: const TextStyle(fontSize: 20, letterSpacing: 1),
              ),
              const SizedBox(height: 4),
              Text('a.n. ${m['accountHolderName'] ?? '-'}'),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () async {
                  final n = m['accountNumber'] as String? ?? '';
                  await Clipboard.setData(ClipboardData(text: n));
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Nomor disalin')),
                    );
                  }
                },
                icon: const Icon(Icons.copy),
                label: const Text('Salin nomor'),
              ),
            ],
            if (type == 'qris' && qrisUrl != null && qrisUrl.isNotEmpty) ...[
              const Text('Scan atau screenshot QR berikut.'),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.network(
                  qrisUrl,
                  height: 220,
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) => const Text('Gagal memuat gambar'),
                ),
              ),
            ],
            const SizedBox(height: 16),
            const Text(
              'Setelah transfer, tandai di bawah lalu lanjut scan barcode ke driver.',
              style: TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: _loading
                  ? null
                  : () => _saveNonCash(type, m['id'] as String),
              child: _loading
                  ? const SizedBox(
                      height: 22,
                      width: 22,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Sudah bayar — lanjut scan'),
            ),
          ],
        ),
      );
    }

    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 16,
        bottom: pad.bottom + 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            widget.order.isKirimBarang
                ? 'Bayar ke driver (Anda pengirim)'
                : 'Bayar ke driver',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Text(
            widget.order.isKirimBarang
                ? 'Sebagai pengirim barang, pilih cara bayar ke driver. Penerima barang tidak lewat langkah ini — mereka hanya scan saat terima barang.'
                : 'Traka tidak menampung uang. Instruksi di bawah dari driver; konfirmasi transfer adalah antara Anda dan driver.',
            style: const TextStyle(fontSize: 13),
          ),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            value: _disclaimer,
            onChanged: (v) => setState(() => _disclaimer = v ?? false),
            title: const Text('Saya mengerti'),
          ),
          if (!_disclaimer)
            const Padding(
              padding: EdgeInsets.only(bottom: 8),
              child: Text(
                'Centang pernyataan di atas untuk memilih metode.',
                style: TextStyle(fontSize: 12, color: Colors.orange),
              ),
            ),
          if (_loading)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_disclaimer) ...[
            FilledButton.icon(
              onPressed: () => _saveCash(),
              icon: const Icon(Icons.payments_outlined),
              label: const Text('Bayar tunai — langsung scan'),
            ),
            const SizedBox(height: 8),
            _methodTile(
              context,
              title: 'Transfer bank',
              subtitle: _byType('bank').isEmpty
                  ? 'Driver belum mengatur'
                  : '${_byType('bank').length} rekening',
              enabled: _byType('bank').isNotEmpty,
              onTap: () => _pickFirstOrList('bank'),
            ),
            _methodTile(
              context,
              title: 'E-wallet',
              subtitle: _byType('ewallet').isEmpty
                  ? 'Driver belum mengatur'
                  : '${_byType('ewallet').length} akun',
              enabled: _byType('ewallet').isNotEmpty,
              onTap: () => _pickFirstOrList('ewallet'),
            ),
            _methodTile(
              context,
              title: 'QRIS',
              subtitle: _byType('qris').isEmpty
                  ? 'Driver belum mengatur'
                  : '${_byType('qris').length} QR',
              enabled: _byType('qris').isNotEmpty,
              onTap: () => _pickFirstOrList('qris'),
            ),
          ],
        ],
      ),
    );
  }

  void _pickFirstOrList(String type) {
    final list = _byType(type);
    if (list.isEmpty) return;
    if (list.length == 1) {
      setState(() {
        _selected = list.first;
        _step = 'detail';
      });
      return;
    }
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'Pilih akun',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            ...list.map(
              (m) => ListTile(
                title: Text(
                  type == 'bank'
                      ? (m['bankName'] as String? ?? 'Bank')
                      : type == 'ewallet'
                          ? (m['ewalletProvider'] as String? ?? 'E-wallet')
                          : 'QRIS',
                ),
                subtitle: Text(m['accountNumber'] as String? ?? ''),
                onTap: () {
                  Navigator.pop(ctx);
                  setState(() {
                    _selected = m;
                    _step = 'detail';
                  });
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _methodTile(
    BuildContext context, {
    required String title,
    required String subtitle,
    required bool enabled,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: OutlinedButton(
        onPressed: enabled ? onTap : null,
        child: ListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(title),
          subtitle: Text(subtitle),
        ),
      ),
    );
  }
}
