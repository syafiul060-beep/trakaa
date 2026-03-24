import 'package:cloud_firestore/cloud_firestore.dart';

/// Cek kelengkapan data verifikasi user.
/// Penumpang: face + KTP + phone
/// Driver: face + vehicle + SIM + phone
class VerificationService {
  VerificationService._();

  /// Field admin di `users/`: permintaan dokumen + pembatasan fitur.
  /// Hanya admin yang boleh mengubah [adminVerificationPendingAt], pesan, deadline, restrict.
  /// Pengguna boleh set [adminVerificationUserSubmittedAt] setelah mengirim data.

  /// Pesan singkat untuk UI (ID) saat fitur dibatasi.
  static const String adminVerificationBlockingHintId =
      'Beberapa fitur dibatasi sampai Anda mengirim data yang diminta.';

  /// Interval verifikasi wajah ulang: 6 bulan.
  static const int faceReverifyMonths = 6;

  /// Admin meminta verifikasi + pembatasan aktif + pengguna belum konfirmasi kirim.
  static bool isAdminVerificationBlockingFeatures(Map<String, dynamic> data) {
    final pending = data['adminVerificationPendingAt'];
    if (pending == null) return false;
    if (data['adminVerificationRestrictFeatures'] != true) return false;
    if (data['adminVerificationUserSubmittedAt'] != null) return false;
    return true;
  }

  /// Permintaan admin masih terbuka (belum dihapus/diselesaikan di panel admin).
  /// Dipakai warna centang: kuning saat true, hijau setelah [adminVerificationPendingAt] dihapus admin.
  static bool hasOpenAdminVerificationRequest(Map<String, dynamic> data) {
    return data['adminVerificationPendingAt'] != null;
  }

  /// Apakah user perlu verifikasi wajah ulang (setiap 6 bulan).
  /// Return true jika: punya faceVerificationUrl TAPI (belum pernah ada lastVerifiedAt ATAU sudah lewat 6 bulan).
  static bool needsFaceReverify(Map<String, dynamic> data) {
    final faceUrl = (data['faceVerificationUrl'] as String?)?.trim();
    if (faceUrl == null || faceUrl.isEmpty) return false;

    final lastVerified = data['faceVerificationLastVerifiedAt'];
    if (lastVerified == null) return true;

    DateTime? dt;
    if (lastVerified is DateTime) {
      dt = lastVerified;
    } else if (lastVerified is Timestamp) {
      dt = lastVerified.toDate();
    }
    if (dt == null) return true;

    final now = DateTime.now();
    final diff = now.difference(dt);
    return diff.inDays >= (faceReverifyMonths * 30); // ~6 bulan
  }

  /// Penumpang terverifikasi lengkap: foto wajah + KTP + nomor HP.
  static bool isPenumpangVerified(Map<String, dynamic> data) {
    final face = (data['faceVerificationUrl'] as String?)?.trim();
    final hasFace = face != null && face.isNotEmpty;
    final hasKTP = data['passengerKTPVerifiedAt'] != null ||
        data['passengerKTPNomorHash'] != null;
    final phone = ((data['phoneNumber'] as String?) ?? '').trim();
    return hasFace && hasKTP && phone.isNotEmpty;
  }

  /// Driver terverifikasi lengkap: foto wajah + data kendaraan (mobil) + SIM + nomor HP.
  static bool isDriverVerified(Map<String, dynamic> data) {
    final face = (data['faceVerificationUrl'] as String?)?.trim();
    final hasFace = face != null && face.isNotEmpty;
    final hasVehicle =
        data['vehiclePlat'] != null || data['vehicleUpdatedAt'] != null;
    final hasDriver = data['driverSIMVerifiedAt'] != null ||
        data['driverSIMNomorHash'] != null;
    final phone = ((data['phoneNumber'] as String?) ?? '').trim();
    return hasFace && hasVehicle && hasDriver && phone.isNotEmpty;
  }

  /// Data kendaraan sudah tersimpan (plat atau waktu simpan) — driver tidak boleh mengubah sendiri.
  static bool isVehicleDataLockedForDriver(Map<String, dynamic> data) {
    return data['vehiclePlat'] != null || data['vehicleUpdatedAt'] != null;
  }

  /// Driver sudah kirim foto STNK untuk minta perubahan data kendaraan (menunggu admin).
  static bool hasPendingVehicleChangeRequest(Map<String, dynamic> data) {
    return data['vehicleChangeRequestAt'] != null;
  }
}
