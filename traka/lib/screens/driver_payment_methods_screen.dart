import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../config/traka_api_config.dart';
import '../services/traka_api_service.dart';

/// Kelola rekening / e-wallet / QRIS untuk instruksi bayar penumpang (via API hybrid).
class DriverPaymentMethodsScreen extends StatefulWidget {
  const DriverPaymentMethodsScreen({super.key});

  @override
  State<DriverPaymentMethodsScreen> createState() =>
      _DriverPaymentMethodsScreenState();
}

class _DriverPaymentMethodsScreenState extends State<DriverPaymentMethodsScreen> {
  bool _loading = true;
  List<Map<String, dynamic>> _items = [];

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    if (!TrakaApiConfig.isApiEnabled) {
      setState(() {
        _loading = false;
        _items = [];
      });
      return;
    }
    setState(() => _loading = true);
    final list = await TrakaApiService.listMyPaymentMethods();
    if (mounted) {
      setState(() {
        _items = list;
        _loading = false;
      });
    }
  }

  Future<void> _addDialog() async {
    String type = 'bank';
    final bankCtrl = TextEditingController();
    final ewalletCtrl = TextEditingController();
    final numberCtrl = TextEditingController();
    final holderCtrl = TextEditingController();
    String? qrisUrl;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) => AlertDialog(
          title: const Text('Tambah metode bayar'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: type,
                  decoration: const InputDecoration(labelText: 'Jenis'),
                  items: const [
                    DropdownMenuItem(value: 'bank', child: Text('Bank')),
                    DropdownMenuItem(value: 'ewallet', child: Text('E-wallet')),
                    DropdownMenuItem(value: 'qris', child: Text('QRIS')),
                  ],
                  onChanged: (v) => setSt(() => type = v ?? 'bank'),
                ),
                if (type == 'bank')
                  TextField(
                    controller: bankCtrl,
                    autocorrect: false,
                    enableSuggestions: false,
                    decoration: const InputDecoration(labelText: 'Nama bank'),
                  ),
                if (type == 'ewallet')
                  TextField(
                    controller: ewalletCtrl,
                    autocorrect: false,
                    enableSuggestions: false,
                    decoration: const InputDecoration(
                      labelText: 'Provider (DANA, GoPay, …)',
                    ),
                  ),
                if (type != 'qris')
                  TextField(
                    controller: numberCtrl,
                    autocorrect: false,
                    enableSuggestions: false,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Nomor rekening / HP e-wallet',
                    ),
                  ),
                TextField(
                  controller: holderCtrl,
                  autocorrect: false,
                  enableSuggestions: false,
                  decoration: const InputDecoration(
                    labelText: 'Nama pemilik (harus sama profil)',
                  ),
                ),
                if (type == 'qris') ...[
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: () async {
                      final uid = FirebaseAuth.instance.currentUser?.uid;
                      if (uid == null) return;
                      final x = await ImagePicker().pickImage(
                        source: ImageSource.gallery,
                        maxWidth: 1600,
                        imageQuality: 85,
                      );
                      if (x == null) return;
                      final ref = FirebaseStorage.instance
                          .ref('driver_qris/$uid/${DateTime.now().millisecondsSinceEpoch}.jpg');
                      await ref.putFile(File(x.path));
                      final url = await ref.getDownloadURL();
                      setSt(() => qrisUrl = url);
                    },
                    icon: const Icon(Icons.upload),
                    label: Text(qrisUrl == null ? 'Unggah gambar QRIS' : 'QRIS terunggah'),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Batal'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Simpan'),
            ),
          ],
        ),
      ),
    );

    final holderName = holderCtrl.text.trim();
    final bankName = bankCtrl.text.trim();
    final ewalletName = ewalletCtrl.text.trim();
    final numStr = numberCtrl.text.trim();
    bankCtrl.dispose();
    ewalletCtrl.dispose();
    numberCtrl.dispose();
    holderCtrl.dispose();

    if (ok != true || !mounted) return;

    final body = <String, dynamic>{
      'type': type,
      'accountHolderName': holderName,
    };
    if (type == 'bank') {
      body['bankName'] = bankName;
      body['accountNumber'] = numStr;
    } else if (type == 'ewallet') {
      body['ewalletProvider'] = ewalletName;
      body['accountNumber'] = numStr;
    } else {
      body['qrisImageUrl'] = qrisUrl ?? '';
    }

    final r = await TrakaApiService.createDriverPaymentMethod(body);
    if (!mounted) return;
    if (r.ok) {
      final msg = r.data?['message'] as String?;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            msg ?? ((r.data?['status'] == 'pending_review')
                ? 'Menunggu tinjauan admin (nama beda dengan profil).'
                : 'Metode disimpan.'),
          ),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(r.error ?? 'Gagal')),
      );
    }
    await _reload();
  }

  Future<void> _remove(String id) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Hapus metode?'),
        content: const Text('Metode tidak lagi ditampilkan ke penumpang.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Batal')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Hapus')),
        ],
      ),
    );
    if (ok != true) return;
    final r = await TrakaApiService.deleteDriverPaymentMethod(id);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(r.ok ? 'Dihapus' : (r.error ?? 'Gagal'))),
      );
    }
    await _reload();
  }

  @override
  Widget build(BuildContext context) {
    if (!TrakaApiConfig.isApiEnabled) {
      return Scaffold(
        appBar: AppBar(title: const Text('Rekening & QRIS')),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'Aktifkan mode hybrid (TRAKA_USE_HYBRID + URL API) untuk mengatur instruksi bayar.',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Rekening & QRIS')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _loading ? null : _addDialog,
        icon: const Icon(Icons.add),
        label: const Text('Tambah'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _reload,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  const Text(
                    'Nama pemilik harus sama dengan nama profil Anda. Jika beda, status menunggu admin — hubungi admin dari menu Bantuan / chat.',
                    style: TextStyle(fontSize: 13),
                  ),
                  const SizedBox(height: 16),
                  if (_items.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(24),
                      child: Text('Belum ada metode. Tambah rekening/e-wallet/QRIS.'),
                    )
                  else
                    ..._items.map((m) {
                      final st = m['status'] as String? ?? '';
                      final pm = m['profileMismatch'] == true;
                      return Card(
                        child: ListTile(
                          title: Text(
                            '${m['type']} · $st${pm ? ' (nama beda profil)' : ''}',
                          ),
                          subtitle: Text(
                            m['type'] == 'qris'
                                ? (m['qrisImageUrl'] as String? ?? '')
                                : '${m['bankName'] ?? m['ewalletProvider'] ?? ''} · ${m['accountNumber'] ?? ''}\n${m['accountHolderName'] ?? ''}',
                          ),
                          isThreeLine: true,
                          trailing: IconButton(
                            icon: const Icon(Icons.delete_outline),
                            onPressed: () => _remove(m['id'] as String),
                          ),
                        ),
                      );
                    }),
                ],
              ),
            ),
    );
  }
}
