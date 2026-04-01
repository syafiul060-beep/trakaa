import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../models/order_model.dart';
import '../services/chat_service.dart';
import '../services/driver_transfer_service.dart';
import '../theme/app_theme.dart';
import '../theme/responsive.dart';
import 'traka_bottom_sheet.dart';
import '../widgets/traka_l10n_scope.dart';
import 'driver_contact_picker.dart';
import 'traka_loading_indicator.dart';
import '../theme/traka_snackbar.dart';

/// Sheet untuk Oper Driver: pilih order (multi), input driver kedua, validasi kapasitas.
/// Kirim barang tidak bisa dioper. Bisa dipakai dari Beranda atau Jadwal.
Future<void> showOperDriverSheet(
  BuildContext context, {
  required List<OrderModel> orders,
  required void Function(List<(String, String)> transfers) onTransfersCreated,
}) {
  return showTrakaModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => _OperDriverSheet(
      orders: orders,
      onTransfersCreated: (transfers) {
        Navigator.pop(ctx);
        onTransfersCreated(transfers);
      },
    ),
  );
}

/// Dialog menampilkan barcode untuk di-scan driver kedua (bisa banyak jika multi-oper).
void showOperDriverBarcodeDialog(
  BuildContext context, {
  required List<(String, String)> transfers,
}) {
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => _OperDriverBarcodeDialog(transfers: transfers),
  );
}

class _OperDriverSheet extends StatefulWidget {
  final List<OrderModel> orders;
  final void Function(List<(String, String)> transfers) onTransfersCreated;

  const _OperDriverSheet({
    required this.orders,
    required this.onTransfersCreated,
  });

  @override
  State<_OperDriverSheet> createState() => _OperDriverSheetState();
}

class _OperDriverSheetState extends State<_OperDriverSheet> {
  final Set<OrderModel> _selectedOrders = {};
  final _phoneController = TextEditingController();
  Map<String, dynamic>? _selectedDriverData;
  bool _loading = false;

  int get _totalPenumpang =>
      _selectedOrders.fold(0, (s, o) => s + o.totalPenumpang);
  int get _driverCapacity =>
      (_selectedDriverData?['vehicleJumlahPenumpang'] as int?) ?? 0;
  bool get _capacityOk =>
      _driverCapacity > 0 && _totalPenumpang <= _driverCapacity;

