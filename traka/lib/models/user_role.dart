/// Role pengguna di aplikasi Traka.
/// Nilai disimpan di Firestore sebagai string ('penumpang' | 'driver').
enum UserRole {
  penumpang,
  driver,
}

extension UserRoleX on UserRole {
  /// Nilai untuk Firestore dan Cloud Functions.
  String get firestoreValue => name;

  /// Nama field di device_accounts (penumpangUid / driverUid).
  String get deviceIdField =>
      this == UserRole.penumpang ? 'penumpangUid' : 'driverUid';
}

extension UserRoleParse on String {
  /// Parse string ke UserRole. Return null jika tidak valid.
  UserRole? get toUserRoleOrNull {
    for (final r in UserRole.values) {
      if (r.name == this) return r;
    }
    return null;
  }
}

