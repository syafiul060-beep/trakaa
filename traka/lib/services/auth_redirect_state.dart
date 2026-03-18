/// State untuk auth redirect: hindari replace LoginScreen saat user sedang login
/// atau saat proses verifikasi (upload foto, KTP, SIM) agar tidak tiba-tiba logout.
class AuthRedirectState {
  AuthRedirectState._();

  static bool _isOnLoginScreen = false;
  static bool _isInVerificationFlow = false;
  static bool _isInLoginFlow = false;

  static bool get isOnLoginScreen => _isOnLoginScreen;
  static bool get isInVerificationFlow => _isInVerificationFlow;
  static bool get isInLoginFlow => _isInLoginFlow;

  static void setOnLoginScreen(bool value) {
    _isOnLoginScreen = value;
  }

  static void setInVerificationFlow(bool value) {
    _isInVerificationFlow = value;
  }

  static void setInLoginFlow(bool value) {
    _isInLoginFlow = value;
  }
}
