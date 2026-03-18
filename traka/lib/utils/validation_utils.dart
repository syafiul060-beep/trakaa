/// Utility validasi form (password, email, dll).
class ValidationUtils {
  ValidationUtils._();

  /// Validasi password: minimal 8 karakter, harus mengandung angka.
  static String? validatePassword(String? value, {required bool isIndonesian}) {
    if (value == null || value.isEmpty) {
      return isIndonesian ? 'Masukkan kata sandi' : 'Enter password';
    }
    if (value.length < 8) {
      return isIndonesian
          ? 'Panjang kata sandi minimal 8, harus mengandung angka'
          : 'Password minimum 8 characters, must contain a number';
    }
    if (!value.contains(RegExp(r'[0-9]'))) {
      return isIndonesian
          ? 'Panjang kata sandi minimal 8, harus mengandung angka'
          : 'Password minimum 8 characters, must contain a number';
    }
    return null;
  }

  /// Validasi konfirmasi password.
  static String? validateConfirmPassword(
    String? value,
    String? password, {
    required bool isIndonesian,
  }) {
    if (value == null || value.isEmpty) {
      return isIndonesian ? 'Konfirmasi kata sandi' : 'Confirm password';
    }
    if (value != password) {
      return isIndonesian ? 'Kata sandi tidak cocok' : 'Passwords do not match';
    }
    return null;
  }
}
