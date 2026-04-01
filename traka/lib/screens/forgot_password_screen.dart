import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:face_verification/face_verification.dart';

import '../services/verification_log_service.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../theme/responsive.dart';
import '../theme/traka_visual_tokens.dart';
import '../widgets/auth_loading_overlay.dart';
import '../widgets/traka_loading_indicator.dart';
import '../utils/phone_utils.dart';
import '../utils/phone_verification_snackbar.dart';
import '../theme/traka_snackbar.dart';
import '../l10n/app_localizations.dart';
import '../services/locale_service.dart';
import '../widgets/traka_l10n_scope.dart';
import '../services/biometric_login_service.dart';
import '../services/device_service.dart';
import '../services/permission_service.dart';
import '../utils/app_logger.dart';
import 'active_liveness_screen.dart';

/// Langkah alur lupa kata sandi.
enum _ForgotStep {
  chooseMethod,
  emailInput,
  emailOtpSent,
  phoneInput,
  phoneOtpSent,
  faceVerify,
  newPassword,
  done,
}

/// Lupa kata sandi: pilih email/telp → verifikasi OTP → verifikasi wajah → password baru.
/// Device ID dibaca dan di-update di Firestore jika berbeda setelah reset berhasil.
class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  _ForgotStep _step = _ForgotStep.chooseMethod;

  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _otpController = TextEditingController();
  final _newPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  bool _loading = false;
  String? _phoneVerificationId;
  String? _resetUid; // UID setelah sign in dengan phone (untuk face + update password)
  bool _faceVerifyBusy = false;
  String? _faceVerifyLastError;

  /// Foto acuan: Storage path utama, lalu URL di Firestore (download URL) jika perlu.
  Future<List<int>?> _loadFaceReferenceBytes(String uid) async {
    try {
      final ref =
          FirebaseStorage.instance.ref().child('users/$uid/face_verification.jpg');
      final maxBytes = 15 * 1024 * 1024;
      final bytes = await ref.getData(maxBytes);
      if (bytes != null && bytes.isNotEmpty) return bytes;
    } catch (e, st) {
      logError('ForgotPassword.loadFaceRef.storage', e, st);
    }
    try {
      final doc =
          await FirebaseFirestore.instance.collection('users').doc(uid).get();
      final url = (doc.data()?['faceVerificationUrl'] as String?)?.trim();
      if (url == null || url.isEmpty) return null;
      final resp = await http
          .get(Uri.parse(url))
          .timeout(const Duration(seconds: 30));
      if (resp.statusCode == 200 && resp.bodyBytes.isNotEmpty) {
        return resp.bodyBytes;
      }
    } catch (e, st) {
      logError('ForgotPassword.loadFaceRef.url', e, st);
    }
    return null;
  }

  @override
  void dispose() {
    _emailController.dispose();
    _phoneController.dispose();
    _otpController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _onChooseEmail() async {
    setState(() => _step = _ForgotStep.emailInput);
  }

  Future<void> _onChoosePhone() async {
    setState(() => _step = _ForgotStep.phoneInput);
  }

  Future<void> _sendEmailOtp() async {
    final email = _emailController.text.trim().toLowerCase();
    if (email.isEmpty) {
      _showSnack(TrakaL10n.of(context).emailRequired, isError: true);
      return;
    }
    setState(() => _loading = true);
    try {
      final callable = FirebaseFunctions.instance.httpsCallable('requestForgotPasswordCode');
      await callable.call({'email': email});
      if (!mounted) return;
      setState(() {
        _loading = false;
        _step = _ForgotStep.emailOtpSent;
      });
      _showSnack(TrakaL10n.of(context).codeSentToEmail);
    } on FirebaseFunctionsException catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      final msg = e.message ?? e.code;
      if (e.code == 'not-found') {
        _showSnack(TrakaL10n.of(context).emailNotRegistered, isError: true);
      } else {
        _showSnack(msg, isError: true);
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
      _showSnack(TrakaL10n.of(context).failedToSendCode, isError: true);
    }
  }

  Future<void> _verifyEmailOtpAndContinue() async {
    final email = _emailController.text.trim().toLowerCase();
    final code = _otpController.text.trim();
    if (email.isEmpty || code.isEmpty) {
      _showSnack(TrakaL10n.of(context).enterCodeFromEmail, isError: true);
      return;
    }
    setState(() => _loading = true);
    try {
      final callable = FirebaseFunctions.instance.httpsCallable('verifyForgotPasswordOtpAndGetToken');
      final result = await callable.call({'email': email, 'code': code});
      final customToken = result.data['customToken'] as String?;
      if (customToken == null || customToken.isEmpty) throw Exception('Token tidak diterima');
      await FirebaseAuth.instance.signInWithCustomToken(customToken);
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) {
        if (mounted) setState(() => _loading = false);
        if (mounted) {
          _showSnack(TrakaL10n.of(context).verificationFailed, isError: true);
        }
        return;
      }
      if (!mounted) return;
      setState(() {
        _resetUid = uid;
        _step = _ForgotStep.faceVerify;
        _loading = false;
        _faceVerifyBusy = true;
        _faceVerifyLastError = null;
      });
      await _runFaceVerification(uid);
    } on FirebaseFunctionsException catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      if (!mounted) return;
      _showSnack(e.message ?? 'Kode salah atau kedaluwarsa.', isError: true);
    } catch (_) {
      if (mounted) setState(() => _loading = false);
      if (!mounted) return;
      _showSnack(TrakaL10n.of(context).wrongOrExpiredCode, isError: true);
    }
  }

  Future<void> _sendPhoneOtp() async {
    final phone = _phoneController.text.trim();
    if (phone.isEmpty) {
      _showSnack(TrakaL10n.of(context).phoneRequired, isError: true);
      return;
    }
    final phoneE164 = toE164(phone);
    setState(() => _loading = true);
    try {
      final callable = FirebaseFunctions.instance.httpsCallable('checkPhoneExists');
      final result = await callable.call({'phone': phoneE164});
      final data = result.data as Map<String, dynamic>?;
      final exists = data?['exists'] as bool? ?? false;
      if (!exists) {
        if (!mounted) return;
        setState(() => _loading = false);
        _showSnack(TrakaL10n.of(context).phoneNotRegistered, isError: true);
        return;
      }
      await FirebaseAuth.instance.verifyPhoneNumber(
        phoneNumber: phoneE164,
        verificationCompleted: (PhoneAuthCredential credential) async {
          if (!mounted) return;
          await _onPhoneVerified(credential);
        },
        verificationFailed: (FirebaseAuthException e) {
          if (!mounted) return;
          setState(() => _loading = false);
          final l10n = AppLocalizations(locale: LocaleService.current);
          showPhoneVerificationFailedSnackBar(
            context,
            exception: e,
            analyticsSource: 'forgot_password_phone',
            l10n: l10n,
          );
        },
        codeSent: (String verificationId, int? resendToken) {
          if (!mounted) return;
          setState(() {
            _phoneVerificationId = verificationId;
            _step = _ForgotStep.phoneOtpSent;
            _loading = false;
          });
          _showSnack('Kode verifikasi telah dikirim ke $phoneE164');
        },
        codeAutoRetrievalTimeout: (_) {},
      );
    } catch (e) {
      if (mounted) setState(() => _loading = false);
      _showSnack('Gagal. Coba lagi.', isError: true);
    }
  }

  Future<void> _onPhoneVerified(PhoneAuthCredential credential) async {
    try {
      final userCredential = await FirebaseAuth.instance.signInWithCredential(credential);
      final uid = userCredential.user?.uid;
      if (uid == null || !mounted) return;
      setState(() {
        _resetUid = uid;
        _step = _ForgotStep.faceVerify;
        _loading = false;
        _faceVerifyBusy = true;
        _faceVerifyLastError = null;
      });
      await _runFaceVerification(uid);
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
      if (!mounted) return;
      _showSnack(TrakaL10n.of(context).phoneNotLinkedToAccount, isError: true);
    }
  }

  Future<void> _verifyOtpAndContinue() async {
    final code = _otpController.text.trim();
    if (code.isEmpty || _phoneVerificationId == null) {
      _showSnack(TrakaL10n.of(context).enterCodeFromSms, isError: true);
      return;
    }
    setState(() => _loading = true);
    try {
      final credential = PhoneAuthProvider.credential(
        verificationId: _phoneVerificationId!,
        smsCode: code,
      );
      await _onPhoneVerified(credential);
    } catch (_) {
      if (mounted) setState(() => _loading = false);
      if (!mounted) return;
      _showSnack(TrakaL10n.of(context).wrongOrExpiredCode, isError: true);
    }
  }

  Future<void> _runFaceVerification(String uid) async {
    if (!mounted) return;
    setState(() {
      _faceVerifyBusy = true;
      _faceVerifyLastError = null;
    });
    File? tempStored;
    try {
      final rawBytes = await _loadFaceReferenceBytes(uid);
      if (rawBytes == null || rawBytes.isEmpty) {
        if (!mounted) return;
        setState(() {
          _faceVerifyBusy = false;
          _faceVerifyLastError = TrakaL10n.of(context).faceDataNotFound;
        });
        _showSnack(TrakaL10n.of(context).faceDataNotFound, isError: true);
        return;
      }
      final tempDir = await getTemporaryDirectory();
      tempStored = File('${tempDir.path}/reset_verify_$uid.jpg');
      await tempStored.writeAsBytes(rawBytes);
      try {
        await FaceVerification.instance.registerFromImagePath(
          id: uid,
          imagePath: tempStored.path,
          imageId: 'reset_verify',
        );
      } catch (e, st) {
        logError('ForgotPassword.registerFromImagePath', e, st);
        VerificationLogService.log(
          userId: uid,
          success: false,
          source: VerificationLogSource.forgotPassword,
          errorMessage: 'Gagal memuat template wajah: $e',
        );
        if (!mounted) return;
        setState(() {
          _faceVerifyBusy = false;
          _faceVerifyLastError = kDebugMode
              ? 'Gagal memproses foto acuan: $e'
              : 'Gagal memproses foto acuan. Ketuk Coba lagi atau hubungi support.';
        });
        _showSnack(TrakaL10n.of(context).faceVerificationFailed, isError: true);
        return;
      }

      if (!mounted) return;
      final cameraOk = await PermissionService.requestCameraPermission(context);
      if (!cameraOk) {
        if (mounted) {
          setState(() {
            _faceVerifyBusy = false;
            _faceVerifyLastError =
                TrakaL10n.of(context).cameraPermissionRequired;
          });
          _showSnack(TrakaL10n.of(context).cameraPermissionRequired, isError: true);
        }
        return;
      }
      if (!mounted) return;
      setState(() => _faceVerifyBusy = false);
      final file = await Navigator.of(context).push<File>(
        MaterialPageRoute<File>(builder: (_) => const ActiveLivenessScreen()),
      );
      if (!mounted) return;
      if (file == null || file.path.isEmpty) {
        setState(() {
          _faceVerifyLastError =
              TrakaL10n.of(context).faceVerificationCancelled;
        });
        _showSnack(TrakaL10n.of(context).faceVerificationCancelled, isError: true);
        return;
      }
      setState(() => _faceVerifyBusy = true);
      final matchId = await FaceVerification.instance.verifyFromImagePath(
        imagePath: file.path,
        threshold: 0.7,
        staffId: uid,
      );
      try {
        FaceVerification.instance.deleteRecord(uid);
      } catch (_) {}
      final verified = matchId == uid;
      VerificationLogService.log(
        userId: uid,
        success: verified,
        source: VerificationLogSource.forgotPassword,
        errorMessage: verified ? null : 'Wajah tidak cocok.',
      );
      if (!mounted) return;
      setState(() => _faceVerifyBusy = false);
      if (verified) {
        setState(() => _step = _ForgotStep.newPassword);
      } else {
        setState(() {
          _faceVerifyLastError =
              TrakaL10n.of(context).faceNotMatch;
        });
        _showSnack(TrakaL10n.of(context).faceNotMatch, isError: true);
      }
    } catch (e, st) {
      logError('ForgotPassword._runFaceVerification', e, st);
      VerificationLogService.log(
        userId: uid,
        success: false,
        source: VerificationLogSource.forgotPassword,
        errorMessage: 'Verifikasi wajah gagal: $e',
      );
      if (mounted) {
        setState(() {
          _faceVerifyBusy = false;
          _faceVerifyLastError = kDebugMode
              ? e.toString()
              : 'Terjadi kesalahan. Periksa jaringan dan izin, lalu coba lagi.';
        });
        _showSnack(TrakaL10n.of(context).faceVerificationFailed, isError: true);
      }
    } finally {
      try {
        tempStored?.deleteSync();
      } catch (_) {}
      if (mounted && _faceVerifyBusy) {
        setState(() => _faceVerifyBusy = false);
      }
    }
  }

  Future<void> _saveNewPassword() async {
    final newPass = _newPasswordController.text;
    final confirm = _confirmPasswordController.text;
    if (newPass.length < 8) {
      _showSnack(TrakaL10n.of(context).passwordMin8Chars, isError: true);
      return;
    }
    if (!RegExp(r'\d').hasMatch(newPass)) {
      _showSnack(TrakaL10n.of(context).passwordMustContainNumber, isError: true);
      return;
    }
    if (newPass != confirm) {
      _showSnack('Konfirmasi kata sandi tidak sama.', isError: true);
      return;
    }
    final uid = _resetUid ?? FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      _showSnack(TrakaL10n.of(context).sessionExpired, isError: true);
      return;
    }
    setState(() => _loading = true);
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw Exception('Not signed in');
      await user.updatePassword(newPass);
      await BiometricLoginService.clearCredentials();

      final currentDeviceId = await DeviceService.getDeviceId();
      final userDoc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
      final storedDeviceId = userDoc.data()?['deviceId'] as String?;
      if (currentDeviceId != null &&
          currentDeviceId.isNotEmpty &&
          currentDeviceId != storedDeviceId) {
        await FirebaseFirestore.instance.collection('users').doc(uid).update({
          'deviceId': currentDeviceId,
          'deviceIdUpdatedAt': FieldValue.serverTimestamp(),
        });
      }

      await FirebaseAuth.instance.signOut();
      if (!mounted) return;
      setState(() {
        _loading = false;
        _step = _ForgotStep.done;
      });
      _showSnack(TrakaL10n.of(context).passwordChangedSuccess);
      await Future.delayed(const Duration(milliseconds: 800));
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (e) {
      if (mounted) setState(() => _loading = false);
      _showSnack('${TrakaL10n.of(context).failedToSave}: ${e.toString()}', isError: true);
    }
  }

  void _showSnack(String msg, {bool isError = false}) {
    if (isError) {
      ScaffoldMessenger.of(context).showSnackBar(
        TrakaSnackBar.error(context, Text(msg)),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        TrakaSnackBar.info(context, Text(msg)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final backdrop = context.trakaVisualTokens?.screenBackdropGradient;
    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        title: Text(TrakaL10n.of(context).forgotPasswordTitle),
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: backdrop ??
                    LinearGradient(colors: [cs.surface, cs.surface]),
              ),
            ),
          ),
          Positioned.fill(
            child: SafeArea(
              child: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(
                  context.responsive.horizontalPadding,
                  MediaQuery.paddingOf(context).top + kToolbarHeight + 8,
                  context.responsive.horizontalPadding,
                  context.responsive.horizontalPadding,
                ),
                child: _buildStepContent(),
              ),
            ),
          ),
          AuthLoadingOverlay(visible: _loading),
        ],
      ),
    );
  }

  Widget _buildStepContent() {
    switch (_step) {
      case _ForgotStep.chooseMethod:
        return _buildChooseMethod();
      case _ForgotStep.emailInput:
        return _buildEmailInput();
      case _ForgotStep.emailOtpSent:
        return _buildEmailOtpInput();
      case _ForgotStep.phoneInput:
        return _buildPhoneInput();
      case _ForgotStep.phoneOtpSent:
        return _buildPhoneOtpInput();
      case _ForgotStep.faceVerify:
        return _buildFaceVerifyPrompt();
      case _ForgotStep.newPassword:
        return _buildNewPasswordForm();
      case _ForgotStep.done:
        return _buildDone();
    }
  }

  Widget _buildChooseMethod() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(height: context.responsive.spacing(24)),
        Text(
          'Pilih metode verifikasi',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 8),
        Text(
          'No. telepon (untuk akun Phone Auth) atau email (untuk akun yang punya email). Lalu verifikasi wajah dan atur kata sandi baru.',
          style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 14),
        ),
        SizedBox(height: context.responsive.spacing(24)),
        ListTile(
          leading: const Icon(Icons.phone_android_outlined),
          title: const Text('No. telepon'),
          subtitle: const Text('Kode OTP via SMS, lalu verifikasi wajah dan atur kata sandi baru'),
          onTap: _onChoosePhone,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        const SizedBox(height: 12),
        ListTile(
          leading: const Icon(Icons.email_outlined),
          title: const Text('Email'),
          subtitle: const Text('Kode OTP dikirim ke email, lalu verifikasi wajah dan atur kata sandi baru'),
          onTap: _onChooseEmail,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ],
    );
  }

  Widget _buildEmailInput() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(height: context.responsive.spacing(16)),
        TextField(
          controller: _emailController,
          autocorrect: false,
          enableSuggestions: false,
          decoration: const InputDecoration(
            labelText: 'Email',
            hintText: 'contoh@email.com',
            prefixIcon: Icon(Icons.email_outlined),
          ),
          keyboardType: TextInputType.emailAddress,
          textInputAction: TextInputAction.done,
        ),
        SizedBox(height: context.responsive.spacing(24)),
        FilledButton(
          onPressed: _loading ? null : _sendEmailOtp,
          child: const Text('Kirim kode'),
        ),
      ],
    );
  }

  Widget _buildEmailOtpInput() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(height: context.responsive.spacing(16)),
        Text(
          'Masukkan kode verifikasi yang dikirim ke ${_emailController.text.trim().isEmpty ? "email Anda" : _emailController.text.trim()}',
          style: TextStyle(fontSize: 14, color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _otpController,
          autocorrect: false,
          enableSuggestions: false,
          decoration: const InputDecoration(
            labelText: 'Kode verifikasi (6 digit)',
            prefixIcon: Icon(Icons.email_outlined),
          ),
          keyboardType: TextInputType.number,
          maxLength: 6,
        ),
        SizedBox(height: context.responsive.spacing(24)),
        FilledButton(
          onPressed: _loading ? null : _verifyEmailOtpAndContinue,
          child: const Text('Verifikasi'),
        ),
        TextButton(
          onPressed: () => setState(() {
            _step = _ForgotStep.emailInput;
            _otpController.clear();
          }),
          child: const Text('Ganti email'),
        ),
      ],
    );
  }

  Widget _buildPhoneInput() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(height: context.responsive.spacing(16)),
        TextField(
          controller: _phoneController,
          decoration: const InputDecoration(
            labelText: 'No. telepon',
            hintText: '08123456789',
            prefixIcon: Icon(Icons.phone_outlined),
          ),
          keyboardType: TextInputType.phone,
        ),
        SizedBox(height: context.responsive.spacing(24)),
        FilledButton(
          onPressed: _loading ? null : _sendPhoneOtp,
          child: const Text('Kirim kode SMS'),
        ),
      ],
    );
  }

  Widget _buildPhoneOtpInput() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(height: context.responsive.spacing(16)),
        TextField(
          controller: _otpController,
          autocorrect: false,
          enableSuggestions: false,
          decoration: const InputDecoration(
            labelText: 'Kode verifikasi (6 digit)',
            prefixIcon: Icon(Icons.sms_outlined),
          ),
          keyboardType: TextInputType.number,
          maxLength: 6,
        ),
        SizedBox(height: context.responsive.spacing(24)),
        FilledButton(
          onPressed: _loading ? null : _verifyOtpAndContinue,
          child: const Text('Verifikasi'),
        ),
        TextButton(
          onPressed: () => setState(() {
            _step = _ForgotStep.phoneInput;
            _phoneVerificationId = null;
            _otpController.clear();
          }),
          child: const Text('Ganti no. telepon'),
        ),
      ],
    );
  }

  Widget _buildFaceVerifyPrompt() {
    final uid = _resetUid ?? FirebaseAuth.instance.currentUser?.uid;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(height: context.responsive.spacing(24)),
        if (_faceVerifyBusy) ...[
          Center(
            child: TrakaLoadingIndicator(
              size: 44,
              primary: Theme.of(context).colorScheme.primary,
              secondary: Theme.of(context).colorScheme.secondary,
            ),
          ),
          const SizedBox(height: 16),
          Center(
            child: Text(
              'Mempersiapkan verifikasi wajah…',
              style: Theme.of(context).textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
          ),
        ] else ...[
          if (_faceVerifyLastError != null) ...[
            Icon(
              Icons.info_outline_rounded,
              size: 40,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: 12),
            Text(
              _faceVerifyLastError!,
              style: Theme.of(context).textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Pastikan izin kamera di pengaturan aplikasi diaktifkan, lalu coba lagi.',
              style: TextStyle(
                fontSize: 13,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            SizedBox(height: context.responsive.spacing(20)),
          ] else ...[
            Text(
              'Langkah berikutnya: verifikasi wajah (kedip di depan kamera).',
              style: Theme.of(context).textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
          ],
          if (uid != null) ...[
            FilledButton(
              onPressed: _faceVerifyBusy ? null : () => _runFaceVerification(uid),
              child: const Text('Coba verifikasi wajah'),
            ),
          ],
          const SizedBox(height: 12),
          TextButton(
            onPressed: _faceVerifyBusy
                ? null
                : () async {
                    await FirebaseAuth.instance.signOut();
                    if (!mounted) return;
                    setState(() {
                      _step = _ForgotStep.chooseMethod;
                      _resetUid = null;
                      _faceVerifyLastError = null;
                      _phoneVerificationId = null;
                      _otpController.clear();
                    });
                  },
            child: const Text('Batalkan & mulai dari awal'),
          ),
        ],
      ],
    );
  }

  Widget _buildNewPasswordForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(height: context.responsive.spacing(16)),
        Text(
          'Kata sandi baru',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _newPasswordController,
          autocorrect: false,
          enableSuggestions: false,
          decoration: const InputDecoration(
            labelText: 'Kata sandi baru',
            prefixIcon: Icon(Icons.lock_outline),
          ),
          obscureText: true,
          textInputAction: TextInputAction.next,
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _confirmPasswordController,
          autocorrect: false,
          enableSuggestions: false,
          decoration: const InputDecoration(
            labelText: 'Konfirmasi kata sandi baru',
            prefixIcon: Icon(Icons.lock_outline),
          ),
          obscureText: true,
          textInputAction: TextInputAction.done,
        ),
        const SizedBox(height: 8),
        Text(
          'Minimal 8 karakter, harus mengandung angka.',
          style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
        SizedBox(height: context.responsive.spacing(24)),
        FilledButton(
          onPressed: _loading ? null : _saveNewPassword,
          child: const Text('Simpan'),
        ),
      ],
    );
  }

  Widget _buildDone() {
    return Column(
      children: [
        SizedBox(height: context.responsive.spacing(24)),
        Icon(Icons.check_circle_outline, size: 64, color: Colors.green.shade700),
        const SizedBox(height: 16),
        const Text(
          'Kata sandi berhasil diubah. Silakan login dengan kata sandi baru.',
          textAlign: TextAlign.center,
        ),
        SizedBox(height: context.responsive.spacing(24)),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Kembali ke login'),
        ),
      ],
    );
  }
}