  @override
  void dispose() {
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _pickDriverFromContacts() async {
    showDriverContactPicker(
      context: context,
      onSelect: (phone, data) {
        if (data != null) {
          setState(() {
            _phoneController.text = phone;
            _selectedDriverData = data;
          });
        }
      },
    );
  }

  Future<void> _submit() async {
    if (_selectedOrders.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Pilih pesanan yang akan dioper')),
      );
      return;
    }
    final phone = _phoneController.text.trim();
    if (phone.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nomor HP driver kedua wajib')),
      );
      return;
    }
    final driverData = _selectedDriverData;
    if (driverData == null || driverData['uid'] == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Pilih driver kedua dari kontak yang terdaftar sebagai driver',
          ),
        ),
      );
      return;
    }
    if (!_capacityOk) {
      ScaffoldMessenger.of(context).showSnackBar(
        TrakaSnackBar.error(context, Text(
            'Kapasitas mobil driver kedua ($_driverCapacity orang) tidak cukup untuk $_totalPenumpang penumpang.',
          )),
      );
      return;
    }

    setState(() => _loading = true);
    final transfers = <(String, String)>[];
    for (final order in _selectedOrders) {
      final (
        transferId,
        barcodePayload,
        error,
      ) = await DriverTransferService.createTransfer(
        orderId: order.id,
        toDriverUid: driverData['uid'] as String,
        toDriverPhone: phone,
      );
      if (!mounted) return;
      if (error != null) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          TrakaSnackBar.error(context, Text(error)),
        );
        return;
      }
      if (transferId != null && barcodePayload != null) {
        transfers.add((transferId, barcodePayload));
        await ChatService.sendMessage(
          order.id,
          'Saya sedang mengoper perjalanan Anda ke driver lain. Driver baru akan menghubungi dan menjemput Anda.',
        );
      }
    }
    setState(() => _loading = false);
    if (transfers.isNotEmpty) {
      widget.onTransfersCreated(transfers);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SingleChildScrollView(
        child: Padding(
          padding: EdgeInsets.all(context.responsive.spacing(20)),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Oper Driver',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                'Pilih penumpang yang sudah dijemput (sesuai kapasitas mobil driver kedua). Kirim barang tidak bisa dioper.',
                style: TextStyle(
                  fontSize: 13,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 16),
              ...widget.orders.map(
                (o) => CheckboxListTile(
                  title: Text(
                    '${o.passengerName} - ${o.destText}',
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    '${o.orderNumber ?? o.id} • ${o.totalPenumpang} orang',
                  ),
                  value: _selectedOrders.contains(o),
                  tristate: false,
                  activeColor: Theme.of(context).colorScheme.primary,
                  onChanged: (v) {
                    setState(() {
                      if (v == true) {
                        _selectedOrders.add(o);
                      } else {
                        _selectedOrders.remove(o);
                      }
                    });
                  },
                  controlAffinity: ListTileControlAffinity.leading,
                ),
              ),
              if (_selectedOrders.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  'Total: $_totalPenumpang penumpang',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ],
              const SizedBox(height: 16),
              const Text(
                'Driver kedua',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              if (_selectedDriverData != null && _driverCapacity > 0)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    'Kapasitas mobil: $_driverCapacity orang',
                    style: TextStyle(
                      fontSize: 13,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              if (_selectedOrders.isNotEmpty &&
                  _driverCapacity > 0 &&
                  !_capacityOk)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    'Kapasitas tidak cukup ($_totalPenumpang > $_driverCapacity)',
                    style: const TextStyle(
                      fontSize: 13,
                      color: Colors.red,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _phoneController,
                      autocorrect: false,
                      enableSuggestions: false,
                      decoration: InputDecoration(
                        labelText: 'No. HP driver kedua',
                        hintText: '08123456789',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppTheme.radiusSm)),
                      ),
                      keyboardType: TextInputType.phone,
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    onPressed: _pickDriverFromContacts,
                    icon: const Icon(Icons.contacts),
                    tooltip: 'Buka kontak HP',
                  ),
                ],
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: (_loading || !_capacityOk) ? null : _submit,
                child: _loading
                    ? trakaLoadingOnDarkSurface(size: 24)
                    : Text(
                        _selectedOrders.length > 1
                            ? 'Buat ${_selectedOrders.length} Oper & Tampilkan Barcode'
                            : 'Buat Oper & Tampilkan Barcode',
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _OperDriverBarcodeDialog extends StatelessWidget {
  final List<(String, String)> transfers;

  const _OperDriverBarcodeDialog({required this.transfers});

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
        transfers.length > 1
            ? '${TrakaL10n.of(context).showBarcodeToSecondDriver} (${transfers.length} transfer)'
            : TrakaL10n.of(context).showBarcodeToSecondDriver,
      ),
      content: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              TrakaL10n.of(context).driverSecondScanHint,
              style: const TextStyle(fontSize: 13),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ...transfers.asMap().entries.map((e) {
              final i = e.key + 1;
              final (_, payload) = e.value;
              return Padding(
                padding: EdgeInsets.only(bottom: i < transfers.length ? 24 : 0),
                child: Column(
                  children: [
                    if (transfers.length > 1)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text(
                          TrakaL10n.of(context).transferCount(i, transfers.length),
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                          ),
                        ),
                      ),
                    Container(
                      padding: const EdgeInsets.all(16),
                      color: Colors.white,
                      child: QrImageView(
                        data: payload,
                        version: QrVersions.auto,
                        size: 200,
                      ),
                    ),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Tutup'),
        ),
      ],
    );
  }
}
