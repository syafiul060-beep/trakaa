import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../l10n/app_localizations.dart';
import '../models/order_model.dart';
import '../services/active_drivers_service.dart';
import '../services/app_analytics_service.dart';
import '../services/lacak_barang_service.dart';
import '../services/locale_service.dart';
import '../services/order_service.dart';
import '../services/passenger_first_chat_message.dart';
import 'estimate_loading_dialog.dart';
import 'receiver_contact_picker.dart';
import 'traka_l10n_scope.dart';

/// Bottom sheet: tautkan penerima kirim barang (cari email/telp → tampil foto+nama → Iya → create order).
class KirimBarangLinkReceiverSheet extends StatefulWidget {
  final ActiveDriverRoute driver;
  final String asal;
  final String tujuan;
  final double? originLat;
  final double? originLng;
  final double? destLat;
  final double? destLng;
  final String? barangCategory;
  final String? barangNama;
  final double? barangBeratKg;
  final double? barangPanjangCm;
  final double? barangLebarCm;
  final double? barangTinggiCm;
  final String? barangFotoUrl;
  final void Function(String orderId, String message, [String? barangFotoUrl])
      onOrderCreated;
  final void Function(String message) onError;
  /// Penumpang memilih lewati cek duplikat pra-sepakat (satu thread per driver).
  final bool bypassDuplicatePendingKirimBarang;

  const KirimBarangLinkReceiverSheet({
    super.key,
    required this.driver,
    required this.asal,
    required this.tujuan,
    this.originLat,
    this.originLng,
    this.destLat,
    this.destLng,
    this.barangCategory,
    this.barangNama,
    this.barangBeratKg,
    this.barangPanjangCm,
    this.barangLebarCm,
    this.barangTinggiCm,
    this.barangFotoUrl,
    required this.onOrderCreated,
    required this.onError,
    this.bypassDuplicatePendingKirimBarang = false,
  });

  @override
  State<KirimBarangLinkReceiverSheet> createState() =>
      _KirimBarangLinkReceiverSheetState();
}

