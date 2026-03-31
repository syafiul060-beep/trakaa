import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../models/order_model.dart';
import '../theme/app_theme.dart';
import 'traka_l10n_scope.dart';

/// Step 1: Pilih jenis barang (Dokumen / Kargo). Kargo: isi nama, berat, dimensi.
class KirimBarangPilihJenisSheet extends StatefulWidget {
  final void Function(Map<String, dynamic> data) onSelected;
  final VoidCallback? onCancel;

  const KirimBarangPilihJenisSheet({
    super.key,
    required this.onSelected,
    this.onCancel,
  });

  @override
  State<KirimBarangPilihJenisSheet> createState() =>
      _KirimBarangPilihJenisSheetState();
}

class _KirimBarangPilihJenisSheetState extends State<KirimBarangPilihJenisSheet> {
  String? _selectedCategory;
  File? _barangFotoFile;
  bool _isUploading = false;
  final _namaController = TextEditingController();
  final _beratController = TextEditingController();
  final _panjangController = TextEditingController();
  final _lebarController = TextEditingController();
  final _tinggiController = TextEditingController();

  @override
  void dispose() {
    _namaController.dispose();
    _beratController.dispose();
    _panjangController.dispose();
    _lebarController.dispose();
    _tinggiController.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt),
              title: const Text('Kamera'),
              onTap: () => Navigator.pop(ctx, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('Galeri'),
              onTap: () => Navigator.pop(ctx, ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
    if (source == null || !mounted) return;
    try {
      final picker = ImagePicker();
      final xFile = await picker.pickImage(source: source, maxWidth: 1200, imageQuality: 85);
      if (xFile == null || !mounted) return;
      setState(() => _barangFotoFile = File(xFile.path));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal memilih foto: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _submit() async {
    if (_selectedCategory == null) return;
    if (_selectedCategory == OrderModel.barangCategoryKargo) {
      final nama = _namaController.text.trim();
      final berat = double.tryParse(_beratController.text.replaceAll(',', '.')) ?? 0;
      final panjang = double.tryParse(_panjangController.text.replaceAll(',', '.')) ?? 0;
      final lebar = double.tryParse(_lebarController.text.replaceAll(',', '.')) ?? 0;
      final tinggi = double.tryParse(_tinggiController.text.replaceAll(',', '.')) ?? 0;
      if (nama.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(TrakaL10n.of(context).enterItemNameType), backgroundColor: Colors.red),
        );
        return;
      }
      if (berat < 0.1 || berat > 100) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(TrakaL10n.of(context).weightRequired), backgroundColor: Colors.red),
        );
        return;
      }
      if (panjang <= 0 || lebar <= 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(TrakaL10n.of(context).dimensionsRequired), backgroundColor: Colors.red),
        );
        return;
      }
      const maxDimensi = 300.0;
      if (panjang > maxDimensi || lebar > maxDimensi || (tinggi > 0 && tinggi > maxDimensi)) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(TrakaL10n.of(context).maxDimensionSize), backgroundColor: Colors.red),
        );
        return;
      }
      final totalDimensi = panjang + lebar + (tinggi > 0 ? tinggi : 0);
      if (totalDimensi > 400) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(TrakaL10n.of(context).totalDimensionsMax), backgroundColor: Colors.red),
        );
        return;
      }
      String? barangFotoUrl;
      if (_barangFotoFile != null) {
        setState(() => _isUploading = true);
        try {
          final user = FirebaseAuth.instance.currentUser;
          if (user == null) throw Exception('User tidak login');
          final ref = FirebaseStorage.instance
              .ref()
              .child('barang_photos')
              .child(user.uid)
              .child('${DateTime.now().millisecondsSinceEpoch}.jpg');
          await ref.putFile(_barangFotoFile!);
          barangFotoUrl = await ref.getDownloadURL();
        } catch (e) {
          if (mounted) {
            setState(() => _isUploading = false);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Gagal upload foto: $e'), backgroundColor: Colors.red),
            );
          }
          return;
        }
        if (mounted) setState(() => _isUploading = false);
      }
      widget.onSelected({
        'barangCategory': OrderModel.barangCategoryKargo,
        'barangNama': nama,
        'barangBeratKg': berat,
        'barangPanjangCm': panjang,
        'barangLebarCm': lebar,
        'barangTinggiCm': tinggi > 0 ? tinggi : null,
        'barangFotoUrl':? barangFotoUrl,
      });
    } else {
      widget.onSelected({'barangCategory': OrderModel.barangCategoryDokumen});
    }
  }

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final isKargo = _selectedCategory == OrderModel.barangCategoryKargo;
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: EdgeInsets.fromLTRB(
        20,
        20,
        20,
        mediaQuery.viewPadding.bottom + mediaQuery.viewInsets.bottom + 20,
      ),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Pilih jenis kirim barang',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Pilih kategori barang yang akan dikirim. Untuk kargo, isi detail barang.',
                style: TextStyle(
                  fontSize: 13,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Biaya Lacak Barang: Rp 10.000 - 25.000 (tergantung provinsi asal/tujuan).',
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context).colorScheme.primary,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: _buildCategoryCard(
                      icon: Icons.mail_outline,
                      label: 'Dokumen',
                      subtitle: 'Surat, dokumen, amplop, paket kecil',
                      category: OrderModel.barangCategoryDokumen,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildCategoryCard(
                      icon: Icons.inventory_2_outlined,
                      label: 'Kargo',
                      subtitle: 'Paket besar, barang umum',
                      category: OrderModel.barangCategoryKargo,
                    ),
                  ),
                ],
              ),
              if (isKargo) ...[
                const SizedBox(height: 24),
                Text(
                  'Detail barang (kargo)',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _namaController,
                  autocorrect: false,
                  enableSuggestions: false,
                  decoration: InputDecoration(
                    labelText: 'Nama/jenis barang *',
                    hintText: 'Contoh: Sepatu, Elektronik',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppTheme.radiusSm)),
                  ),
                  textCapitalization: TextCapitalization.sentences,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _beratController,
                  autocorrect: false,
                  enableSuggestions: false,
                  decoration: InputDecoration(
                    labelText: 'Berat (kg) *',
                    hintText: 'Contoh: 2.5',
                    helperText: 'Min 0,1 kg, max 100 kg',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppTheme.radiusSm)),
                  ),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _panjangController,
                        autocorrect: false,
                        enableSuggestions: false,
                        decoration: InputDecoration(
                          labelText: 'Panjang (cm) *',
                          hintText: '30',
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppTheme.radiusSm)),
                        ),
                        keyboardType: TextInputType.number,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: _lebarController,
                        autocorrect: false,
                        enableSuggestions: false,
                        decoration: InputDecoration(
                          labelText: 'Lebar (cm) *',
                          hintText: '20',
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppTheme.radiusSm)),
                        ),
                        keyboardType: TextInputType.number,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: _tinggiController,
                        autocorrect: false,
                        enableSuggestions: false,
                        decoration: InputDecoration(
                          labelText: 'Tinggi (cm)',
                          hintText: '15',
                          helperText: 'Opsional, max 300',
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppTheme.radiusSm)),
                        ),
                        keyboardType: TextInputType.number,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  'Foto barang (opsional)',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    if (_barangFotoFile != null) ...[
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.file(
                          _barangFotoFile!,
                          width: 80,
                          height: 80,
                          fit: BoxFit.cover,
                        ),
                      ),
                      const SizedBox(width: 12),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => setState(() => _barangFotoFile = null),
                        tooltip: 'Hapus foto',
                      ),
                    ] else
                      OutlinedButton.icon(
                        onPressed: _isUploading ? null : _pickImage,
                        icon: const Icon(Icons.add_photo_alternate_outlined, size: 20),
                        label: const Text('Tambah foto'),
                      ),
                  ],
                ),
              ],
              const SizedBox(height: 24),
              Row(
                children: [
                  if (widget.onCancel != null)
                    OutlinedButton(
                      onPressed: widget.onCancel,
                      child: const Text('Batal'),
                    ),
                  if (widget.onCancel != null) const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: _selectedCategory == null || _isUploading
                          ? null
                          : () => _submit(),
                      child: _isUploading
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Text(
                              isKargo ? 'Lanjut ke Tautkan Penerima' : 'Lanjut',
                            ),
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

  Widget _buildCategoryCard({
    required IconData icon,
    required String label,
    required String subtitle,
    required String category,
  }) {
    final selected = _selectedCategory == category;
    return InkWell(
      onTap: () => setState(() => _selectedCategory = category),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: selected
              ? Theme.of(context).colorScheme.primaryContainer
              : Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected
                ? Theme.of(context).colorScheme.primary
                : Colors.transparent,
            width: 2,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 32, color: Theme.of(context).colorScheme.primary),
            const SizedBox(height: 8),
            Text(
              label,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: TextStyle(
                fontSize: 11,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}
