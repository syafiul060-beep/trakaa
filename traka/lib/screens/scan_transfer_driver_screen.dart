import 'package:flutter/material.dart';

import '../services/location_service.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../services/driver_transfer_service.dart';

/// Layar scan barcode Oper Driver oleh driver kedua.
/// Setelah scan berhasil: langsung selesaikan transfer (tidak perlu password).
class ScanTransferDriverScreen extends StatefulWidget {
  const ScanTransferDriverScreen({super.key});

  @override
  State<ScanTransferDriverScreen> createState() =>
      _ScanTransferDriverScreenState();
}

class _ScanTransferDriverScreenState extends State<ScanTransferDriverScreen> {
  final MobileScannerController _controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.normal,
    facing: CameraFacing.back,
    torchEnabled: false,
  );
  bool _scanned = false;
  bool _processing = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _onDetect(BarcodeCapture capture) async {
    if (_scanned || _processing) return;
    final barcode = capture.barcodes.firstOrNull;
    final raw = barcode?.rawValue;
    if (raw == null || raw.isEmpty) return;

    final (transferId, parseError) =
        DriverTransferService.parseTransferBarcodePayload(raw);
    if (transferId == null) return;

    setState(() {
      _scanned = true;
      _processing = true;
    });

    double? lat;
    double? lng;
    try {
      final result = await LocationService.getCurrentPositionWithMockCheck(
        forTracking: true,
      );
      if (!result.isFakeGpsDetected && result.position != null) {
        lat = result.position!.latitude;
        lng = result.position!.longitude;
      }
    } catch (_) {}

    final (success, error) = await DriverTransferService.applyDriverScanTransfer(
      raw,
      toDriverLat: lat,
      toDriverLng: lng,
    );

    if (!mounted) return;
    setState(() => _processing = false);

    if (success) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Oper berhasil. Pesanan telah dipindah ke Anda.'),
          backgroundColor: Colors.green,
          behavior: SnackBarBehavior.floating,
        ),
      );
      Navigator.of(context).pop(true);
    } else {
      setState(() => _scanned = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error ?? 'Oper gagal'),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Scan barcode Oper Driver'),
        backgroundColor: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.87),
        foregroundColor: Colors.white,
      ),
      body: _scanned && _processing
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CircularProgressIndicator(),
                  const SizedBox(height: 16),
                  Text(
                    'Memproses oper...',
                    style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
                  ),
                ],
              ),
            )
          : Stack(
              children: [
                MobileScanner(controller: _controller, onDetect: _onDetect),
                if (_processing)
                  Container(
                    color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.54),
                    child: const Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          CircularProgressIndicator(color: Colors.white),
                          SizedBox(height: 16),
                          Text(
                            'Memverifikasi...',
                            style: TextStyle(color: Colors.white, fontSize: 16),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
    );
  }

}
