import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/user_role.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:jailbreak_root_detection/jailbreak_root_detection.dart';

import 'device_service.dart';

/// Keamanan device ID:
/// - Cegah spam: max 1 akun per role per device (penumpang + driver = OK)
/// - Rate limit: max gagal login per jam (via Cloud Function device_rate_limit)
/// - Deteksi emulator
///
/// Pengecualian: device sama untuk penumpang + driver diperbolehkan.
class DeviceSecurityService {
  static const _collectionDeviceAccounts = 'device_accounts';

  /// Cek apakah perangkat ter-root (Android) atau jailbreak (iOS).
  static Future<bool> isRootedOrJailbroken() async {
    try {
      final isNotTrust = await JailbreakRootDetection.instance.isNotTrust;
      if (isNotTrust) return true;
      final isJailBroken = await JailbreakRootDetection.instance.isJailBroken;
      return isJailBroken;
    } catch (_) {
      return false;
    }
  }

  /// Cek apakah perangkat adalah emulator.
  static Future<bool> isEmulator() async {
    try {
      final deviceInfo = DeviceInfoPlugin();
      if (Platform.isAndroid) {
        final android = await deviceInfo.androidInfo;
        return !android.isPhysicalDevice;
      } else if (Platform.isIOS) {
        final ios = await deviceInfo.iosInfo;
        return !ios.isPhysicalDevice;
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  /// Cek apakah registrasi diperbolehkan.
  /// Memanggil Cloud Function checkRegistrationAllowed (Firestore rules terbatas).
  static Future<DeviceSecurityResult> checkRegistrationAllowed(
    String role,
  ) async {
    try {
      final info = await DeviceService.getDeviceInfo();
      final deviceId = info.deviceId?.trim() ?? '';
      final installId = info.installId.trim();

      if (kDebugMode) debugPrint('[Traka DeviceCheck] role=$role, installId=${installId.isEmpty ? "(kosong)" : "..."}');

      final isEmu = await isEmulator();
      if (isEmu) {
        return DeviceSecurityResult.blocked(
          'Registrasi tidak diperbolehkan dari emulator.',
        );
      }

      final isRooted = await isRootedOrJailbroken();
      if (isRooted) {
        return DeviceSecurityResult.blocked(
          'Registrasi tidak diperbolehkan dari perangkat yang di-root atau jailbreak.',
        );
      }

      final callable = FirebaseFunctions.instance.httpsCallable(
        'checkRegistrationAllowed',
      );
      final result = await callable.call({
        'installId': installId,
        'deviceId': deviceId,
        'role': role,
      });
      final data = result.data as Map<String, dynamic>?;
      final allowed = data?['allowed'] as bool? ?? false;
      final message = data?['message'] as String?;

      if (!allowed) {
        return DeviceSecurityResult.blocked(
          message ?? 'Registrasi tidak diperbolehkan.',
        );
      }
      if (kDebugMode) debugPrint('[Traka DeviceCheck] Cloud Function → allowed');
      return DeviceSecurityResult.allowed();
    } catch (e, st) {
      if (kDebugMode) debugPrint('[Traka DeviceCheck] Error: $e\n$st');
      return DeviceSecurityResult.blocked(
        'Tidak dapat memverifikasi perangkat. Silakan coba lagi atau hubungi admin.',
      );
    }
  }

  /// Melepaskan device lama dari device_accounts saat user login di device baru.
  /// Agar HP lama bisa dipakai untuk registrasi akun baru (driver/penumpang).
  static Future<void> releaseDeviceRegistration(
    String oldDeviceId,
    String role,
  ) async {
    final trimmed = oldDeviceId.trim();
    if (trimmed.isEmpty) return;
    try {
      final col =
          FirebaseFirestore.instance.collection(_collectionDeviceAccounts);
      final doc = await col.doc(trimmed).get();
      if (!doc.exists) return;
      final data = doc.data();
      final field = role == 'penumpang' ? 'penumpangUid' : 'driverUid';
      final storedUid = data?[field] as String?;
      if (storedUid == null || storedUid.isEmpty) return;

      await col.doc(trimmed).update({field: FieldValue.delete()});
      if (kDebugMode) debugPrint(
        '[Traka DeviceCheck] releaseDeviceRegistration: cleared $role dari $trimmed',
      );

      final installId = (data?['installId'] as String?)?.trim();
      if (installId != null &&
          installId.isNotEmpty &&
          installId != trimmed) {
        final installDoc = await col.doc(installId).get();
        if (installDoc.exists) {
          await col.doc(installId).update({field: FieldValue.delete()});
          if (kDebugMode) debugPrint(
            '[Traka DeviceCheck] releaseDeviceRegistration: cleared $role dari installId $installId',
          );
        }
      }
    } catch (e, st) {
      if (kDebugMode) debugPrint(
        '[Traka DeviceCheck] releaseDeviceRegistration Error: $e\n$st',
      );
    }
  }

  /// Catat registrasi berhasil (panggil setelah akun tersimpan).
  /// Hanya menulis ke installId (deviceId bisa tabrakan antar HP, installId unik per install).
  static Future<void> recordRegistration(String uid, String role) async {
    try {
      final info = await DeviceService.getDeviceInfo();
      final installId = info.installId.trim();
      if (installId.isEmpty) {
        if (kDebugMode) debugPrint('[Traka DeviceCheck] recordRegistration: installId kosong, skip');
        return;
      }

      final userRole = role.toUserRoleOrNull;
      if (userRole == null) return;
      final field = userRole.deviceIdField;
      final data = {
        field: uid,
        'osVersion': info.osVersion,
        'model': info.model,
        'installId': info.installId,
        'updatedAt': FieldValue.serverTimestamp(),
      };
      final col = FirebaseFirestore.instance.collection(
        _collectionDeviceAccounts,
      );
      await col.doc(installId).set(data, SetOptions(merge: true));
      if (kDebugMode) debugPrint('[Traka DeviceCheck] recordRegistration: berhasil tulis $role untuk installId');
    } catch (e, st) {
      if (kDebugMode) debugPrint('[Traka DeviceCheck] recordRegistration Error: $e\n$st');
      // Jangan rethrow - akun sudah dibuat, hanya device_accounts yang gagal
    }
  }

  /// Cek rate limit login (gagal berulang). Via Cloud Function (device_rate_limit aman).
  static Future<DeviceSecurityResult> checkLoginRateLimit() async {
    try {
      final info = await DeviceService.getDeviceInfo();
      final deviceKey = _deviceKey(info);
      if (deviceKey.isEmpty) return DeviceSecurityResult.allowed();

      final isEmu = await isEmulator();
      if (isEmu) {
        return DeviceSecurityResult.blocked(
          'Login tidak diperbolehkan dari emulator.',
        );
      }

      final isRooted = await isRootedOrJailbroken();
      if (isRooted) {
        return DeviceSecurityResult.blocked(
          'Login tidak diperbolehkan dari perangkat yang di-root atau jailbreak.',
        );
      }

      final callable = FirebaseFunctions.instance.httpsCallable(
        'checkLoginRateLimit',
      );
      final result = await callable.call({
        'deviceKey': deviceKey,
        'osVersion': info.osVersion,
        'model': info.model,
      });
      final data = result.data as Map<String, dynamic>?;
      final allowed = data?['allowed'] as bool? ?? true;
      final message = data?['message'] as String?;

      if (allowed) return DeviceSecurityResult.allowed();
      return DeviceSecurityResult.blocked(
        message ?? 'Terlalu banyak percobaan login gagal. Coba lagi dalam 1 jam.',
      );
    } catch (_) {
      return DeviceSecurityResult.allowed();
    }
  }

  /// Catat percobaan login (panggil saat login gagal). Via Cloud Function.
  static Future<void> recordLoginFailed() async {
    try {
      final info = await DeviceService.getDeviceInfo();
      final deviceKey = _deviceKey(info);
      if (deviceKey.isEmpty) return;

      final callable = FirebaseFunctions.instance.httpsCallable(
        'recordLoginFailed',
      );
      await callable.call({
        'deviceKey': deviceKey,
        'osVersion': info.osVersion,
        'model': info.model,
      });
    } catch (_) {}
  }

  /// Reset rate limit saat login berhasil. Via Cloud Function.
  static Future<void> recordLoginSuccess() async {
    try {
      final info = await DeviceService.getDeviceInfo();
      final deviceKey = _deviceKey(info);
      if (deviceKey.isEmpty) return;

      final callable = FirebaseFunctions.instance.httpsCallable(
        'recordLoginSuccess',
      );
      await callable.call({'deviceKey': deviceKey});
    } catch (_) {}
  }

  static String _deviceKey(TrakaDeviceInfo info) {
    final id = info.deviceId ?? info.installId;
    if (id.isEmpty) return '';
    return id;
  }
}

/// Hasil pengecekan keamanan device.
class DeviceSecurityResult {
  final bool allowed;
  final String? message;

  const DeviceSecurityResult({required this.allowed, this.message});

  factory DeviceSecurityResult.allowed() =>
      const DeviceSecurityResult(allowed: true);

  factory DeviceSecurityResult.blocked(String message) =>
      DeviceSecurityResult(allowed: false, message: message);
}
