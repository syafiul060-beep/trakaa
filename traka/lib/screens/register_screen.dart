import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';

import 'login_screen.dart';
import 'driver_screen.dart';
import 'penumpang_screen.dart';
import '../widgets/app_update_wrapper.dart';
import '../widgets/auth_loading_overlay.dart';
import '../widgets/traka_loading_indicator.dart';

import '../l10n/app_localizations.dart';
import '../services/locale_service.dart';
import '../services/account_deletion_service.dart';
import '../services/app_analytics_service.dart';
import '../services/device_security_service.dart';
import '../services/fcm_service.dart';
import '../services/voice_call_incoming_service.dart';
import '../theme/app_interaction_styles.dart';
import '../theme/app_theme.dart';
import '../theme/traka_visual_tokens.dart';
import '../theme/responsive.dart';
import '../services/fake_gps_overlay_service.dart';
import '../services/location_service.dart';
import '../models/user_role.dart';
import '../utils/app_logger.dart';
import '../config/google_oauth_web_client.dart';
import '../utils/phone_utils.dart';
import '../utils/phone_verification_snackbar.dart';
import 'privacy_screen.dart';
import 'terms_screen.dart';
import '../theme/traka_snackbar.dart';

/// Tipe pendaftaran: Penumpang atau Driver.
enum RegisterType { penumpang, driver }

/// Pesan di [AuthLoadingOverlay] saat loading (Google vs kirim formulir).
enum _RegisterAuthOverlayKind { googleEmail, completingRegistration }

/// Jarak vertikal konsisten (skala responsif), selaras dengan halaman login.
class _RegisterLayoutGap {
  _RegisterLayoutGap(this._context);
  final BuildContext _context;
  double _s(double base) => _context.responsive.spacing(base);
  double get xs => _s(8);
  double get sm => _s(12);
  double get md => _s(16);
  double get lg => _s(20);
  double get xl => _s(24);
  double get xxl => _s(32);
}

class RegisterScreen extends StatefulWidget {
  final RegisterType type;
  final bool useGoogleSignUp;

  const RegisterScreen({
    super.key,
    required this.type,
    this.useGoogleSignUp = false,
  });

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _otpController = TextEditingController();

  bool _agreeToTerms = false;
  bool _isLoading = false;
  _RegisterAuthOverlayKind? _registerAuthOverlayKind;
  /// OTP sedang diminta — tanpa [AuthLoadingOverlay] agar WebView reCAPTCHA tidak «nempel» di atas scrim.
  bool _otpRequestInFlight = false;
  bool _phoneOtpSent = false;
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  String? _phoneVerificationId;

  AppLocalizations get l10n => AppLocalizations(locale: LocaleService.current);

  void _setRegisterLoading(
    bool value, {
    _RegisterAuthOverlayKind? overlayKind,
  }) {
    if (!mounted) return;
    setState(() {
      _isLoading = value;
      _registerAuthOverlayKind = value ? overlayKind : null;
    });
  }

  String? _registerAuthOverlayMessage() {
    if (!_isLoading || _otpRequestInFlight) return null;
    switch (_registerAuthOverlayKind) {
      case _RegisterAuthOverlayKind.googleEmail:
        return l10n.authOverlayGoogleEmailVerifying;
      case _RegisterAuthOverlayKind.completingRegistration:
        return l10n.authOverlayCompletingRegistration;
      case null:
        return null;
    }
  }

  bool get _googleUserReady {
    if (!widget.useGoogleSignUp) return true;
    final u = FirebaseAuth.instance.currentUser;
    if (u == null) return false;
    return u.providerData.any((p) => p.providerId == 'google.com');
  }