class _KirimBarangLinkReceiverSheetState
    extends State<KirimBarangLinkReceiverSheet> {
  final _controller = TextEditingController();
  bool _loading = false;
  Map<String, dynamic>? _receiver; // {uid, displayName, photoUrl}
  String? _notFound;
  List<Map<String, dynamic>> _recentReceivers = [];
  String? _estimasiLacakBarang; // "Rp X" atau "Rp 10.000 - Rp 25.000"

  @override
  void initState() {
    super.initState();
    _loadRecentReceivers();
    _loadEstimasiLacakBarang();
  }

  Future<void> _loadEstimasiLacakBarang() async {
    final oLat = widget.originLat;
    final oLng = widget.originLng;
    final dLat = widget.destLat;
    final dLng = widget.destLng;
    if (oLat != null && oLng != null && dLat != null && dLng != null) {
      try {
        final (_, fee) = await LacakBarangService.getTierAndFee(
          originLat: oLat,
          originLng: oLng,
          destLat: dLat,
          destLng: dLng,
        );
        if (mounted) {
          setState(() => _estimasiLacakBarang =
              'Rp ${fee.toString().replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]}.')}');
        }
      } catch (_) {
        if (mounted) setState(() => _estimasiLacakBarang = 'Rp 10.000 - Rp 25.000');
      }
    } else {
      if (mounted) setState(() => _estimasiLacakBarang = 'Rp 10.000 - Rp 25.000');
    }
  }

  Future<void> _loadRecentReceivers() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final list = await OrderService.getRecentReceivers(user.uid);
    if (mounted) setState(() => _recentReceivers = list);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _selectReceiver(Map<String, dynamic> receiver) {
    setState(() {
      _receiver = receiver;
      _notFound = null;
    });
  }

  Future<void> _cari() async {
    final input = _controller.text.trim();
    if (input.isEmpty) {
      widget.onError('Masukkan no. telepon penerima.');
      return;
    }
    setState(() {
      _loading = true;
      _receiver = null;
      _notFound = null;
    });
    final result = await OrderService.findUserByEmailOrPhone(input);
    if (!mounted) return;
    setState(() {
      _loading = false;
      _receiver = result;
      _notFound = result == null ? 'User tidak ditemukan.' : null;
    });
  }

  Future<void> _kirimKeDriver() async {
    final receiver = _receiver;
    if (receiver == null) return;
    final uid = receiver['uid'] as String?;
    if (uid == null) return;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    if (uid == user.uid) {
      widget.onError('Penerima tidak boleh sama dengan pengirim.');
      return;
    }
    // Validasi ulang: pastikan penerima masih terdaftar
    try {
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .get();
      if (!userDoc.exists) {
        widget.onError('Penerima tidak ditemukan. Pilih ulang dari kontak.');
        setState(() => _receiver = null);
        return;
      }
    } catch (_) {
      widget.onError('Gagal memverifikasi penerima. Coba lagi.');
      return;
    }
    if (!widget.bypassDuplicatePendingKirimBarang) {
      final pendingKb =
          await OrderService.getPassengerPendingKirimBarangWithDriver(
        user.uid,
        widget.driver.driverUid,
      );
      if (!mounted) return;
      if (pendingKb != null) {
        widget.onError(
          TrakaL10n.of(context).passengerPendingKirimBarangDuplicateShort,
        );
        return;
      }
    }
    setState(() => _loading = true);
    String? passengerName;
    String? passengerPhotoUrl;
    String? passengerAppLocale;
    try {
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      if (userDoc.exists && userDoc.data() != null) {
        final d = userDoc.data()!;
        passengerName = d['displayName'] as String?;
        passengerPhotoUrl = d['photoUrl'] as String?;
        passengerAppLocale = (d['appLocale'] as String?) ??
            (LocaleService.current == AppLocale.id ? 'id' : 'en');
      } else {
        passengerAppLocale = LocaleService.current == AppLocale.id ? 'id' : 'en';
      }
    } catch (_) {
      passengerAppLocale = LocaleService.current == AppLocale.id ? 'id' : 'en';
    }
    passengerName ??= user.email ?? 'Penumpang';
    final receiverName = (receiver['displayName'] as String?) ?? 'Penerima';
    final receiverPhotoUrl = receiver['photoUrl'] as String?;
    final orderId = await OrderService.createOrder(
      passengerUid: user.uid,
      driverUid: widget.driver.driverUid,
      routeJourneyNumber: widget.driver.routeJourneyNumber,
      passengerName: passengerName,
      passengerPhotoUrl: passengerPhotoUrl,
      passengerAppLocale: passengerAppLocale,
      originText: widget.asal,
      destText: widget.tujuan,
      originLat: widget.originLat,
      originLng: widget.originLng,
      destLat: widget.destLat,
      destLng: widget.destLng,
      orderType: OrderModel.typeKirimBarang,
      receiverUid: uid,
      receiverName: receiverName,
      receiverPhotoUrl: receiverPhotoUrl,
      barangCategory: widget.barangCategory ?? OrderModel.barangCategoryKargo,
      barangNama: widget.barangNama,
      barangBeratKg: widget.barangBeratKg,
      barangPanjangCm: widget.barangPanjangCm,
      barangLebarCm: widget.barangLebarCm,
      barangTinggiCm: widget.barangTinggiCm,
      barangFotoUrl: widget.barangFotoUrl,
      bypassDuplicatePendingKirimBarang:
          widget.bypassDuplicatePendingKirimBarang,
    );
    if (!mounted) return;
    AppAnalyticsService.logOrderCreated(
      orderType: OrderModel.typeKirimBarang,
      success: orderId != null,
    );
    if (orderId == null) {
      setState(() => _loading = false);
      widget.onError(TrakaL10n.of(context).failedToCreateOrder);
      return;
    }
    setState(() => _loading = false);

    final driverName = widget.driver.driverName ?? 'Driver';
    final jenisLabel = widget.barangCategory == OrderModel.barangCategoryDokumen
        ? 'Dokumen (surat, amplop, paket kecil)'
        : 'Kargo';
    String barangDetail = '';
    if (widget.barangCategory == OrderModel.barangCategoryKargo &&
        widget.barangNama != null &&
        widget.barangNama!.trim().isNotEmpty) {
      final parts = <String>[widget.barangNama!.trim()];
      if (widget.barangBeratKg != null && widget.barangBeratKg! > 0) {
        parts.add('${widget.barangBeratKg!.toStringAsFixed(1)} kg');
      }
      if (widget.barangPanjangCm != null &&
          widget.barangLebarCm != null &&
          widget.barangPanjangCm! > 0 &&
          widget.barangLebarCm! > 0) {
        final dim = widget.barangTinggiCm != null && widget.barangTinggiCm! > 0
            ? '${widget.barangPanjangCm!.toInt()}×${widget.barangLebarCm!.toInt()}×${widget.barangTinggiCm!.toInt()} cm'
            : '${widget.barangPanjangCm!.toInt()}×${widget.barangLebarCm!.toInt()} cm';
        parts.add(dim);
      }
      barangDetail = '\nBarang: ${parts.join(' • ')}\n';
    }
    final l10n = TrakaL10n.of(context);
    final oLat = widget.originLat;
    final oLng = widget.originLng;
    final dLat = widget.destLat;
    final dLng = widget.destLng;
    String? jarakKontribusiLines;
    if (oLat != null && oLng != null && dLat != null && dLng != null) {
      jarakKontribusiLines = await runWithEstimateLoading<String?>(
        context,
        l10n,
        () async {
          final preview = await OrderService.computeJarakKontribusiPreview(
            originLat: oLat,
            originLng: oLng,
            destLat: dLat,
            destLng: dLng,
            orderType: OrderModel.typeKirimBarang,
            barangCategory:
                widget.barangCategory ?? OrderModel.barangCategoryKargo,
          );
          if (preview != null) {
            return PassengerFirstChatMessage.formatJarakKontribusiLines(
                l10n, preview);
          }
          return l10n.chatPreviewEstimateUnavailable;
        },
      );
    }
    if (!mounted) return;
    final message = PassengerFirstChatMessage.kirimBarang(
      driverName: driverName,
      isScheduled: false,
      jenisLabel: jenisLabel,
      barangDetailSuffix: barangDetail,
      receiverName: receiverName,
      asal: widget.asal,
      tujuan: widget.tujuan,
      jarakKontribusiLines: jarakKontribusiLines,
    );
    widget.onOrderCreated(orderId, message, widget.barangFotoUrl);
  }

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
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
                'Kirim Barang – Tautkan Penerima',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Masukkan no. telepon penerima (harus terdaftar di Traka).',
                style: TextStyle(
                    fontSize: 13,
                    color: Theme.of(context).colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: 6),
              Text(
                _estimasiLacakBarang != null
                    ? 'Estimasi Lacak Barang: $_estimasiLacakBarang (sesuai jarak pengirim–penerima).'
                    : 'Lacak barang: Rp 10.000 - Rp 25.000 (sesuai jarak pengirim–penerima).',
                style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.onSurfaceVariant),
              ),
              if (_recentReceivers.isNotEmpty) ...[
                const SizedBox(height: 16),
                Text(
                  'Riwayat penerima',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  height: 56,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: _recentReceivers.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 8),
                    itemBuilder: (context, i) {
                      final r = _recentReceivers[i];
                      final name = (r['displayName'] as String?) ?? 'Penerima';
                      final photoUrl = r['photoUrl'] as String?;
                      final selected = _receiver?['uid'] == r['uid'];
                      return Material(
                        color: selected
                            ? Theme.of(context).colorScheme.primaryContainer
                            : Theme.of(context)
                                .colorScheme
                                .surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(12),
                        child: InkWell(
                          onTap: () => _selectReceiver(r),
                          borderRadius: BorderRadius.circular(12),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 8),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                CircleAvatar(
                                  radius: 20,
                                  backgroundColor:
                                      Theme.of(context).colorScheme.surface,
                                  backgroundImage:
                                      photoUrl != null && photoUrl.isNotEmpty
                                          ? CachedNetworkImageProvider(
                                              photoUrl)
                                          : null,
                                  child: photoUrl == null || photoUrl.isEmpty
                                      ? Icon(Icons.person,
                                          size: 20,
                                          color: Theme.of(context)
                                              .colorScheme
                                              .onSurfaceVariant)
                                      : null,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  name,
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w500,
                                    color:
                                        Theme.of(context).colorScheme.onSurface,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                  maxLines: 1,
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
              const SizedBox(height: 16),
              TextField(
                controller: _controller,
                decoration: InputDecoration(
                  labelText: 'No. telepon',
                  border: const OutlineInputBorder(),
                  hintText: '08123456789',
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.contacts_outlined),
                    tooltip: 'Buka kontak HP',
                    onPressed: () {
                      showReceiverContactPicker(
                        context: context,
                        onSelect: (phone, receiverData) {
                          _controller.text = phone;
                          setState(() {
                            _receiver = receiverData;
                            _notFound = receiverData == null
                                ? 'Kontak belum terdaftar di Traka.'
                                : null;
                          });
                        },
                      );
                    },
                  ),
                ),
                keyboardType: TextInputType.phone,
                onSubmitted: (_) => _cari(),
              ),
              const SizedBox(height: 12),
              if (_notFound != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    _notFound!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                      fontSize: 13,
                    ),
                  ),
                ),
              if (_receiver != null) ...[
                Row(
                  children: [
                    CircleAvatar(
                      radius: 28,
                      backgroundColor: Theme.of(context)
                          .colorScheme
                          .surfaceContainerHighest,
                      backgroundImage:
                          (_receiver!['photoUrl'] as String?) != null &&
                                  (_receiver!['photoUrl'] as String).isNotEmpty
                              ? CachedNetworkImageProvider(
                                  _receiver!['photoUrl'] as String,
                                )
                              : null,
                      child:
                          (_receiver!['photoUrl'] as String?) == null ||
                                  (_receiver!['photoUrl'] as String).isEmpty
                              ? Icon(Icons.person,
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurfaceVariant)
                              : null,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        (_receiver!['displayName'] as String?) ?? 'Penerima',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Text(
                  'Penerima akan dapat notifikasi dan harus setuju. Setelah setuju, pesanan masuk ke driver.',
                  style: TextStyle(
                      fontSize: 12,
                      color:
                          Theme.of(context).colorScheme.onSurfaceVariant),
                ),
                const SizedBox(height: 16),
              ],
              FilledButton(
                onPressed: _loading
                    ? null
                    : () async {
                        if (_receiver != null) {
                          await _kirimKeDriver();
                        } else {
                          await _cari();
                        }
                      },
                child: _loading
                    ? const SizedBox(
                        height: 24,
                        width: 24,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(
                        _receiver != null ? 'Iya, kirim ke driver' : 'Cari'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
