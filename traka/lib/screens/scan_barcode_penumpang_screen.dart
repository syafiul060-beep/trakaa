import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../services/fake_gps_overlay_service.dart';
import '../services/ferry_distance_service.dart';
import '../services/location_service.dart';
import '../services/order_service.dart';
import '../utils/app_logger.dart' show log, logError;
import '../widgets/traka_l10n_scope.dart';
import '../theme/traka_snackbar.dart';

/// Layar scan barcode driver oleh penumpang.
/// Scan 1 (PICKUP): konfirmasi jemput → pop(_kScanResultPickup).
/// Scan 2 (COMPLETE): selesai perjalanan → pop(orderId).
/// Receiver scan (kirim barang): terima barang → pop(_kScanResultReceiver).
class ScanBarcodePenumpangScreen extends StatefulWidget {
  const ScanBarcodePenumpangScreen({super.key});

  /// Return value saat scan PICKUP (penjemputan terkonfirmasi).
  static const String resultPickup = '__scan_pickup__';
  /// Return value saat scan receiver (barang diterima).
  static const String resultReceiver = '__scan_receiver__';

  @override
  State<ScanBarcodePenumpangScreen> createState() =>
      _ScanBarcodePenumpangScreenState();
}

class _ScanBarcodePenumpangScreenState
    extends State<ScanBarcodePenumpangScreen> {
  final MobileScannerController _controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.normal,
    facing: CameraFacing.back,
    torchEnabled: false,
  );
  bool _scanned = false;
  bool _processing = false;
  final TextEditingController _ferryController = TextEditingController();

  /// Rate limit: max 5 percobaan gagal dalam 1 menit.
  static const int _maxFailedAttempts = 5;
  static const Duration _rateLimitWindow = Duration(minutes: 1);
  final List<DateTime> _failedAttemptTimes = [];

  @override
  void dispose() {
    _ferryController.dispose();
    _controller.dispose();
    super.dispose();
  }

  /// [estimatedFerryKm] = estimasi otomatis jika beda pulau; null jika sama pulau.
  Future<double?> _showFerryDialog(
    BuildContext context, {
    double? estimatedFerryKm,
  }) async {
    _ferryController.clear();
    if (estimatedFerryKm != null) {
      _ferryController.text = estimatedFerryKm.round().toString();
    }
    return showDialog<double>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Rute kapal laut'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (estimatedFerryKm != null) ...[
              Text(
                'Estimasi jarak kapal: ${estimatedFerryKm.round()} km',
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'Gunakan estimasi atau ubah jika Anda tahu jarak yang lebih akurat.',
                style: TextStyle(fontSize: 13),
              ),
            ] else ...[
              const Text(
                'Jika rute melewati kapal laut, masukkan jarak kapal (km) untuk dikurangi dari total jarak.',
                style: TextStyle(fontSize: 14),
              ),
            ],
            const SizedBox(height: 16),
            TextField(
              controller: _ferryController,
              autocorrect: false,
              enableSuggestions: false,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: 'Jarak kapal (km)',
                hintText: estimatedFerryKm != null
                    ? 'Ubah jika perlu'
                    : 'Kosongkan jika tidak naik kapal',
                border: const OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(null),
            child: const Text('Lewati'),
          ),
          if (estimatedFerryKm != null)
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(estimatedFerryKm),
              child: const Text('Gunakan'),
            ),
          FilledButton(
            onPressed: () {
              final s = _ferryController.text.trim();
              if (s.isEmpty) {
                Navigator.of(ctx).pop(estimatedFerryKm);
                return;
              }
              final v = double.tryParse(s.replaceAll(',', '.'));
              Navigator.of(ctx).pop(v != null && v >= 0 ? v : estimatedFerryKm);
            },
            child: Text(estimatedFerryKm != null ? 'Ubah' : 'Lanjutkan'),
          ),
        ],
      ),
    );
  }

  bool _isRateLimited() {
    final now = DateTime.now();
    _failedAttemptTimes.removeWhere((t) => now.difference(t) > _rateLimitWindow);
    return _failedAttemptTimes.length >= _maxFailedAttempts;
  }

  Future<void> _onDetect(BarcodeCapture capture) async {
    if (_scanned || _processing) return;
    if (_isRateLimited()) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          TrakaSnackBar.warning(context, Text(TrakaL10n.of(context).tooManyAttempts), behavior: SnackBarBehavior.floating),
        );
      }
      return;
    }
    final barcode = capture.barcodes.firstOrNull;
    final raw = barcode?.rawValue;
    if (raw == null || raw.isEmpty) return;

    setState(() => _processing = true);

    double? dropLat;
    double? dropLng;
    try {
      final result = await LocationService.getCurrentPositionWithMockCheck();
      if (result.isFakeGpsDetected) {
        if (mounted) {
          setState(() => _processing = false);
          FakeGpsOverlayService.showOverlay();
        }
        return;
      }
      final pos = result.position;
      if (pos != null) {
        dropLat = pos.latitude;
        dropLng = pos.longitude;
      }
    } catch (e, st) {
      logError('ScanBarcodePenumpangScreen._onDetect getCurrentPosition', e, st);
    }

    // Parse fase: PICKUP = penjemputan, COMPLETE = selesai
    final (_, fase, _) = OrderService.parseDriverBarcodePayloadWithPhase(raw);
    if (kDebugMode) {
      log('ScanBarcodePenumpang: raw=${raw.length > 40 ? "${raw.substring(0, 40)}..." : raw}, fase=$fase');
    }

    bool success = false;
    String? error;
    String? completedOrderId;
    bool isReceiverScan = false;

    if (fase == 'PICKUP') {
      // Scan barcode penjemputan (penumpang/pengirim scan saat dijemput)
      final (s, e, oid) = await OrderService.applyPassengerScanDriverPickup(
        raw,
        pickupLat: dropLat,
        pickupLng: dropLng,
      );
      success = s;
      error = e;
      completedOrderId = oid;
    } else {
      // Scan barcode selesai (penumpang scan saat sampai tujuan)
      // Hybrid: estimasi jarak kapal otomatis jika beda pulau, atau dialog manual
      double? ferryKm;
      final (orderId, _, _) = OrderService.parseDriverBarcodePayloadWithPhase(raw);
      double? estimatedFerry;
      if (orderId != null && dropLat != null && dropLng != null) {
        final order = await OrderService.getOrderById(orderId);
        final pickLat = order?.pickupLat ?? order?.passengerLat ?? order?.originLat;
        final pickLng = order?.pickupLng ?? order?.passengerLng ?? order?.originLng;
        if (pickLat != null && pickLng != null) {
          estimatedFerry = await FerryDistanceService.getEstimatedFerryKm(
            originLat: pickLat,
            originLng: pickLng,
            destLat: dropLat,
            destLng: dropLng,
          );
        }
      }
      if (estimatedFerry != null && mounted) {
        ferryKm = await _showFerryDialog(context, estimatedFerryKm: estimatedFerry);
      }
      // Jika sama pulau (estimatedFerry == null): lewati dialog, ferryKm tetap null (= 0)
      var (s, e, oid) = await OrderService.applyPassengerScanDriver(
        raw,
        dropLat: dropLat,
        dropLng: dropLng,
        ferryDistanceKm: ferryKm,
      );
      if (!s && e != null && e.contains('bukan untuk pesanan')) {
        // Kirim barang: coba sebagai penerima
        final (recS, recE, recOid) = await OrderService.applyReceiverScanDriver(
          raw,
          dropLat: dropLat,
          dropLng: dropLng,
          ferryDistanceKm: ferryKm,
        );
        if (recS) {
          success = true;
          isReceiverScan = true;
          completedOrderId = recOid;
        } else {
          error = recE;
        }
      } else {
        success = s;
        error = e;
        completedOrderId = oid;
      }
    }

    if (!mounted) return;
    if (success) {
      _scanned = true;
      HapticFeedback.mediumImpact();
      final isPickup = fase == 'PICKUP';
      String msg;
      if (isPickup) {
        msg = 'Penjemputan terkonfirmasi. Saat sampai tujuan, scan barcode selesai.';
      } else if (isReceiverScan) {
        msg = 'Barang diterima. Terima kasih.';
      } else {
        msg = 'Perjalanan selesai. Terima kasih.';
      }
      ScaffoldMessenger.of(context).showSnackBar(
        TrakaSnackBar.success(context, Text(msg), behavior: SnackBarBehavior.floating),
      );
      // Pickup: pop(resultPickup). Receiver: pop(resultReceiver). Complete: pop(orderId) untuk rating.
      final result = isPickup
          ? ScanBarcodePenumpangScreen.resultPickup
          : (isReceiverScan
              ? ScanBarcodePenumpangScreen.resultReceiver
              : completedOrderId);
      if (kDebugMode) {
        log('ScanBarcodePenumpang: success, result=${isPickup ? "pickup" : (isReceiverScan ? "receiver" : "complete")}');
      }
      Navigator.of(context).pop(result);
    } else {
      _failedAttemptTimes.add(DateTime.now());
      setState(() => _processing = false);
      ScaffoldMessenger.of(context).showSnackBar(
        TrakaSnackBar.error(context, Text(error ?? TrakaL10n.of(context).scanFailed), behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 4)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Scan barcode driver'),
        backgroundColor: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.87),
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.flash_on),
            tooltip: 'Senter',
            onPressed: () => _controller.toggleTorch(),
          ),
        ],
      ),
      body: Stack(
        children: [
          MobileScanner(controller: _controller, onDetect: _onDetect),
          if (_processing)
            Container(
              color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.54),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const CircularProgressIndicator(color: Colors.white),
                    const SizedBox(height: 16),
                    Text(
                      'Memverifikasi...',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Mohon tunggu, jangan tutup kamera',
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          Positioned(
            left: 16,
            right: 16,
            bottom: 28,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Travel: PICKUP (jemput) → COMPLETE (tujuan).',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    shadows: [
                      Shadow(color: Colors.black.withValues(alpha: 0.85), blurRadius: 4),
                      Shadow(color: Colors.black.withValues(alpha: 0.85), offset: Offset(1, 1)),
                    ],
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Kirim barang: pengirim scan PICKUP; penerima scan saat terima.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.95),
                    fontSize: 12,
                    height: 1.3,
                    shadows: [
                      Shadow(color: Colors.black.withValues(alpha: 0.85), blurRadius: 4),
                      Shadow(color: Colors.black.withValues(alpha: 0.85), offset: Offset(1, 1)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
