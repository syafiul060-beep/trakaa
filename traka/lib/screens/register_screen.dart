import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'login_screen.dart';
import 'driver_screen.dart';
import 'penumpang_screen.dart';
import '../widgets/app_update_wrapper.dart';

import '../l10n/app_localizations.dart';
import '../services/locale_service.dart';
import '../services/account_deletion_service.dart';
import '../services/app_analytics_service.dart';
import '../services/device_security_service.dart';
import '../services/fcm_service.dart';
import '../services/voice_call_incoming_service.dart';
import '../theme/app_theme.dart';
import '../theme/responsive.dart';
import '../services/fake_gps_overlay_service.dart';
import '../services/location_service.dart';
import '../models/user_role.dart';
import '../utils/app_logger.dart';
import '../utils/phone_utils.dart';
import 'privacy_screen.dart';
import 'terms_screen.dart';

/// Tipe pendaftaran: Penumpang atau Driver.
enum RegisterType { penumpang, driver }

class RegisterScreen extends StatefulWidget {
  final RegisterType type;

  const RegisterScreen({super.key, required this.type});

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
  bool _phoneOtpSent = false;
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  String? _phoneVerificationId;

  AppLocalizations get l10n => AppLocalizations(locale: LocaleService.current);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _checkDeviceAndBlockIfNeeded();
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
        const SnackBar(
          content: Text(
            'Izin lokasi diperlukan untuk menggunakan aplikasi Traka.',
            textAlign: TextAlign.center,
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
          margin: EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          duration: Duration(seconds: 4),
        ),
      );
      Navigator.of(context).pop();
    }
  }

  /// Cek device: jika perangkat sudah terdaftar (penumpang/driver), langsung ke halaman login dan tampilkan notifikasi.
  Future<void> _checkDeviceAndBlockIfNeeded() async {
    final role = (widget.type == RegisterType.penumpang
            ? UserRole.penumpang
            : UserRole.driver)
        .firestoreValue;
    final result = await DeviceSecurityService.checkRegistrationAllowed(role);
    if (!mounted) return;
    if (!result.allowed) {
      final message =
          result.message ??
          (l10n.locale == AppLocale.id
              ? 'Perangkat sudah digunakan oleh $role. Silakan login.'
              : 'Device already in use by $role. Please login.');
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

    setState(() => _isLoading = true);
    // Cek apakah nomor sudah terdaftar (untuk UX: arahkan ke Login)
    try {
      final callable = FirebaseFunctions.instance.httpsCallable('checkPhoneExists');
      final result = await callable.call({'phone': phoneE164});
      final data = result.data as Map<String, dynamic>?;
      final exists = data?['exists'] as bool? ?? false;
      if (exists && mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              l10n.locale == AppLocale.id
                  ? 'Nomor sudah terdaftar. Silakan login.'
                  : 'Number already registered. Please login.',
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            backgroundColor: Colors.orange,
            behavior: SnackBarBehavior.floating,
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            duration: const Duration(seconds: 4),
          ),
        );
        return;
      }
    } catch (e) {
      logError('RegisterScreen.checkPhoneExists', e, null);
    }

    await FirebaseAuth.instance.verifyPhoneNumber(
      phoneNumber: phoneE164,
      verificationCompleted: (PhoneAuthCredential credential) async {
        if (!mounted) return;
        final password = _passwordController.text;
        if (password.length < 6) return;
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
            setState(() => _isLoading = false);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(e.toString().replaceAll('Exception: ', '')),
                backgroundColor: Colors.red,
              ),
            );
          }
        }
      },
      verificationFailed: (FirebaseAuthException e) {
        if (!mounted) return;
        setState(() => _isLoading = false);
        String message = l10n.locale == AppLocale.id
            ? 'Verifikasi gagal. Coba lagi.'
            : 'Verification failed. Try again.';
        final code = e.code;
        final msg = (e.message ?? '').toLowerCase();
        if (code == 'missing-client-identifier' ||
            msg.contains('app identifier') ||
            msg.contains('play integrity') ||
            msg.contains('recaptcha')) {
          message = l10n.locale == AppLocale.id
              ? 'Perangkat/aplikasi belum terverifikasi. Tambahkan SHA-1 di Firebase Console dan coba di HP asli.'
              : 'App not verified. Add SHA-1 in Firebase Console and try on real device.';
        } else if (msg.contains('blocked') || msg.contains('unusual activity')) {
          message = l10n.locale == AppLocale.id
              ? 'Perangkat ini sementara diblokir. Tunggu beberapa jam lalu coba lagi.'
              : 'Device temporarily blocked. Try again in a few hours.';
        } else if (e.message != null && e.message!.isNotEmpty) {
          message = e.message!;
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 5),
          ),
        );
      },
      codeSent: (String verificationId, int? resendToken) {
        if (!mounted) return;
        setState(() {
          _phoneVerificationId = verificationId;
          _phoneOtpSent = true;
          _isLoading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              l10n.locale == AppLocale.id
                  ? 'Kode verifikasi telah dikirim ke $phoneE164'
                  : 'Verification code sent to $phoneE164',
            ),
            backgroundColor: Colors.green,
          ),
        );
      },
      codeAutoRetrievalTimeout: (_) {},
    );
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
  Future<void> _completeRegistration(
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
        if (!mounted) return;
        final confirm = await _showCancelDeletionDialog();
        if (!mounted || confirm != true) {
          setState(() => _isLoading = false);
          await FirebaseAuth.instance.signOut();
          return;
        }
        await AccountDeletionService.cancelAccountDeletion(uid);
        await DeviceSecurityService.recordRegistration(uid, role);
        if (!mounted) return;
        setState(() => _isLoading = false);
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
        return;
      }
      // User sudah terdaftar, arahkan ke login
      await FirebaseAuth.instance.signOut();
      if (!mounted) return;
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            l10n.locale == AppLocale.id
                ? 'Akun sudah terdaftar. Silakan login.'
                : 'Account already registered. Please login.',
          ),
          backgroundColor: Colors.orange,
        ),
      );
      Navigator.of(context).pop();
      return;
    }

    // Cek device + lokasi paralel agar lebih cepat
    final results = await Future.wait([
      DeviceSecurityService.checkRegistrationAllowed(role),
      LocationService.getDriverLocationResult(),
    ]);
    final securityResult = results[0] as DeviceSecurityResult;
    final locationResult = results[1] as DriverLocationResult;

    if (!securityResult.allowed) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            securityResult.message ?? 'Registrasi tidak diperbolehkan.',
            textAlign: TextAlign.center,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          duration: const Duration(seconds: 4),
        ),
      );
      return;
    }
    if (locationResult.errorMessage != null) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      if (locationResult.isFakeGpsDetected) {
        FakeGpsOverlayService.showOverlay();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              locationResult.errorMessage!,
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            duration: const Duration(seconds: 5),
          ),
        );
      }
      return;
    }
    if (!locationResult.isInIndonesia) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            l10n.trakaIndonesiaOnly,
            textAlign: TextAlign.center,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          duration: const Duration(seconds: 4),
        ),
      );
      return;
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

    if (!mounted) return;
    setState(() => _isLoading = false);

    await FirebaseAuth.instance.signOut();

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(l10n.registerSuccess),
        backgroundColor: Colors.green,
      ),
    );

    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute<void>(
        builder: (_) => const AppUpdateWrapper(child: LoginScreen()),
      ),
      (route) => false,
    );
  }

  Future<void> _onSubmit() async {
    if (!_agreeToTerms) return;
    if (!_formKey.currentState!.validate()) return;

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
    if (password.length < 6) {
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

    setState(() => _isLoading = true);

    try {
      final phoneE164 = toE164(phone);
      final authEmail = _phoneToAuthEmail(phoneE164);
      final credential = PhoneAuthProvider.credential(
        verificationId: _phoneVerificationId!,
        smsCode: code,
      );
      await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: authEmail,
        password: password,
      );
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        if (mounted) setState(() => _isLoading = false);
        return;
      }
      try {
        await user.linkWithCredential(credential);
      } catch (_) {
        await FirebaseAuth.instance.signOut();
        if (!mounted) return;
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              l10n.locale == AppLocale.id
                  ? 'Nomor sudah terdaftar. Silakan login.'
                  : 'Number already registered. Please login.',
            ),
            backgroundColor: Colors.orange,
          ),
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
      setState(() => _isLoading = false);
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
        SnackBar(content: Text(msg), backgroundColor: Colors.red),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.toString().replaceAll('Exception: ', '')),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.type == RegisterType.penumpang
        ? '${l10n.penumpang} – Pendaftaran'
        : '${l10n.driver} – Pendaftaran';

    return Scaffold(
      appBar: AppBar(
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          title,
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurface,
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.symmetric(horizontal: context.responsive.horizontalPadding),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(height: context.responsive.spacing(16)),
                _RegisterUnderlineField(
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
                SizedBox(height: context.responsive.spacing(20)),
                _RegisterUnderlineField(
                  controller: _phoneController,
                  hint: l10n.phoneHintRegister,
                  icon: Icons.phone_outlined,
                  keyboardType: TextInputType.phone,
                  suffix: _phoneOtpSent
                      ? (_isLoading
                          ? const Padding(
                              padding: EdgeInsets.all(8.0),
                              child: SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              ),
                            )
                          : IconButton(
                              icon: Icon(
                                Icons.refresh,
                                color: Theme.of(context).colorScheme.primary,
                                size: 22,
                              ),
                              onPressed: _sendPhoneOtp,
                              splashRadius: 24,
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
                if (!_phoneOtpSent) ...[
                  SizedBox(height: context.responsive.spacing(12)),
                  FilledButton(
                    onPressed: _isLoading ? null : _sendPhoneOtp,
                    style: FilledButton.styleFrom(
                      backgroundColor: Theme.of(context).colorScheme.primary,
                      foregroundColor: Theme.of(context).colorScheme.onPrimary,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppTheme.radiusXs),
                      ),
                    ),
                    child: _isLoading
                        ? SizedBox(
                            height: 22,
                            width: 22,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Theme.of(context).colorScheme.onPrimary,
                            ),
                          )
                        : Row(
                            mainAxisSize: MainAxisSize.min,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                l10n.locale == AppLocale.id ? 'Kirim kode' : 'Send code',
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Icon(
                                Icons.arrow_forward,
                                size: 20,
                                color: Theme.of(context).colorScheme.onPrimary,
                              ),
                            ],
                          ),
                  ),
                ],
                SizedBox(height: context.responsive.spacing(20)),
                _RegisterUnderlineField(
                  controller: _passwordController,
                  hint: l10n.passwordHintRegister,
                  icon: Icons.lock_outline,
                  obscureText: _obscurePassword,
                  suffix: IconButton(
                    icon: Icon(
                      _obscurePassword ? Icons.visibility_off : Icons.visibility,
                      size: 22,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                    onPressed: () =>
                        setState(() => _obscurePassword = !_obscurePassword),
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
                SizedBox(height: context.responsive.spacing(20)),
                _RegisterUnderlineField(
                  controller: _confirmPasswordController,
                  hint: l10n.confirmPasswordHint,
                  icon: Icons.lock_outline,
                  obscureText: _obscureConfirmPassword,
                  suffix: IconButton(
                    icon: Icon(
                      _obscureConfirmPassword ? Icons.visibility_off : Icons.visibility,
                      size: 22,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                    onPressed: () =>
                        setState(() => _obscureConfirmPassword = !_obscureConfirmPassword),
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
                if (_phoneOtpSent) ...[
                  SizedBox(height: context.responsive.spacing(20)),
                  _RegisterUnderlineField(
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
                const SizedBox(height: 24),
                // Tombol Ajukan – hijau bila agree, abu-abu bila belum
                FilledButton(
                  onPressed: _agreeToTerms && !_isLoading ? _onSubmit : null,
                  style: FilledButton.styleFrom(
                    backgroundColor: _agreeToTerms
                        ? const Color(0xFF22C55E) // Hijau saat setuju terms
                        : Theme.of(context).colorScheme.onSurfaceVariant,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: _isLoading
                      ? const SizedBox(
                          height: 22,
                          width: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : Text(
                          _phoneOtpSent
                              ? l10n.submitButton
                              : (l10n.locale == AppLocale.id
                                  ? 'Kirim kode'
                                  : 'Send code'),
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                ),
                const SizedBox(height: 16),
                // Checkbox + Terms & Privacy (klikabel)
                _TermsCheckbox(
                  value: _agreeToTerms,
                  onChanged: (v) => setState(() => _agreeToTerms = v ?? false),
                  onTermsTap: _openTerms,
                  onPrivacyTap: _openPrivacy,
                  label: l10n.agreeTerms,
                  termsLabel: l10n.termsOfService,
                  privacyLabel: l10n.privacyPolicy,
                ),
                const SizedBox(height: 32),
                OutlinedButton.icon(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.arrow_back, size: 18),
                  label: Text(l10n.backToLogin),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Theme.of(context).colorScheme.primary,
                    side: BorderSide(color: Theme.of(context).colorScheme.primary),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RegisterUnderlineField extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final IconData icon;
  final bool obscureText;
  final Widget? suffix;
  final TextInputType? keyboardType;
  final String? Function(String?)? validator;

  const _RegisterUnderlineField({
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
    return TextFormField(
      controller: controller,
      obscureText: obscureText,
      keyboardType: keyboardType,
      validator: validator,
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 14),
        prefixIcon: Icon(icon, size: 22, color: Theme.of(context).colorScheme.onSurfaceVariant),
        suffixIcon: suffix,
        border: UnderlineInputBorder(
          borderSide: BorderSide(color: Theme.of(context).colorScheme.outline),
        ),
        enabledBorder: UnderlineInputBorder(
          borderSide: BorderSide(color: Theme.of(context).colorScheme.outline),
        ),
        focusedBorder: UnderlineInputBorder(
          borderSide: BorderSide(color: Theme.of(context).colorScheme.primary, width: 1.5),
        ),
        errorBorder: const UnderlineInputBorder(
          borderSide: BorderSide(color: Colors.red),
        ),
      ),
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

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 24,
          width: 24,
          child: Checkbox(
            value: value,
            onChanged: onChanged,
            activeColor: Theme.of(context).colorScheme.primary,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(4),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Wrap(
            alignment: WrapAlignment.start,
            runSpacing: 2,
            children: [
              Text(
                beforeTerms,
                style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 13),
              ),
              GestureDetector(
                onTap: onTermsTap,
                child: Text(
                  termsLabel,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.primary,
                    fontSize: 13,
                    decoration: TextDecoration.underline,
                  ),
                ),
              ),
              Text(
                between,
                style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 13),
              ),
              GestureDetector(
                onTap: onPrivacyTap,
                child: Text(
                  privacyLabel,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.primary,
                    fontSize: 13,
                    decoration: TextDecoration.underline,
                  ),
                ),
              ),
              Text(
                afterPrivacy,
                style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 13),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
