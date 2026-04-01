import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_contacts/flutter_contacts.dart';

import '../services/driver_contact_service.dart';
import '../theme/app_theme.dart';
import 'traka_bottom_sheet.dart';
import 'traka_empty_state.dart';

class _ContactPhoneItem {
  final Contact contact;
  final String phone;
  final String displayName;
  _ContactPhoneItem({
    required this.contact,
    required this.phone,
    required this.displayName,
  });
}

/// Modal picker kontak untuk pilih driver kedua (Oper Driver).
/// Hanya kontak yang terdaftar sebagai driver yang bisa dipilih.
void showDriverContactPicker({
  required BuildContext context,
  required void Function(String phone, Map<String, dynamic>? driverData) onSelect,
}) {
  showTrakaModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => _DriverContactPickerSheet(
      onSelect: (phone, data) {
        Navigator.of(ctx).pop();
        onSelect(phone, data);
      },
    ),
  );
}

class _DriverContactPickerSheet extends StatefulWidget {
  final void Function(String phone, Map<String, dynamic>? driverData) onSelect;

  const _DriverContactPickerSheet({required this.onSelect});

  @override
  State<_DriverContactPickerSheet> createState() => _DriverContactPickerSheetState();
}

class _DriverContactPickerSheetState extends State<_DriverContactPickerSheet> {
  List<_ContactPhoneItem> _items = [];
  Map<String, Map<String, dynamic>> _registered = {};
  bool _loading = true;
  String? _error;
  final _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<_ContactPhoneItem> get _filteredItems {
    final q = _searchController.text.trim().toLowerCase();
    if (q.isEmpty) return _items;
    return _items.where((i) => i.displayName.toLowerCase().contains(q)).toList();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final status =
          await FlutterContacts.permissions.request(PermissionType.read);
      if (status != PermissionStatus.granted &&
          status != PermissionStatus.limited) {
        if (mounted) {
          setState(() {
            _loading = false;
            _error = 'Izin akses kontak diperlukan. Aktifkan di Pengaturan aplikasi.';
          });
        }
        return;
      }
      final contacts = await FlutterContacts.getAll(
        properties: {ContactProperty.phone, ContactProperty.photoThumbnail},
      );
      if (!mounted) return;

      final items = <_ContactPhoneItem>[];
      final allPhones = <String>[];

      for (final c in contacts) {
        final phones = (c.phones)
            .map((p) => p.number)
            .where((n) => n.trim().isNotEmpty)
            .toList();
        if (phones.isEmpty) continue;
        final dn = c.displayName ?? '';
        final name = dn.trim().isEmpty ? 'Tanpa nama' : dn;
        for (final p in phones) {
          items.add(_ContactPhoneItem(contact: c, phone: p, displayName: name));
          allPhones.add(p);
        }
      }

      final registered = <String, Map<String, dynamic>>{};
      for (var i = 0; i < allPhones.length; i += 50) {
        final batch = allPhones.skip(i).take(50).toList();
        final result = await DriverContactService.checkRegisteredDrivers(batch);
        for (final e in result.entries) {
          final norm = DriverContactService.normalizePhone(e.key);
          if (norm != null) registered[norm] = e.value;
        }
      }

      if (!mounted) return;
      setState(() {
        _items = items;
        _registered = registered;
        _loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'Gagal memuat kontak. Pastikan izin kontak diaktifkan.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.85,
      ),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: EdgeInsets.only(bottom: bottomInset + 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 12),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.outline,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Pilih driver kedua dari kontak',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
          Text(
            'Hanya kontak yang terdaftar sebagai driver',
            style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _searchController,
            autocorrect: false,
            enableSuggestions: false,
            decoration: InputDecoration(
              hintText: 'Cari nama...',
              prefixIcon: const Icon(Icons.search),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 12),
          Flexible(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? TrakaEmptyState(
                        icon: Icons.error_outline,
                        title: _error!,
                        action: TextButton(
                          onPressed: _load,
                          child: const Text('Coba lagi'),
                        ),
                      )
                    : _items.isEmpty
                        ? const TrakaEmptyState(
                            icon: Icons.phone_disabled_outlined,
                            title: 'Tidak ada kontak dengan nomor HP.',
                            subtitle:
                                'Pastikan kontak di ponsel memiliki nomor telepon.',
                          )
                        : _filteredItems.isEmpty
                            ? const TrakaEmptyState(
                                icon: Icons.search_off,
                                title:
                                    'Tidak ada kontak yang cocok dengan pencarian.',
                              )
                            : ListView.builder(
                            shrinkWrap: true,
                            itemCount: _filteredItems.length,
                            itemBuilder: (context, i) {
                              final item = _filteredItems[i];
                              final norm = DriverContactService.normalizePhone(item.phone) ?? '';
                              final reg = _registered[norm];
                              final isDriver = reg != null && reg['uid'] != null;

                              return ListTile(
                                leading: _buildAvatar(item.contact, reg),
                                title: Text(item.displayName),
                                subtitle: Text(item.phone, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
                                trailing: isDriver
                                    ? Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                        decoration: BoxDecoration(
                                          color: AppTheme.primary.withValues(alpha: 0.1),
                                          borderRadius: BorderRadius.circular(8),
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(Icons.directions_car, size: 18, color: AppTheme.primary),
                                            const SizedBox(width: 4),
                                            Text('Driver', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.primary)),
                                          ],
                                        ),
                                      )
                                    : null,
                                onTap: isDriver
                                    ? () => widget.onSelect(
                                          item.phone,
                                          {
                                            'uid': reg['uid'],
                                            'displayName': reg['displayName'] ?? item.displayName,
                                            'photoUrl': reg['photoUrl'],
                                            'email': reg['email'],
                                          },
                                        )
                                    : null,
                              );
                            },
                          ),
          ),
        ],
      ),
    );
  }

  Widget _buildAvatar(Contact c, Map<String, dynamic>? reg) {
    final photoUrl = reg?['photoUrl'] as String?;
    final photoBytes = c.photo?.thumbnail ?? c.photo?.fullSize;

    if (photoUrl != null && photoUrl.isNotEmpty) {
      try {
        return CircleAvatar(
          radius: 24,
          backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
          backgroundImage: CachedNetworkImageProvider(photoUrl),
        );
      } catch (_) {
        // Fallback jika foto gagal dimuat
      }
    }
    if (photoBytes != null && photoBytes.isNotEmpty) {
      try {
        return CircleAvatar(
          radius: 24,
          backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
          backgroundImage: MemoryImage(photoBytes),
        );
      } catch (_) {
        // Fallback jika foto kontak rusak/tidak valid
      }
    }
    return CircleAvatar(
      radius: 24,
      backgroundColor: AppTheme.primary.withValues(alpha: 0.2),
      child: Text(
        ((c.displayName ?? '').trim().isNotEmpty
                ? (c.displayName ?? '').trim()[0]
                : '?')
            .toUpperCase(),
        style: TextStyle(color: AppTheme.primary, fontWeight: FontWeight.w600, fontSize: 18),
      ),
    );
  }
}
