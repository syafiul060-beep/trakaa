import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart' as ph;
import 'package:geolocator/geolocator.dart';

/// Service untuk mengelola semua permission yang diperlukan aplikasi.
/// Jika user tidak memberikan izin, akan terus meminta sampai diberikan.
class PermissionService {
  /// Request izin minimal untuk masuk ke home (lokasi + device ID).
  /// Kamera & notifikasi diminta nanti saat dibutuhkan.
  static Future<bool> requestEssentialForHome(BuildContext context) async {
    bool allGranted = false;
    while (!allGranted) {
      if (!context.mounted) return false;
      final locationGranted = await requestLocationPermission(context);
      if (!context.mounted) return false;
      final phoneStateGranted = await requestPhoneStatePermission(context);
      allGranted = locationGranted && phoneStateGranted;
      if (!allGranted) {
        if (!context.mounted) return false;
        final shouldContinue = await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => AlertDialog(
            title: const Text('Izin Diperlukan'),
            content: const Text(
              'Aplikasi memerlukan izin lokasi dan device ID untuk masuk. '
              'Lokasi dipakai untuk peta dan layanan di sekitar Anda; device ID untuk keamanan akun. '
              'Untuk berbagi posisi saat aplikasi di latar belakang, nanti Anda bisa mengaktifkan izin lokasi '
              'Selalu—biasanya ditawarkan saat ada pesanan atau saat navigasi.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: const Text('Tutup'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                child: const Text('Berikan Izin'),
              ),
            ],
          ),
        );
        if (shouldContinue != true) return false;
        if (!locationGranted || !phoneStateGranted) {
          if (!context.mounted) return false;
          final open = await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text('Buka Pengaturan'),
              content: const Text(
                'Buka pengaturan aplikasi dan berikan izin yang diperlukan.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(false),
                  child: const Text('Batal'),
                ),
                ElevatedButton(
                  onPressed: () => Navigator.of(ctx).pop(true),
                  child: const Text('Buka Pengaturan'),
                ),
              ],
            ),
          );
          if (open == true) {
            await ph.openAppSettings();
            await Future.delayed(const Duration(seconds: 1));
          }
        }
      }
    }
    return true;
  }

  /// Request semua permission yang diperlukan aplikasi.
  /// Akan terus meminta sampai semua permission diberikan.
  static Future<bool> requestAllPermissions(BuildContext context) async {
    bool allGranted = false;

    while (!allGranted) {
      if (!context.mounted) return false;
      // Request permission satu per satu
      final locationGranted = await requestLocationPermission(context);
      if (!context.mounted) return false;
      final phoneStateGranted = await requestPhoneStatePermission(context);
      if (!context.mounted) return false;
      final cameraGranted = await requestCameraPermission(context);
      if (!context.mounted) return false;
      final notificationGranted = await requestNotificationPermission(context);

      allGranted =
          locationGranted &&
          phoneStateGranted &&
          cameraGranted &&
          notificationGranted;

      if (!allGranted) {
        if (!context.mounted) return false;
        // Jika ada permission yang belum diberikan, tampilkan dialog
        final shouldContinue = await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => AlertDialog(
            title: const Text('Izin Diperlukan'),
            content: const Text(
              'Aplikasi Traka memerlukan beberapa izin untuk berfungsi dengan baik:\n\n'
              '• Lokasi: peta, mencari driver, dan rute; untuk pembaruan lokasi saat layar mati atau app di belakang, '
              'nanti Anda bisa memilih izin Selalu (diminta saat perjalanan atau berbagi lokasi)\n'
              '• Device ID: untuk keamanan akun\n'
              '• Kamera: untuk verifikasi wajah\n'
              '• Notifikasi: untuk menerima pesan dan update\n\n'
              'Tanpa izin ini, aplikasi tidak dapat berfungsi dengan baik.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: const Text('Tutup Aplikasi'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                child: const Text('Berikan Izin'),
              ),
            ],
          ),
        );

        if (shouldContinue != true) {
          // User memilih tutup aplikasi
          return false;
        }

        // Buka pengaturan jika ada permission yang ditolak permanent
        if (!locationGranted ||
            !phoneStateGranted ||
            !cameraGranted ||
            !notificationGranted) {
          if (!context.mounted) return false;
          final openSettings = await showDialog<bool>(
            context: context,
            barrierDismissible: false,
            builder: (ctx) => AlertDialog(
              title: const Text('Buka Pengaturan'),
              content: const Text(
                'Beberapa izin diperlukan. Silakan buka pengaturan aplikasi '
                'dan berikan semua izin yang diperlukan.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(false),
                  child: const Text('Batal'),
                ),
                ElevatedButton(
                  onPressed: () => Navigator.of(ctx).pop(true),
                  child: const Text('Buka Pengaturan'),
                ),
              ],
            ),
          );

          if (openSettings == true) {
            await ph.openAppSettings();
            // Tunggu sebentar lalu cek lagi
            await Future.delayed(const Duration(seconds: 1));
          }
        }
      }
    }

    return true;
  }

  /// Request permission lokasi dengan loop sampai diberikan.
  static Future<bool> requestLocationPermission(BuildContext context) async {
    while (true) {
      // Cek apakah GPS aktif
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (!context.mounted) return false;
        final openSettings = await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => AlertDialog(
            title: const Text('GPS Tidak Aktif'),
            content: const Text(
              'Aplikasi Traka memerlukan layanan lokasi/GPS agar peta, penjemputan, dan navigasi akurat. '
              'Silakan aktifkan di pengaturan perangkat Anda.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: const Text('Batal'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                child: const Text('Buka Pengaturan'),
              ),
            ],
          ),
        );

        if (openSettings == true) {
          await Geolocator.openLocationSettings();
          await Future.delayed(const Duration(seconds: 1));
          continue;
        } else {
          return false;
        }
      }

      // Cek permission lokasi
      LocationPermission permission = await Geolocator.checkPermission();

      if (permission == LocationPermission.deniedForever) {
        if (!context.mounted) return false;
        final openSettings = await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => AlertDialog(
            title: const Text('Izin Lokasi Diperlukan'),
            content: const Text(
              'Izin lokasi diperlukan untuk aplikasi Traka. '
              'Silakan buka pengaturan aplikasi dan berikan izin lokasi.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: const Text('Batal'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                child: const Text('Buka Pengaturan'),
              ),
            ],
          ),
        );

        if (openSettings == true) {
          await ph.openAppSettings();
          await Future.delayed(const Duration(seconds: 1));
          continue;
        } else {
          return false;
        }
      }

      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          // User tolak, tanya lagi
          if (!context.mounted) return false;
          final retry = await showDialog<bool>(
            context: context,
            barrierDismissible: false,
            builder: (ctx) => AlertDialog(
              title: const Text('Izin Lokasi Diperlukan'),
              content: const Text(
                'Aplikasi Traka memerlukan izin lokasi untuk berfungsi. '
                'Anda bisa mulai dengan izin saat aplikasi digunakan; untuk berbagi posisi saat layar terkunci atau '
                'app di belakang layar, nanti pilih izin Selalu ketika diminta. '
                'Tanpa izin lokasi dasar, aplikasi tidak dapat digunakan.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(false),
                  child: const Text('Batal'),
                ),
                ElevatedButton(
                  onPressed: () => Navigator.of(ctx).pop(true),
                  child: const Text('Berikan Izin'),
                ),
              ],
            ),
          );

          if (retry == true) {
            continue;
          } else {
            return false;
          }
        }
      }

      // Izin diberikan
      if (permission == LocationPermission.whileInUse ||
          permission == LocationPermission.always) {
        return true;
      }
    }
  }

  /// Request permission READ_PHONE_STATE untuk membaca device ID.
  static Future<bool> requestPhoneStatePermission(BuildContext context) async {
    while (true) {
      final status = await ph.Permission.phone.status;

      if (status.isGranted) {
        return true;
      }

      if (status.isPermanentlyDenied) {
        if (!context.mounted) return false;
        final openSettings = await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => AlertDialog(
            title: const Text('Izin Device ID Diperlukan'),
            content: const Text(
              'Izin untuk membaca Device ID diperlukan untuk keamanan akun. '
              'Silakan buka pengaturan aplikasi dan berikan izin.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: const Text('Batal'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                child: const Text('Buka Pengaturan'),
              ),
            ],
          ),
        );

        if (openSettings == true) {
          await ph.openAppSettings();
          await Future.delayed(const Duration(seconds: 1));
          continue;
        } else {
          return false;
        }
      }

      // Request permission
      final result = await ph.Permission.phone.request();

      if (result.isGranted) {
        return true;
      }

      if (result.isDenied) {
        // User tolak, tanya lagi
        if (!context.mounted) return false;
        final retry = await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => AlertDialog(
            title: const Text('Izin Device ID Diperlukan'),
            content: const Text(
              'Aplikasi Traka memerlukan izin untuk membaca Device ID '
              'untuk keamanan akun. Tanpa izin ini, aplikasi tidak dapat digunakan.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: const Text('Batal'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                child: const Text('Berikan Izin'),
              ),
            ],
          ),
        );

        if (retry == true) {
          continue;
        } else {
          return false;
        }
      }
    }
  }

  /// Request permission kamera.
  static Future<bool> requestCameraPermission(BuildContext context) async {
    while (true) {
      final status = await ph.Permission.camera.status;

      if (status.isGranted) {
        return true;
      }

      if (status.isPermanentlyDenied) {
        if (!context.mounted) return false;
        final openSettings = await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => AlertDialog(
            title: const Text('Izin Kamera Diperlukan'),
            content: const Text(
              'Izin kamera diperlukan untuk verifikasi wajah. '
              'Silakan buka pengaturan aplikasi dan berikan izin kamera.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: const Text('Batal'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                child: const Text('Buka Pengaturan'),
              ),
            ],
          ),
        );

        if (openSettings == true) {
          await ph.openAppSettings();
          await Future.delayed(const Duration(seconds: 1));
          continue;
        } else {
          return false;
        }
      }

      // Request permission
      final result = await ph.Permission.camera.request();

      if (result.isGranted) {
        return true;
      }

      if (result.isDenied) {
        // User tolak, tanya lagi
        if (!context.mounted) return false;
        final retry = await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => AlertDialog(
            title: const Text('Izin Kamera Diperlukan'),
            content: const Text(
              'Aplikasi Traka memerlukan izin kamera untuk verifikasi wajah. '
              'Tanpa izin ini, Anda tidak dapat login atau mendaftar.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: const Text('Batal'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                child: const Text('Berikan Izin'),
              ),
            ],
          ),
        );

        if (retry == true) {
          continue;
        } else {
          return false;
        }
      }
    }
  }

  /// Request permission notifikasi (Android 13+).
  static Future<bool> requestNotificationPermission(
    BuildContext context,
  ) async {
    // Cek apakah Android 13+ (permission handler akan handle ini)
    final status = await ph.Permission.notification.status;

    if (status.isGranted) {
      return true;
    }

    if (status.isPermanentlyDenied) {
      if (!context.mounted) return false;
      final openSettings = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          title: const Text('Izin Notifikasi Diperlukan'),
          content: const Text(
            'Izin notifikasi diperlukan untuk menerima pesan dan update. '
            'Silakan buka pengaturan aplikasi dan berikan izin notifikasi.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Batal'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Buka Pengaturan'),
            ),
          ],
        ),
      );

      if (openSettings == true) {
        await ph.openAppSettings();
      }
      return false;
    }

    // Request permission
    final result = await ph.Permission.notification.request();
    return result.isGranted;
  }
}
