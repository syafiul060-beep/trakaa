import 'package:cloud_firestore/cloud_firestore.dart';

import 'verification_service.dart';

/// Data minimal untuk shell [IndexedStack] penumpang/driver.
/// Stream sumber: `users/{uid}` — **hanya emit baru** jika fingerprint
/// verifikasi berubah (bukan tiap update `lastSeen` / field lain).
class UserShellRebuild {
  const UserShellRebuild({
    required this.isVerified,
    required this.adminVerificationBlocksFeatures,
  });

  final bool isVerified;
  /// True jika admin meminta data + restrict + user belum konfirmasi kirim.
  final bool adminVerificationBlocksFeatures;
}

String _adminVerificationFingerprint(Map<String, dynamic> data) {
  final m = (data['adminVerificationMessage'] as String?) ?? '';
  return '${data['adminVerificationPendingAt']}_${data['adminVerificationRestrictFeatures']}_${data['adminVerificationUserSubmittedAt']}_$m';
}

/// Fingerprint field yang mempengaruhi [VerificationService.isPenumpangVerified].
String _penumpangVerificationFingerprint(Map<String, dynamic> data) {
  final face = (data['faceVerificationUrl'] as String?)?.trim() ?? '';
  final ktp =
      '${data['passengerKTPVerifiedAt']}_${data['passengerKTPNomorHash']}';
  final phone = ((data['phoneNumber'] as String?) ?? '').trim();
  return '$face|$ktp|$phone|${_adminVerificationFingerprint(data)}';
}

/// Fingerprint field yang mempengaruhi [VerificationService.isDriverVerified].
String _driverVerificationFingerprint(Map<String, dynamic> data) {
  final face = (data['faceVerificationUrl'] as String?)?.trim() ?? '';
  final vehicle = '${data['vehiclePlat']}_${data['vehicleUpdatedAt']}';
  final sim = '${data['driverSIMVerifiedAt']}_${data['driverSIMNomorHash']}';
  final phone = ((data['phoneNumber'] as String?) ?? '').trim();
  final vreq =
      '${data['vehicleChangeRequestAt']}_${data['vehicleChangeRequestStnkUrl']}';
  return '$face|$vehicle|$sim|$phone|$vreq|${_adminVerificationFingerprint(data)}';
}

/// Stream shell penumpang: hindari rebuild penuh saat dokumen user berubah tanpa dampak verifikasi.
Stream<UserShellRebuild> penumpangUserShellStream(String uid) {
  return _distinctVerificationShellStream(
    uid,
    fingerprint: _penumpangVerificationFingerprint,
    isVerified: VerificationService.isPenumpangVerified,
  );
}

/// Stream shell driver: sama seperti penumpang.
Stream<UserShellRebuild> driverUserShellStream(String uid) {
  return _distinctVerificationShellStream(
    uid,
    fingerprint: _driverVerificationFingerprint,
    isVerified: VerificationService.isDriverVerified,
  );
}

Stream<UserShellRebuild> _distinctVerificationShellStream(
  String uid, {
  required String Function(Map<String, dynamic> data) fingerprint,
  required bool Function(Map<String, dynamic> data) isVerified,
}) async* {
  String? lastFp;
  await for (final snap
      in FirebaseFirestore.instance.collection('users').doc(uid).snapshots()) {
    final data = snap.data() ?? <String, dynamic>{};
    final fp = fingerprint(data);
    if (fp == lastFp) continue;
    lastFp = fp;
    yield UserShellRebuild(
      isVerified: isVerified(data),
      adminVerificationBlocksFeatures:
          VerificationService.isAdminVerificationBlockingFeatures(data),
    );
  }
}
