import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Batas RAM minimal (MB) agar Traka berjalan optimal.
const int _minRamMb = 6144; // 6 GB

const _prefKey = 'low_ram_warning_shown';

/// Layanan peringatan RAM rendah. Tampilkan dialog sekali saat user masuk beranda.
class LowRamWarningService {
  static final DeviceInfoPlugin _deviceInfo = DeviceInfoPlugin();

  /// Reset flag agar peringatan bisa tampil lagi (dari Pengaturan).
  static Future<void> resetWarningFlag() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefKey, false);
  }

  /// Tampilkan dialog peringatan RAM jika < 6GB. Dipanggil manual dari Pengaturan.
  static Future<void> showWarningIfLowRam(BuildContext context) async {
    if (!context.mounted) return;
    final ramMb = await _getDeviceRamMb();
    if (ramMb == null) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Informasi RAM tidak tersedia di perangkat ini.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return;
    }
    if (ramMb >= _minRamMb) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Perangkat Anda memiliki RAM cukup (min. 6 GB) untuk pengalaman optimal.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return;
    }
    if (!context.mounted) return;
    await _showDialog(context, ramMb);
  }

  /// Cek RAM dan tampilkan dialog jika < 6GB & belum pernah ditampilkan.
  /// Panggil dari initState PenumpangScreen atau DriverScreen.
  static Future<void> checkAndShowIfNeeded(BuildContext context) async {
    if (!context.mounted) return;
    final ramMb = await _getDeviceRamMb();
    if (ramMb == null || ramMb >= _minRamMb) return;

    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_prefKey) == true) return;

    if (!context.mounted) return;
    await _showDialog(context, ramMb);

    if (context.mounted) {
      await prefs.setBool(_prefKey, true);
    }
  }

  static Future<int?> _getDeviceRamMb() async {
    try {
      if (Platform.isAndroid) {
        final android = await _deviceInfo.androidInfo;
        return android.physicalRamSize; // in MB
      }
      // iOS: device_info_plus tidak expose total RAM secara langsung
      return null;
    } catch (_) {
      return null;
    }
  }

  /// RAM perangkat dalam MB. Untuk optimasi OCR di HP RAM rendah (< 4 GB).
  static Future<int?> getDeviceRamMb() => _getDeviceRamMb();

  static Future<void> _showDialog(BuildContext context, int ramMb) async {
    final ramGb = ramMb >= 1024
        ? '${(ramMb / 1024).toStringAsFixed(1)}'
        : '${(ramMb / 1024).toStringAsFixed(2)}';

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Informasi Perangkat'),
        content: Text(
          'Traka berjalan optimal di perangkat dengan RAM minimal 6 GB. '
          'Perangkat Anda memiliki RAM $ramGb GB. '
          'Aplikasi masih bisa digunakan tetapi mungkin terasa lebih lambat.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Mengerti'),
          ),
        ],
      ),
    );
  }
}