  /// Akun Google ini sudah punya profil Traka — daftar ulang memicu bentrok; arahkan ke login.
  Future<bool> _redirectIfGoogleAccountAlreadyRegistered(User user) async {
    final snap =
        await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
    if (!snap.exists) return false;
    final data = snap.data();
    if (AccountDeletionService.isDeleted(data)) return false;

    await FirebaseAuth.instance.signOut();
    if (!mounted) return true;
    _setRegisterLoading(false);
    ScaffoldMessenger.of(context).showSnackBar(
      TrakaSnackBar.warning(context, Text(
          l10n.locale == AppLocale.id
              ? 'Akun Google ini sudah terdaftar di Traka. Silakan login (Google atau nomor + OTP).'
              : 'This Google account is already registered. Please sign in (Google or phone + SMS code).',
        ), behavior: SnackBarBehavior.floating),
    );
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => const AppUpdateWrapper(child: LoginScreen()),
      ),
    );
    return true;
  }

  /// OTP pernah berhasil (Google + phone di Auth) tetapi tulis Firestore belum — selesaikan tanpa bentrok OTP ulang.
  Future<bool> _completeGoogleRegistrationIfAuthHasPhone(User user) async {
    if (!widget.useGoogleSignUp) return false;
    final doc =
        await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
    if (doc.exists) return false;
    final phoneRaw = user.phoneNumber?.trim();
    if (phoneRaw == null || phoneRaw.isEmpty) return false;
    final hasGoogle =
        user.providerData.any((p) => p.providerId == 'google.com');
    final hasPhone =
        user.providerData.any((p) => p.providerId == 'phone');
    if (!hasGoogle || !hasPhone) return false;

    final name = _nameController.text.trim().isNotEmpty
        ? _nameController.text.trim()
        : (user.displayName?.trim() ?? '');
    if (name.isEmpty) return false;

    final role = (widget.type == RegisterType.penumpang
            ? UserRole.penumpang
            : UserRole.driver)
        .firestoreValue;
    return _completeRegistration(
      user.uid,
      name: name,
      role: role,
      phoneE164: phoneRaw,
      email: user.email,
    );
  }

  /// Email Google sudah dipakai dokumen `users` dengan uid lain → cegah bentrok profil.
  Future<bool> _blockIfGoogleEmailLinkedToOtherFirestoreUser(User user) async {
    final email = user.email?.trim();
    if (email == null || email.isEmpty) return false;
    try {
      final callable = FirebaseFunctions.instance
          .httpsCallable('checkGoogleEmailConflictForRegister');
      final result = await callable.call(<String, dynamic>{
        'email': email,
        'currentUid': user.uid,
      });
      final data = result.data as Map<String, dynamic>?;
      if (data?['conflict'] != true) return false;
      await FirebaseAuth.instance.signOut();
      if (!mounted) return true;
      _setRegisterLoading(false);
      ScaffoldMessenger.of(context).showSnackBar(
        TrakaSnackBar.warning(context, Text(
            l10n.locale == AppLocale.id
                ? 'Email Google ini sudah dipakai profil Traka lain. Gunakan Login atau akun Google lain.'
                : 'This Google email is already used by another Traka profile. Sign in or use a different Google account.',
          ), behavior: SnackBarBehavior.floating),
      );
      return true;
    } catch (e, st) {
      logError('RegisterScreen.checkGoogleEmailConflictForRegister', e, st);
      return false;
    }
  }

  String get _registrationRoleFirestoreValue =>
      (widget.type == RegisterType.penumpang
              ? UserRole.penumpang
              : UserRole.driver)
          .firestoreValue;

  /// Daftar Google: perangkat sudah dipakai untuk role yang sama → info + ke Login (bisa sebelum/sesudah pilih akun Google).
  Future<bool> _redirectIfDeviceNotAllowedForGoogleRegister() async {
    final result = await DeviceSecurityService.checkRegistrationAllowed(
      _registrationRoleFirestoreValue,
    );
    if (!mounted) return true;
    if (result.allowed) return false;

    await FirebaseAuth.instance.signOut();
    try {
      await GoogleSignIn().signOut();
    } catch (_) {}

    if (!mounted) return true;
    _setRegisterLoading(false);
    final message = result.message ??
        (l10n.locale == AppLocale.id
            ? (widget.type == RegisterType.driver
                ? 'Perangkat ini sudah terdaftar sebagai driver. Silakan login.'
                : 'Perangkat ini sudah terdaftar sebagai penumpang. Silakan login.')
            : (widget.type == RegisterType.driver
                ? 'This device is already registered as a driver. Please sign in.'
                : 'This device is already registered as a passenger. Please sign in.'));
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => LoginScreen(deviceAlreadyUsedMessage: message),
      ),
    );
    return true;
  }

  Future<void> _signInWithGoogleForRegister() async {
    FocusScope.of(context).unfocus();
    _setRegisterLoading(
      true,
      overlayKind: _RegisterAuthOverlayKind.googleEmail,
    );
    await Future<void>.delayed(Duration.zero);
    try {
      if (await _redirectIfDeviceNotAllowedForGoogleRegister()) return;
      await GoogleSignIn().signOut();
      await FirebaseAuth.instance.signOut();
      final googleSignIn = GoogleSignIn(
        scopes: const <String>['email', 'profile'],
        serverClientId: kGoogleOAuthWebClientId,
      );
      final account = await googleSignIn.signIn();
      if (!mounted) return;
      if (account == null) {
        _setRegisterLoading(false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.googleSignInCancelled),
            behavior: SnackBarBehavior.floating,
          ),
        );
        return;
      }
      final auth = await account.authentication;
      if (auth.idToken == null && auth.accessToken == null) {
        if (!mounted) return;
        _setRegisterLoading(false);
        ScaffoldMessenger.of(context).showSnackBar(
          TrakaSnackBar.error(context, Text(l10n.googleSignInFailed), behavior: SnackBarBehavior.floating),
        );
        return;
      }
      final credential = GoogleAuthProvider.credential(
        accessToken: auth.accessToken,
        idToken: auth.idToken,
      );
      final uc = await FirebaseAuth.instance.signInWithCredential(credential);
      final user = uc.user;
      if (!mounted) return;
      if (user == null) {
        _setRegisterLoading(false);
        ScaffoldMessenger.of(context).showSnackBar(
          TrakaSnackBar.error(context, Text(l10n.googleSignInFailed), behavior: SnackBarBehavior.floating),
        );
        return;
      }
      if (await _redirectIfDeviceNotAllowedForGoogleRegister()) return;
      final display = user.displayName?.trim();
      if (display != null &&
          display.isNotEmpty &&
          _nameController.text.trim().isEmpty) {
        _nameController.text = display;
      }
      if (await _blockIfGoogleEmailLinkedToOtherFirestoreUser(user)) return;
      if (await _redirectIfGoogleAccountAlreadyRegistered(user)) return;
      if (await _completeGoogleRegistrationIfAuthHasPhone(user)) return;
      _setRegisterLoading(false);
    } on FirebaseAuthException catch (e, st) {
      logError('RegisterScreen.signInWithGoogle', e, st);
      if (!mounted) return;
      _setRegisterLoading(false);
      final String msg;
      switch (e.code) {
        case 'account-exists-with-different-credential':
          msg = l10n.locale == AppLocale.id
              ? 'Akun dengan email ini sudah ada dengan cara masuk lain. Gunakan Login dan pilih metode yang sama seperti saat pertama mendaftar.'
              : 'An account already exists with a different sign-in method. Use Log in with the same method you used when you registered.';
          break;
        case 'email-already-in-use':
          msg = l10n.locale == AppLocale.id
              ? 'Email sudah dipakai. Gunakan Login atau daftar dengan akun lain.'
              : 'This email is already in use. Sign in or use another account.';
          break;
        case 'credential-already-in-use':
          msg = l10n.locale == AppLocale.id
              ? 'Kredensial ini sudah terhubung ke akun lain. Silakan login.'
              : 'This sign-in is already linked to another account. Please sign in.';
          break;
        default:
          msg = e.message ?? l10n.googleSignInFailed;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        TrakaSnackBar.error(context, Text(msg), behavior: SnackBarBehavior.floating),
      );
    } catch (e, st) {
      logError('RegisterScreen.signInWithGoogle', e, st);
      if (!mounted) return;
      _setRegisterLoading(false);
      ScaffoldMessenger.of(context).showSnackBar(
        TrakaSnackBar.error(context, Text(l10n.googleSignInFailed), behavior: SnackBarBehavior.floating),
      );
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _checkDeviceAndBlockIfNeeded();
      if (!mounted) return;
      // Biar layar pendaftaran sempat terlukis sebelum dialog izin lokasi (terasa lebih responsif).
      await Future<void>.delayed(const Duration(milliseconds: 350));
      if (!mounted) return;
      await _requestLocationPermissionForAll();
    });
  }

  /// Minta izin lokasi untuk semua pengguna (penumpang dan driver).
  Future<void> _requestLocationPermissionForAll() async {
    final hasPermission = await LocationService.requestPermissionPersistent(
      context,
    );
    if (!hasPermission && mounted) {
      // User tidak kasih izin, kembali ke login
      ScaffoldMessenger.of(context).showSnackBar(
        TrakaSnackBar.error(context, Text(
            'Izin lokasi diperlukan untuk menggunakan aplikasi Traka.',
            textAlign: TextAlign.center,
            style: TextStyle(fontWeight: FontWeight.bold),
          ), behavior: SnackBarBehavior.floating,
          margin: EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          duration: Duration(seconds: 4)),
      );
      Navigator.of(context).pop();
    }
  }

  /// Cek device: jika perangkat sudah terdaftar (penumpang/driver), langsung ke halaman login dan tampilkan notifikasi.
  Future<void> _checkDeviceAndBlockIfNeeded() async {
    final result = await DeviceSecurityService.checkRegistrationAllowed(
      _registrationRoleFirestoreValue,
    );
    if (!mounted) return;
    if (!result.allowed) {
      final message =
          result.message ??
          (l10n.locale == AppLocale.id
              ? 'Perangkat sudah digunakan oleh $_registrationRoleFirestoreValue. Silakan login.'
              : 'Device already in use by $_registrationRoleFirestoreValue. Please login.');
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) => LoginScreen(deviceAlreadyUsedMessage: message),
        ),
      );
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _otpController.dispose();
    super.dispose();
  }

  /// Auth email untuk user phone+password: phoneE164 tanpa + + @traka.phone
  static String _phoneToAuthEmail(String phoneE164) {
    final digits = phoneE164.replaceAll(RegExp(r'[^\d]'), '');
    return '$digits@traka.phone';
  }

  Future<void> _sendPhoneOtp() async {
    if (widget.useGoogleSignUp && !_googleUserReady) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.connectGoogleFirst),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    final phone = _phoneController.text.trim();
    if (phone.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            l10n.locale == AppLocale.id
                ? 'No. telepon wajib diisi'
                : 'Phone number is required',
          ),
        ),
      );
      return;
    }
    final phoneE164 = toE164(phone);
    if (phoneE164.length < 12) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            l10n.locale == AppLocale.id
                ? 'Format no. telepon tidak valid'
                : 'Invalid phone number format',
          ),
        ),
      );
      return;
    }

    setState(() => _otpRequestInFlight = true);
    await Future<void>.delayed(Duration.zero);
    if (widget.useGoogleSignUp) {
      final u = FirebaseAuth.instance.currentUser;
      if (u != null) {
        final finished = await _completeGoogleRegistrationIfAuthHasPhone(u);
        if (finished) {
          if (mounted) setState(() => _otpRequestInFlight = false);
          return;
        }
      }
    }
    // Cek apakah nomor sudah terdaftar (untuk UX: arahkan ke Login)
    try {
      final callable = FirebaseFunctions.instance.httpsCallable('checkPhoneExists');
      final result = await callable.call({'phone': phoneE164});
      final data = result.data as Map<String, dynamic>?;
      final exists = data?['exists'] as bool? ?? false;
      if (exists && mounted) {
        setState(() => _otpRequestInFlight = false);
        ScaffoldMessenger.of(context).showSnackBar(
          TrakaSnackBar.warning(context, Text(
              l10n.locale == AppLocale.id
                  ? 'Nomor sudah terdaftar. Silakan login.'
                  : 'Number already registered. Please login.',
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ), behavior: SnackBarBehavior.floating,
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            duration: const Duration(seconds: 4)),
        );
        return;
      }
    } catch (e) {
      logError('RegisterScreen.checkPhoneExists', e, null);
    }

    try {
      // Pastikan klien reCAPTCHA siap sebelum WebView native dibuka; init di main.dart
      // berjalan unawaited sehingga tap cepat «Kirim kode» kadang memicu tampilan kosong.
      if (!kIsWeb &&
          (defaultTargetPlatform == TargetPlatform.android ||
              defaultTargetPlatform == TargetPlatform.iOS)) {
        try {
          await FirebaseAuth.instance.initializeRecaptchaConfig();
        } catch (_) {}
      }
      await FirebaseAuth.instance.verifyPhoneNumber(
        phoneNumber: phoneE164,
        verificationCompleted: (PhoneAuthCredential credential) async {
        if (!mounted) return;
        if (widget.useGoogleSignUp) {
          final user = FirebaseAuth.instance.currentUser;
          if (user == null) {
            if (mounted) setState(() => _otpRequestInFlight = false);
            return;
          }
          try {
            await user.linkWithCredential(credential);
          } on FirebaseAuthException catch (e) {
            if (e.code == 'provider-already-linked') {
              final done = await _completeGoogleRegistrationIfAuthHasPhone(user);
              if (done) {
                if (mounted) setState(() => _otpRequestInFlight = false);
                return;
              }
            }
            if (!mounted) return;
            setState(() {
              _registerAuthOverlayKind = null;
              _isLoading = false;
              _otpRequestInFlight = false;
            });
            final msg = e.code == 'credential-already-in-use'
                ? (l10n.locale == AppLocale.id
                    ? 'Nomor sudah terdaftar di akun lain. Silakan login.'
                    : 'This number is registered to another account. Please sign in.')
                : (e.code == 'provider-already-linked'
                    ? (l10n.locale == AppLocale.id
                        ? 'Nomor sudah terhubung ke sesi Google ini. Isi nama lengkap lalu coba lagi, atau buka Login.'
                        : 'This number is already linked. Enter your name and try again, or open Log in.')
                    : (l10n.locale == AppLocale.id
                        ? 'Nomor sudah terdaftar atau tidak bisa dipakai. Silakan login.'
                        : 'Number unavailable or already in use. Please log in.'));
            ScaffoldMessenger.of(context).showSnackBar(
              TrakaSnackBar.warning(context, Text(msg)),
            );
            return;
          } catch (_) {
            if (!mounted) return;
            setState(() {
              _registerAuthOverlayKind = null;
              _isLoading = false;
              _otpRequestInFlight = false;
            });
            ScaffoldMessenger.of(context).showSnackBar(
              TrakaSnackBar.warning(context, Text(
                  l10n.locale == AppLocale.id
                      ? 'Nomor sudah terdaftar atau tidak bisa dipakai. Silakan login.'
                      : 'Number unavailable or already in use. Please log in.',
                )),
            );
            return;
          }
          final role = (widget.type == RegisterType.penumpang
                  ? UserRole.penumpang
                  : UserRole.driver)
              .firestoreValue;
          final name = _nameController.text.trim();
          if (mounted) setState(() => _otpRequestInFlight = false);
          await _completeRegistration(
            user.uid,
            name: name,
            role: role,
            phoneE164: phoneE164,
            email: user.email,
          );
          return;
        }
        final password = _passwordController.text;
        if (password.length < 6) {
          if (mounted) setState(() => _otpRequestInFlight = false);
          return;
        }
        try {
          final authEmail = _phoneToAuthEmail(phoneE164);
          await FirebaseAuth.instance.createUserWithEmailAndPassword(
            email: authEmail,
            password: password,
          );
          final user = FirebaseAuth.instance.currentUser;
          if (user != null) {
            try {
              await user.linkWithCredential(credential);
            } catch (_) {}
            final role = (widget.type == RegisterType.penumpang
                    ? UserRole.penumpang
                    : UserRole.driver)
                .firestoreValue;
            final name = _nameController.text.trim();
            await _completeRegistration(
              user.uid,
              name: name,
              role: role,
              phoneE164: phoneE164,
            );
          }
        } catch (e) {
          if (mounted) {
            setState(() {
              _registerAuthOverlayKind = null;
              _isLoading = false;
              _otpRequestInFlight = false;
            });
            ScaffoldMessenger.of(context).showSnackBar(
              TrakaSnackBar.error(context, Text(e.toString().replaceAll('Exception: ', ''))),
            );
          }
        }
      },
      verificationFailed: (FirebaseAuthException e) {
        if (!mounted) return;
        setState(() {
          _registerAuthOverlayKind = null;
          _isLoading = false;
          _otpRequestInFlight = false;
        });
        showPhoneVerificationFailedSnackBar(
          context,
          exception: e,
          analyticsSource: 'register',
          l10n: l10n,
        );
      },
      codeSent: (String verificationId, int? resendToken) {
        if (!mounted) return;
        setState(() {
          _phoneVerificationId = verificationId;
          _phoneOtpSent = true;
          _registerAuthOverlayKind = null;
          _isLoading = false;
          _otpRequestInFlight = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          TrakaSnackBar.success(context, Text(
              l10n.locale == AppLocale.id
                  ? 'Kode verifikasi telah dikirim ke $phoneE164'
                  : 'Verification code sent to $phoneE164',
            )),
        );
      },
      codeAutoRetrievalTimeout: (_) {},
      );
    } catch (e, st) {
      logError('RegisterScreen.verifyPhoneNumber', e, st);
      if (!mounted) return;
      setState(() {
        _registerAuthOverlayKind = null;
        _isLoading = false;
        _otpRequestInFlight = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        TrakaSnackBar.error(context, Text(
            l10n.locale == AppLocale.id
                ? 'Tidak bisa memulai verifikasi SMS. Coba lagi.'
                : 'Could not start SMS verification. Try again.',
          )),
      );
    }
  }

  void _openTerms() {
    Navigator.push(
      context,
      MaterialPageRoute<void>(builder: (_) => const TermsScreen()),
    );
  }

  void _openPrivacy() {
    Navigator.push(
      context,
      MaterialPageRoute<void>(builder: (_) => const PrivacyScreen()),
    );
  }

  Future<bool?> _showCancelDeletionDialog() async {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Akun dalam proses penghapusan'),
        content: const Text(
          'Akun ini sedang dalam proses penghapusan. Batalkan penghapusan dan login?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Ya, batalkan & login'),
          ),
        ],
      ),
    );
  }

  /// Selesaikan registrasi: simpan ke Firestore, navigasi. Untuk phone dan email.
  /// `true` jika alur selesai sukses (navigasi ke login atau layar utama pemulihan akun).
  Future<bool> _completeRegistration(
    String uid, {
    required String name,
    required String role,
    String? phoneE164,
    String? email,
  }) async {

    // Cek apakah user doc sudah ada (akun lama / deleted)
    final userDoc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
    if (userDoc.exists) {
      final data = userDoc.data();
      if (AccountDeletionService.isDeleted(data)) {
        if (!mounted) return false;
        final confirm = await _showCancelDeletionDialog();
        if (!mounted || confirm != true) {
          _setRegisterLoading(false);
          await FirebaseAuth.instance.signOut();
          return false;
        }
        await AccountDeletionService.cancelAccountDeletion(uid);
        await DeviceSecurityService.recordRegistration(uid, role);
        if (!mounted) return false;
        _setRegisterLoading(false);
        FcmService.saveTokenForUser(uid);
        VoiceCallIncomingService.start(uid);
        if (role == UserRole.penumpang.firestoreValue) {
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute<void>(builder: (_) => const PenumpangScreen()),
            (route) => false,
          );
        } else {
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute<void>(builder: (_) => const DriverScreen()),
            (route) => false,
          );
        }
        return true;
      }
      // User sudah terdaftar, arahkan ke login
      await FirebaseAuth.instance.signOut();
      if (!mounted) return false;
      _setRegisterLoading(false);
      ScaffoldMessenger.of(context).showSnackBar(
        TrakaSnackBar.warning(context, Text(
            l10n.locale == AppLocale.id
                ? 'Akun sudah terdaftar. Silakan login.'
                : 'Account already registered. Please login.',
          )),
      );
      Navigator.of(context).pop();
      return false;
    }

    // Cek device + lokasi paralel agar lebih cepat
    final results = await Future.wait([
      DeviceSecurityService.checkRegistrationAllowed(role),
      LocationService.getDriverLocationResult(),
    ]);
    final securityResult = results[0] as DeviceSecurityResult;
    final locationResult = results[1] as DriverLocationResult;

    if (!securityResult.allowed) {
      if (!mounted) return false;
      _setRegisterLoading(false);
      ScaffoldMessenger.of(context).showSnackBar(
        TrakaSnackBar.error(context, Text(
            securityResult.message ?? 'Registrasi tidak diperbolehkan.',
            textAlign: TextAlign.center,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ), behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          duration: const Duration(seconds: 4)),
      );
      return false;
    }
    if (locationResult.errorMessage != null) {
      if (!mounted) return false;
      _setRegisterLoading(false);
      if (locationResult.isFakeGpsDetected) {
        FakeGpsOverlayService.showOverlay();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          TrakaSnackBar.error(context, Text(
              locationResult.errorMessage!,
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ), behavior: SnackBarBehavior.floating,
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            duration: const Duration(seconds: 5)),
        );
      }
      return false;
    }
    if (!locationResult.isInIndonesia) {
      if (!mounted) return false;
      _setRegisterLoading(false);
      ScaffoldMessenger.of(context).showSnackBar(
        TrakaSnackBar.error(context, Text(
            l10n.trakaIndonesiaOnly,
            textAlign: TextAlign.center,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ), behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          duration: const Duration(seconds: 4)),
      );
      return false;
    }

    final userRegion = locationResult.region ?? locationResult.country;
    final userLat = locationResult.latitude;
    final userLng = locationResult.longitude;
    final userKabupaten = locationResult.kabupaten;

    final Map<String, dynamic> userData = {
      'role': role,
      'phoneNumber': phoneE164 ?? '',
      'email': email ?? '',
      'displayName': name,
      'photoUrl': '',
      'faceVerificationUrl': '',
      'faceVerificationPool': [],
      'deviceId': '',
      'verificationStatus': 'pending',
      'appLocale': LocaleService.current == AppLocale.id ? 'id' : 'en',
      'createdAt': FieldValue.serverTimestamp(),
    };
    if (userRegion != null) userData['region'] = userRegion;
    if (userKabupaten != null && userKabupaten.isNotEmpty) {
      userData['kabupaten'] = userKabupaten;
    }
    if (userLat != null) userData['latitude'] = userLat;
    if (userLng != null) userData['longitude'] = userLng;

    await FirebaseFirestore.instance.collection('users').doc(uid).set(userData);

    try {
      await DeviceSecurityService.recordRegistration(uid, role);
    } catch (_) {}
    AppAnalyticsService.logRegisterSuccess(role: role);

    if (!mounted) return false;
    _setRegisterLoading(false);

    await FirebaseAuth.instance.signOut();

    if (!mounted) return false;
    ScaffoldMessenger.of(context).showSnackBar(
      TrakaSnackBar.success(context, Text(l10n.registerSuccess)),
    );

    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute<void>(
        builder: (_) => const AppUpdateWrapper(child: LoginScreen()),
      ),
      (route) => false,
    );
    return true;
  }

  Future<void> _onSubmit() async {
    if (!_agreeToTerms) return;
    if (!_formKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();

    final role = (widget.type == RegisterType.penumpang
            ? UserRole.penumpang
            : UserRole.driver)
        .firestoreValue;
    final name = _nameController.text.trim();
    await _onSubmitPhone(role: role, name: name);
  }

  Future<void> _onSubmitPhone({required String role, required String name}) async {
    final phone = _phoneController.text.trim();
    final password = _passwordController.text;

    if (widget.useGoogleSignUp && !_googleUserReady) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.connectGoogleFirst),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    if (phone.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            l10n.locale == AppLocale.id
                ? 'No. telepon wajib diisi'
                : 'Phone number is required',
          ),
        ),
      );
      return;
    }
    if (!widget.useGoogleSignUp && password.length < 6) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            l10n.locale == AppLocale.id
                ? 'Kata sandi minimal 6 karakter'
                : 'Password minimum 6 characters',
          ),
        ),
      );
      return;
    }

    if (!_phoneOtpSent || _phoneVerificationId == null) {
      _setRegisterLoading(true);
      await Future<void>.delayed(Duration.zero);
      await _sendPhoneOtp();
      return;
    }

    final code = _otpController.text.trim();
    if (code.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            l10n.locale == AppLocale.id
                ? 'Masukkan kode verifikasi dari SMS'
                : 'Enter verification code from SMS',
          ),
        ),
      );
      return;
    }

    _setRegisterLoading(
      true,
      overlayKind: _RegisterAuthOverlayKind.completingRegistration,
    );
    await Future<void>.delayed(Duration.zero);

    try {
      final phoneE164 = toE164(phone);
      final credential = PhoneAuthProvider.credential(
        verificationId: _phoneVerificationId!,
        smsCode: code,
      );
      if (widget.useGoogleSignUp) {
        final user = FirebaseAuth.instance.currentUser;
        if (user == null) {
          if (mounted) _setRegisterLoading(false);
          return;
        }
        try {
          await user.linkWithCredential(credential);
        } on FirebaseAuthException catch (e) {
          if (e.code == 'provider-already-linked') {
            final done = await _completeGoogleRegistrationIfAuthHasPhone(user);
            if (done) return;
          }
          if (!mounted) return;
          _setRegisterLoading(false);
          final String msg;
          if (e.code == 'credential-already-in-use') {
            msg = l10n.locale == AppLocale.id
                ? 'Nomor sudah terdaftar di akun lain. Silakan login.'
                : 'This number is registered to another account. Please sign in.';
          } else if (e.code == 'provider-already-linked') {
            msg = l10n.locale == AppLocale.id
                ? 'Nomor sudah terhubung ke sesi Google ini. Isi nama lengkap lalu coba «Kirim kode» lagi, atau buka Login.'
                : 'This number is already linked. Enter your full name and tap «Send code» again, or open Log in.';
          } else {
            msg = e.message ??
                (l10n.locale == AppLocale.id
                    ? 'Kode salah atau kedaluwarsa.'
                    : 'Invalid or expired code.');
          }
          ScaffoldMessenger.of(context).showSnackBar(
            TrakaSnackBar.error(context, Text(msg)),
          );
          return;
        } catch (_) {
          if (!mounted) return;
          _setRegisterLoading(false);
          ScaffoldMessenger.of(context).showSnackBar(
            TrakaSnackBar.warning(context, Text(
                l10n.locale == AppLocale.id
                    ? 'Nomor sudah terdaftar. Silakan login.'
                    : 'Number already registered. Please log in.',
              )),
          );
          return;
        }
        await _completeRegistration(
          user.uid,
          name: name,
          role: role,
          phoneE164: phoneE164,
          email: user.email,
        );
        return;
      }

      final authEmail = _phoneToAuthEmail(phoneE164);
      await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: authEmail,
        password: password,
      );
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        if (mounted) _setRegisterLoading(false);
        return;
      }
      try {
        await user.linkWithCredential(credential);
      } catch (_) {
        await FirebaseAuth.instance.signOut();
        if (!mounted) return;
        _setRegisterLoading(false);
        ScaffoldMessenger.of(context).showSnackBar(
          TrakaSnackBar.warning(context, Text(
              l10n.locale == AppLocale.id
                  ? 'Nomor sudah terdaftar. Silakan login.'
                  : 'Number already registered. Please login.',
            )),
        );
        return;
      }
      await _completeRegistration(
        user.uid,
        name: name,
        role: role,
        phoneE164: phoneE164,
      );
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      _setRegisterLoading(false);
      String msg = e.message ??
          (l10n.locale == AppLocale.id
              ? 'Kode salah atau kedaluwarsa.'
              : 'Invalid or expired code.');
      if (e.code == 'email-already-in-use') {
        msg = l10n.locale == AppLocale.id
            ? 'Nomor sudah terdaftar. Silakan login.'
            : 'Number already registered. Please login.';
      }
      ScaffoldMessenger.of(context).showSnackBar(
        TrakaSnackBar.error(context, Text(msg)),
      );
    } catch (e) {
      if (!mounted) return;
      _setRegisterLoading(false);
      ScaffoldMessenger.of(context).showSnackBar(
        TrakaSnackBar.error(context, Text(e.toString().replaceAll('Exception: ', ''))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final textTheme = theme.textTheme;
    final title = widget.type == RegisterType.penumpang
        ? '${l10n.penumpang} – Pendaftaran'
        : '${l10n.driver} – Pendaftaran';
    final backdrop = context.trakaVisualTokens?.screenBackdropGradient;

    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_rounded, color: cs.onSurface),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          title,
          style: textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
        ),
      ),
      resizeToAvoidBottomInset: true,
      body: Stack(
        fit: StackFit.expand,
        children: [
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: backdrop ??
                    LinearGradient(
                      colors: [cs.surface, cs.surface],
                    ),
              ),
            ),
          ),
          Positioned.fill(
            child: SafeArea(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final gap = _RegisterLayoutGap(context);
                  final hPad = context.responsive.horizontalPadding;
                  final maxFormW = math.min(440.0, constraints.maxWidth);
                  final topPad =
                      MediaQuery.paddingOf(context).top + kToolbarHeight + gap.sm;
                  final captionStyle = textTheme.bodySmall?.copyWith(
                    color: cs.onSurfaceVariant,
                    height: 1.4,
                  );

                  return SingleChildScrollView(
                    padding: EdgeInsets.fromLTRB(hPad, topPad, hPad, gap.xl),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: BoxConstraints(maxWidth: maxFormW),
                        child: Form(
                          key: _formKey,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              _RegisterWelcomeHero(
                                type: widget.type,
                                isId: l10n.locale == AppLocale.id,
                              ),
                              if (widget.useGoogleSignUp) ...[
                                SizedBox(height: gap.lg),
                                OutlinedButton.icon(
                                  onPressed: (_isLoading || _otpRequestInFlight)
                                      ? null
                                      : _signInWithGoogleForRegister,
                                  icon: _RegisterGoogleGlyph(
                                    size: context.responsive.iconSize(22),
                                  ),
                                  label: Text(
                                    _googleUserReady
                                        ? l10n.googleConnectedShort(
                                            FirebaseAuth.instance.currentUser?.email,
                                          )
                                        : l10n.connectGooglePrompt,
                                    style: textTheme.labelLarge,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  style: AppInteractionStyles.outlinedModern(
                                    primaryColor: cs.primary,
                                    outlineColor: cs.outline,
                                    foregroundColor: cs.onSurface,
                                  ),
                                ),
                              ],
                              SizedBox(height: gap.xl),
                              _RegisterTextField(
                                controller: _nameController,
                                hint: l10n.nameHint,
                                icon: Icons.person_outline,
                                validator: (v) {
                                  if (v == null || v.trim().isEmpty) {
                                    return l10n.locale == AppLocale.id
                                        ? 'Nama wajib diisi'
                                        : 'Name is required';
                                  }
                                  return null;
                                },
                              ),
                              SizedBox(height: gap.md),
                              _RegisterTextField(
                                controller: _phoneController,
                                hint: l10n.phoneHintRegister,
                                icon: Icons.phone_outlined,
                                keyboardType: TextInputType.phone,
                                suffix: _phoneOtpSent
                                    ? (_otpRequestInFlight
                                        ? Padding(
                                            padding: EdgeInsets.all(gap.xs),
                                            child: TrakaLoadingIndicator(
                                              size: context.responsive.iconSize(22),
                                              strokeWidth: 2.5,
                                              primary: cs.primary,
                                              variant:
                                                  TrakaLoadingVariant.onLightSurface,
                                            ),
                                          )
                                        : IconButton(
                                            icon: Icon(
                                              Icons.refresh_rounded,
                                              color: cs.primary,
                                              size: context.responsive.iconSize(22),
                                            ),
                                            onPressed: _sendPhoneOtp,
                                            style: IconButton.styleFrom(
                                              tapTargetSize:
                                                  MaterialTapTargetSize.shrinkWrap,
                                            ),
                                          ))
                                    : null,
                                validator: (v) {
                                  if (v == null || v.trim().isEmpty) {
                                    return l10n.locale == AppLocale.id
                                        ? 'No. telepon wajib diisi'
                                        : 'Phone number is required';
                                  }
                                  final digits = v.replaceAll(RegExp(r'\D'), '');
                                  if (digits.length < 10) {
                                    return l10n.locale == AppLocale.id
                                        ? 'Format no. telepon tidak valid'
                                        : 'Invalid phone number format';
                                  }
                                  return null;
                                },
                              ),
                              if (!widget.useGoogleSignUp) ...[
                                SizedBox(height: gap.md),
                                _RegisterTextField(
                                  controller: _passwordController,
                                  hint: l10n.passwordHintRegister,
                                  icon: Icons.lock_outline,
                                  obscureText: _obscurePassword,
                                  suffix: IconButton(
                                    icon: Icon(
                                      _obscurePassword
                                          ? Icons.visibility_off_outlined
                                          : Icons.visibility_outlined,
                                      size: context.responsive.iconSize(22),
                                      color: cs.onSurfaceVariant,
                                    ),
                                    onPressed: () => setState(
                                      () => _obscurePassword = !_obscurePassword,
                                    ),
                                  ),
                                  validator: (v) {
                                    if (v == null || v.isEmpty) {
                                      return l10n.locale == AppLocale.id
                                          ? 'Kata sandi wajib diisi'
                                          : 'Password is required';
                                    }
                                    if (v.length < 6) {
                                      return l10n.locale == AppLocale.id
                                          ? 'Minimal 6 karakter'
                                          : 'Minimum 6 characters';
                                    }
                                    return null;
                                  },
                                ),
                                SizedBox(height: gap.md),
                                _RegisterTextField(
                                  controller: _confirmPasswordController,
                                  hint: l10n.confirmPasswordHint,
                                  icon: Icons.lock_outline,
                                  obscureText: _obscureConfirmPassword,
                                  suffix: IconButton(
                                    icon: Icon(
                                      _obscureConfirmPassword
                                          ? Icons.visibility_off_outlined
                                          : Icons.visibility_outlined,
                                      size: context.responsive.iconSize(22),
                                      color: cs.onSurfaceVariant,
                                    ),
                                    onPressed: () => setState(
                                      () => _obscureConfirmPassword =
                                          !_obscureConfirmPassword,
                                    ),
                                  ),
                                  validator: (v) {
                                    if (v == null || v.isEmpty) {
                                      return l10n.locale == AppLocale.id
                                          ? 'Ulangi kata sandi wajib diisi'
                                          : 'Confirm password is required';
                                    }
                                    if (v != _passwordController.text) {
                                      return l10n.locale == AppLocale.id
                                          ? 'Kata sandi tidak sama'
                                          : 'Passwords do not match';
                                    }
                                    return null;
                                  },
                                ),
                              ],
                              if (!_phoneOtpSent) ...[
                                SizedBox(height: gap.lg),
                                FilledButton(
                                  onPressed:
                                      _otpRequestInFlight ? null : _sendPhoneOtp,
                                  style: AppInteractionStyles.authPrimaryCta(context),
                                  child: _otpRequestInFlight
                                      ? TrakaLoadingIndicator(
                                          size: 24,
                                          strokeWidth: 2.5,
                                          primary: cs.onPrimary,
                                          secondary: cs.onPrimary
                                              .withValues(alpha: 0.75),
                                          variant:
                                              TrakaLoadingVariant.onDimmedBackdrop,
                                        )
                                      : Row(
                                          mainAxisSize: MainAxisSize.min,
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
                                          children: [
                                            Text(
                                              l10n.locale == AppLocale.id
                                                  ? 'Kirim kode'
                                                  : 'Send code',
                                              style:
                                                  AppInteractionStyles.authCtaLabelStyle,
                                            ),
                                            SizedBox(width: gap.sm),
                                            Icon(
                                              Icons.arrow_forward_rounded,
                                              size: context.responsive.iconSize(22),
                                              color: cs.onPrimary,
                                            ),
                                          ],
                                        ),
                                ),
                                SizedBox(height: gap.md),
                                DecoratedBox(
                                  decoration: BoxDecoration(
                                    color: cs.surfaceContainerHighest
                                        .withValues(alpha: 0.65),
                                    borderRadius:
                                        BorderRadius.circular(AppTheme.radiusMd),
                                    border: Border.all(
                                      color: cs.outlineVariant.withValues(
                                        alpha: 0.55,
                                      ),
                                    ),
                                  ),
                                  child: Padding(
                                    padding: EdgeInsets.all(gap.md),
                                    child: Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Icon(
                                          Icons.info_outline_rounded,
                                          size: context.responsive.iconSize(20),
                                          color: cs.primary,
                                        ),
                                        SizedBox(width: gap.sm),
                                        Expanded(
                                          child: Text(
                                            l10n.registerPhoneOtpRecaptchaHint,
                                            style: captionStyle,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                              if (_phoneOtpSent) ...[
                                SizedBox(height: gap.lg),
                                _RegisterTextField(
                                  controller: _otpController,
                                  hint: l10n.verificationCodeHint,
                                  icon: Icons.sms_outlined,
                                  keyboardType: TextInputType.number,
                                  validator: (v) {
                                    if (!_phoneOtpSent) return null;
                                    if (v == null || v.trim().isEmpty) {
                                      return l10n.locale == AppLocale.id
                                          ? 'Kode verifikasi wajib diisi'
                                          : 'Verification code is required';
                                    }
                                    return null;
                                  },
                                ),
                              ],
                              SizedBox(height: gap.lg),
                              Divider(
                                height: 1,
                                thickness: 1,
                                color: cs.outlineVariant.withValues(alpha: 0.65),
                              ),
                              SizedBox(height: gap.md),
                              _TermsCheckbox(
                                value: _agreeToTerms,
                                onChanged: (v) =>
                                    setState(() => _agreeToTerms = v ?? false),
                                onTermsTap: _openTerms,
                                onPrivacyTap: _openPrivacy,
                                label: l10n.agreeTerms,
                                termsLabel: l10n.termsOfService,
                                privacyLabel: l10n.privacyPolicy,
                              ),
                              SizedBox(height: gap.lg),
                              FilledButton(
                                onPressed: (_isLoading || _otpRequestInFlight)
                                    ? null
                                    : () {
                                        if (!_phoneOtpSent) {
                                          ScaffoldMessenger.of(context)
                                              .showSnackBar(
                                            SnackBar(
                                              content: Text(
                                                l10n.locale == AppLocale.id
                                                    ? 'Tekan «Kirim kode», lalu isi kode SMS di atas.'
                                                    : 'Tap «Send code», then enter the SMS code above.',
                                              ),
                                              behavior: SnackBarBehavior.floating,
                                            ),
                                          );
                                          return;
                                        }
                                        if (!_agreeToTerms) {
                                          ScaffoldMessenger.of(context)
                                              .showSnackBar(
                                            SnackBar(
                                              content: Text(
                                                l10n.locale == AppLocale.id
                                                    ? 'Centang persyaratan dan kebijakan privasi terlebih dahulu.'
                                                    : 'Please accept the terms and privacy policy first.',
                                              ),
                                              behavior: SnackBarBehavior.floating,
                                            ),
                                          );
                                          return;
                                        }
                                        _onSubmit();
                                      },
                                style: AppInteractionStyles.registerTermsSubmit(
                                  context,
                                  agreeToTerms: _agreeToTerms && _phoneOtpSent,
                                ),
                                child: _isLoading
                                    ? TrakaLoadingIndicator(
                                        size: 24,
                                        strokeWidth: 2.5,
                                        primary: cs.onPrimary,
                                        secondary:
                                            cs.onPrimary.withValues(alpha: 0.72),
                                        variant:
                                            TrakaLoadingVariant.onDimmedBackdrop,
                                      )
                                    : Text(
                                        widget.type == RegisterType.driver
                                            ? l10n.submitButton
                                            : l10n.registerFormSubmitButton,
                                        style:
                                            AppInteractionStyles.authCtaLabelStyle,
                                      ),
                              ),
                              SizedBox(height: gap.xl),
                              OutlinedButton.icon(
                                onPressed: () => Navigator.of(context).pop(),
                                icon: Icon(
                                  Icons.arrow_back_rounded,
                                  size: context.responsive.iconSize(20),
                                ),
                                label: Text(l10n.backToLogin),
                                style: AppInteractionStyles.outlinedFromTheme(
                                  context,
                                  padding: EdgeInsets.symmetric(
                                    vertical: gap.sm,
                                  ),
                                  sideColor: cs.primary,
                                ),
                              ),
                              SizedBox(height: gap.md),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
          AuthLoadingOverlay(
            visible: _isLoading && !_otpRequestInFlight,
            opaqueBackdrop: true,
            message: _registerAuthOverlayMessage(),
          ),
        ],
      ),
    );
  }
}

/// Ikon pengenal Google untuk tombol sambung (gambar resmi; fallback jaringan gagal).
class _RegisterGoogleGlyph extends StatelessWidget {
  const _RegisterGoogleGlyph({this.size = 22});

  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: Image.network(
        'https://www.google.com/images/branding/googleg/1x/googleg_standard_color_128dp.png',
        fit: BoxFit.contain,
        errorBuilder: (context, error, stackTrace) => Icon(
          Icons.account_circle_outlined,
          size: size,
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
    );
  }
}

/// Ilustrasi ringan di atas form: masuk halus + denyut ikon (tanpa dependensi ekstra).
class _RegisterWelcomeHero extends StatefulWidget {
  const _RegisterWelcomeHero({
    required this.type,
    required this.isId,
  });

  final RegisterType type;
  final bool isId;

  @override
  State<_RegisterWelcomeHero> createState() => _RegisterWelcomeHeroState();
}

class _RegisterWelcomeHeroState extends State<_RegisterWelcomeHero>
    with TickerProviderStateMixin {
  late AnimationController _entrance;
  late AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _entrance = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 780),
    )..forward();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2600),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _entrance.dispose();
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isPassenger = widget.type == RegisterType.penumpang;
    final title = widget.isId
        ? (isPassenger ? 'Bergabung sebagai penumpang' : 'Bergabung sebagai driver')
        : (isPassenger ? 'Join as a passenger' : 'Join as a driver');
    final subtitle = widget.isId
        ? 'Lengkapi langkah di bawah — cepat dan aman.'
        : 'Complete the steps below — quick and secure.';

    final pulseScale = Tween<double>(begin: 0.96, end: 1.04).animate(
      CurvedAnimation(parent: _pulse, curve: Curves.easeInOut),
    );
    final entranceFade = CurvedAnimation(
      parent: _entrance,
      curve: const Interval(0.0, 0.55, curve: Curves.easeOut),
    );
    final entranceSlide = Tween<Offset>(
      begin: const Offset(0, 0.12),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(parent: _entrance, curve: Curves.easeOutCubic),
    );

    return FadeTransition(
      opacity: entranceFade,
      child: SlideTransition(
        position: entranceSlide,
        child: RepaintBoundary(
          child: Column(
            children: [
              ScaleTransition(
                scale: pulseScale,
                child: Container(
                  padding: const EdgeInsets.all(22),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      colors: [
                        cs.primary.withValues(alpha: 0.14),
                        AppTheme.primaryLight.withValues(alpha: 0.1),
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    border: Border.all(
                      color: cs.primary.withValues(alpha: 0.28),
                      width: 1.25,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: cs.primary.withValues(alpha: 0.22),
                        blurRadius: 24,
                        offset: const Offset(0, 10),
                        spreadRadius: -6,
                      ),
                    ],
                  ),
                  child: Icon(
                    isPassenger ? Icons.hail_rounded : Icons.local_taxi_rounded,
                    size: 44,
                    color: cs.primary,
                  ),
                ),
              ),
              SizedBox(height: context.responsive.spacing(16)),
              Text(
                title,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.2,
                      color: cs.onSurface,
                      height: 1.25,
                    ),
              ),
              SizedBox(height: context.responsive.spacing(6)),
              Text(
                subtitle,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: cs.onSurfaceVariant,
                      height: 1.4,
                      fontWeight: FontWeight.w500,
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Field pendaftaran — selaras [InputDecorationTheme] aplikasi (outline, radius).
class _RegisterTextField extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final IconData icon;
  final bool obscureText;
  final Widget? suffix;
  final TextInputType? keyboardType;
  final String? Function(String?)? validator;

  const _RegisterTextField({
    required this.controller,
    required this.hint,
    required this.icon,
    this.obscureText = false,
    this.suffix,
    this.keyboardType,
    this.validator,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final defaults = theme.inputDecorationTheme;
    return TextFormField(
      controller: controller,
      obscureText: obscureText,
      keyboardType: keyboardType,
      autocorrect: false,
      enableSuggestions: false,
      validator: validator,
      style: theme.textTheme.bodyLarge,
      cursorColor: cs.primary,
      decoration: InputDecoration(
        hintText: hint,
        prefixIcon: Icon(
          icon,
          size: context.responsive.iconSize(22),
          color: cs.onSurfaceVariant,
        ),
        suffixIcon: suffix,
      ).applyDefaults(defaults),
    );
  }
}

class _TermsCheckbox extends StatelessWidget {
  final bool value;
  final ValueChanged<bool?> onChanged;
  final VoidCallback onTermsTap;
  final VoidCallback onPrivacyTap;
  final String label;
  final String termsLabel;
  final String privacyLabel;

  const _TermsCheckbox({
    required this.value,
    required this.onChanged,
    required this.onTermsTap,
    required this.onPrivacyTap,
    required this.label,
    required this.termsLabel,
    required this.privacyLabel,
  });

  @override
  Widget build(BuildContext context) {
    // "I agree with the " [Terms of Service] " and " [Privacy Policy] "."
    final parts = label.split(termsLabel);
    final beforeTerms = parts.isNotEmpty ? parts[0] : label;
    final afterTerms = parts.length > 1 ? parts[1] : '';
    final andParts = afterTerms.split(privacyLabel);
    final between = andParts.isNotEmpty ? andParts[0] : '';
    final afterPrivacy = andParts.length > 1 ? andParts[1] : '';

    final cs = Theme.of(context).colorScheme;
    final baseStyle = Theme.of(context).textTheme.bodySmall?.copyWith(
          color: cs.onSurfaceVariant,
          height: 1.45,
        );
    final linkStyle = Theme.of(context).textTheme.bodySmall?.copyWith(
          color: cs.primary,
          fontWeight: FontWeight.w600,
          decoration: TextDecoration.underline,
          decorationColor: cs.primary,
          height: 1.45,
        );

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: SizedBox(
            width: 24,
            height: 24,
            child: Checkbox(
              value: value,
              onChanged: onChanged,
              activeColor: cs.primary,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppTheme.radiusXs),
              ),
              side: BorderSide(color: cs.outline),
            ),
          ),
        ),
        SizedBox(width: AppTheme.spacingSm),
        Expanded(
          child: Wrap(
            alignment: WrapAlignment.start,
            runSpacing: 4,
            spacing: 2,
            children: [
              Text(beforeTerms, style: baseStyle),
              GestureDetector(
                onTap: onTermsTap,
                child: Text(termsLabel, style: linkStyle),
              ),
              Text(between, style: baseStyle),
              GestureDetector(
                onTap: onPrivacyTap,
                child: Text(privacyLabel, style: linkStyle),
              ),
              Text(afterPrivacy, style: baseStyle),
            ],
          ),
        ),
      ],
    );
  }
}
