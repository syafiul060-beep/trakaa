import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:crypto/crypto.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';

import 'active_liveness_screen.dart';
import '../services/face_validation_service.dart';
import '../services/verification_log_service.dart';
import '../services/permission_service.dart';
import '../services/ocr_preprocess_service.dart';
import 'package:image_picker/image_picker.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../config/indonesia_config.dart';
import '../services/account_deletion_service.dart';
import '../services/app_analytics_service.dart';
import '../services/auth_redirect_state.dart';
import '../services/low_ram_warning_service.dart';
import '../services/lite_mode_service.dart';
import '../services/driver_status_service.dart';
import '../services/voice_call_incoming_service.dart';
import '../services/image_compression_service.dart';
import '../theme/app_theme.dart';
import '../l10n/app_localizations.dart';
import '../services/locale_service.dart';
import '../widgets/traka_l10n_scope.dart';
import '../theme/responsive.dart';
import '../utils/phone_utils.dart';
import '../utils/safe_navigation_utils.dart';
import '../services/stnk_scan_service.dart';
import '../services/rating_service.dart';
import '../services/route_persistence_service.dart';
import '../widgets/admin_contact_widget.dart';
import '../widgets/document_capture_guide_dialog.dart';
import '../widgets/profile_contact_row.dart';
import '../widgets/profile_face_validation_dialog.dart';
import '../widgets/theme_toggle_widget.dart';
import '../widgets/biometric_login_credential_tile.dart';
import '../widgets/biometric_toggle_widget.dart';
import '../widgets/app_version_title.dart';
import '../widgets/delayed_loading_builder.dart';
import '../widgets/shimmer_loading.dart';
import 'data_kendaraan_screen.dart';
import 'login_screen.dart';
import 'contribution_driver_screen.dart';
import 'driver_earnings_screen.dart';
import 'payment_history_screen.dart';
import 'panduan_aplikasi_screen.dart';
import 'promo_list_screen.dart';
import 'saran_ke_admin_screen.dart';

/// Halaman profil khusus driver (tanpa nomor telepon dan login sidik jari/wajah).
class ProfileDriverScreen extends StatefulWidget {
  const ProfileDriverScreen({super.key});

  @override
  State<ProfileDriverScreen> createState() => _ProfileDriverScreenState();
}

class _ProfileDriverScreenState extends State<ProfileDriverScreen> {
  final _auth = FirebaseAuth.instance;
  final _firestore = FirebaseFirestore.instance;
  DocumentSnapshot<Map<String, dynamic>>? _userDoc;
  bool _loading = true;
  bool _isCheckingFace = false;
  bool _isOcrLoading = false;
  bool _isLowRamDevice = false;
  File? _photoFile;
  final _nameController = TextEditingController();

  static const _daysPhotoLock = 30;

  Future<(double?, int)>? _cachedRatingFuture;
  Future<(double?, int)> get _driverRatingFuture {
    _cachedRatingFuture ??= () async {
      final uid = _auth.currentUser?.uid;
      if (uid == null) return (null, 0);
      final avg = await RatingService.getDriverAverageRating(uid);
      final count = await RatingService.getDriverReviewCount(uid);
      return (avg, count);
    }();
    return _cachedRatingFuture!;
  }

  @override
  void initState() {
    super.initState();
    _loadUser();
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _loadUser({bool forceFromServer = false}) async {
    final user = _auth.currentUser;
    if (user == null) return;
    try {
      final doc = await _firestore.collection('users').doc(user.uid).get(
        forceFromServer ? const GetOptions(source: Source.server) : const GetOptions(),
      );
      if (mounted) {
        setState(() {
          _userDoc = doc;
          _loading = false;
          if (doc.exists && doc.data() != null) {
            final d = doc.data()!;
            _nameController.text = (d['displayName'] as String?) ?? '';
          }
        });
      }
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Map<String, dynamic> get _userData => _userDoc?.data() ?? <String, dynamic>{};

  /// Driver sudah isi verifikasi SIM (nama + nomor SIM tersimpan).
  bool get _isDriverVerified {
    return _userData['driverSIMVerifiedAt'] != null ||
        _userData['driverSIMNomorHash'] != null;
  }

  /// Data kendaraan sudah diisi (plat/merek/type tersimpan di users).
  bool get _isDataKendaraanFilled {
    return _userData['vehiclePlat'] != null ||
        _userData['vehicleUpdatedAt'] != null;
  }

  /// Email & No.Telp dianggap lengkap jika email ATAU no. telepon sudah ditambahkan.
  bool get _isEmailDanTelpFilled {
    final String phone = ((_userData['phoneNumber'] as String?) ?? '').trim();
    final String email = (_auth.currentUser?.email ?? '').trim();
    return phone.isNotEmpty || email.isNotEmpty;
  }

  /// Semua menu verifikasi sudah lengkap: Data Kendaraan + Verifikasi Driver + Email & No.Telp.
  bool get _isAllProfileVerified =>
      _isDataKendaraanFilled && _isDriverVerified && _isEmailDanTelpFilled;

  int get _verificationCompleteCount =>
      (_isDataKendaraanFilled ? 1 : 0) +
      (_isDriverVerified ? 1 : 0) +
      (_isEmailDanTelpFilled ? 1 : 0);

  DateTime? _timestamp(dynamic v) {
    if (v == null) return null;
    if (v is Timestamp) return v.toDate();
    return null;
  }

  bool _canChangePhoto() {
    final updatedAt = _timestamp(_userData['photoUpdatedAt']);
    if (updatedAt == null) return true;
    return DateTime.now().difference(updatedAt).inDays >= _daysPhotoLock;
  }

  int? _daysUntilPhotoChange() {
    final updatedAt = _timestamp(_userData['photoUpdatedAt']);
    if (updatedAt == null) return null;
    final days = _daysPhotoLock - DateTime.now().difference(updatedAt).inDays;
    return days > 0 ? days : null;
  }

  Future<void> _pickAndVerifyPhoto() async {
    if (!_canChangePhoto()) return;
    final cameraOk = await PermissionService.requestCameraPermission(context);
    if (!cameraOk || !mounted) return;

    setState(() => _isCheckingFace = true);
    final file = await Navigator.of(context).push<File>(
      MaterialPageRoute<File>(builder: (_) => const ActiveLivenessScreen()),
    );
    if (!mounted) return;
    setState(() => _isCheckingFace = false);

    if (file == null || file.path.isEmpty) return;

    // Loading saat memeriksa foto
    if (mounted) {
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => const AlertDialog(
          content: Row(
            children: [
              CircularProgressIndicator(),
              SizedBox(width: 16),
              Text('Memeriksa foto...'),
            ],
          ),
        ),
      );
    }
    final validationResult = await FaceValidationService.validateFacePhoto(file.path);
    if (!mounted) return;
    Navigator.of(context).pop();
    if (!validationResult.isValid) {
      final action = await ProfileFaceValidationDialog.show(
        context,
        message: validationResult.errorMessage ??
            TrakaL10n.of(context).photoDoesNotMeetRequirements,
        isBlurError: validationResult.isBlurError,
      );
      if (action == FaceValidationDialogAction.retry && mounted) return _pickAndVerifyPhoto();
      if (action == FaceValidationDialogAction.useAnyway && mounted) {
        if (mounted) {
          showDialog<void>(
            context: context,
            barrierDismissible: false,
            builder: (ctx) => const AlertDialog(
              content: Row(
                children: [
                  CircularProgressIndicator(),
                  SizedBox(width: 16),
                  Text('Memeriksa foto...'),
                ],
              ),
            ),
          );
        }
        final skipBlurResult = await FaceValidationService.validateFacePhotoSkipBlur(file.path);
        if (mounted) Navigator.of(context).pop();
        if (!skipBlurResult.isValid) {
          final retry = await ProfileFaceValidationDialog.show(
            context,
            message:
                'Foto harus wajah asli, bukan dari gambar atau layar. Silakan ambil foto ulang.',
            isBlurError: false,
          );
          if (retry == FaceValidationDialogAction.retry && mounted) return _pickAndVerifyPhoto();
          return;
        }
        setState(() => _photoFile = file);
        await _uploadPhoto();
      }
      return;
    }

    setState(() => _photoFile = file);
    await _uploadPhoto();
  }

  Future<void> _uploadPhoto() async {
    final user = _auth.currentUser;
    final file = _photoFile;
    if (user == null || file == null) return;
    if (mounted) {
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => const AlertDialog(
          content: Row(
            children: [
              CircularProgressIndicator(),
              SizedBox(width: 16),
              Text('Mengunggah foto...'),
            ],
          ),
        ),
      );
    }
    try {
      final compressedPath = await ImageCompressionService.compressForUpload(file.path);
      final fileToUpload = File(compressedPath);
      final photoRef = FirebaseStorage.instance.ref().child(
        'users/${user.uid}/photo.jpg',
      );
      await photoRef.putFile(fileToUpload);
      final photoUrl = await photoRef.getDownloadURL();
      final faceRef = FirebaseStorage.instance.ref().child(
        'users/${user.uid}/face_verification.jpg',
      );
      await faceRef.putFile(fileToUpload);
      final faceUrl = await faceRef.getDownloadURL();
      final updates = <String, dynamic>{
        'photoUrl': photoUrl,
        'photoUpdatedAt': FieldValue.serverTimestamp(),
        'faceVerificationUrl': faceUrl,
        'faceVerificationLastVerifiedAt': FieldValue.serverTimestamp(),
      };
      await _firestore.collection('users').doc(user.uid).update(updates);
      VerificationLogService.log(
        userId: user.uid,
        success: true,
        source: VerificationLogSource.profileDriver,
      );
      if (mounted) {
        Navigator.of(context).pop();
        setState(() => _photoFile = null);
      }
      await _loadUser(forceFromServer: true);
      if (mounted) _showSnackBar('Foto profil berhasil diubah.');
    } catch (e) {
      if (mounted) Navigator.of(context).pop();
      VerificationLogService.log(
        userId: user.uid,
        success: false,
        source: VerificationLogSource.profileDriver,
        errorMessage: 'Gagal mengunggah foto: $e',
      );
      if (mounted) _showSnackBar('Gagal mengunggah foto: $e', isError: true);
    }
  }

  void _showLanguageSelector() {
    final l10n = TrakaL10n.of(context);
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                l10n.language,
                style: Theme.of(ctx).textTheme.titleLarge,
              ),
            ),
            ListTile(
              leading: const Icon(Icons.flag),
              title: Text(TrakaL10n.of(context).languageIndonesia),
              onTap: () {
                LocaleService.setLocale(AppLocale.id);
                Navigator.pop(ctx);
              },
            ),
            ListTile(
              leading: const Icon(Icons.flag),
              title: Text(TrakaL10n.of(context).languageEnglish),
              onTap: () {
                LocaleService.setLocale(AppLocale.en);
                Navigator.pop(ctx);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showChangePasswordDialog() async {
    final user = _auth.currentUser;
    if (user == null) return;
    final hasEmail = (user.email ?? '').trim().isNotEmpty;
    if (!hasEmail) {
      final goAdd = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(TrakaL10n.of(context).changePasswordTitle),
          content: Text(TrakaL10n.of(context).addEmailFirstToChangePassword),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Batal'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(TrakaL10n.of(context).addEmail),
            ),
          ],
        ),
      );
      if (goAdd == true && mounted) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _showTambahEmailDialog();
        });
      }
      return;
    }
    final oldC = TextEditingController();
    final newC = TextEditingController();
    final confirmC = TextEditingController();
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(TrakaL10n.of(context).changePasswordTitle),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: oldC,
                decoration: InputDecoration(
                  labelText: TrakaL10n.of(context).oldPassword,
                  border: const OutlineInputBorder(),
                ),
                obscureText: true,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: newC,
                decoration: InputDecoration(
                  labelText: TrakaL10n.of(context).newPassword,
                  border: const OutlineInputBorder(),
                ),
                obscureText: true,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: confirmC,
                decoration: InputDecoration(
                  labelText: TrakaL10n.of(context).confirmNewPassword,
                  border: const OutlineInputBorder(),
                ),
                obscureText: true,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () async {
              final old = oldC.text;
              final newP = newC.text;
              final confirm = confirmC.text;
              if (newP.length < 8) {
                _showSnackBar(
                  'Password baru minimal 8 karakter.',
                  isError: true,
                );
                return;
              }
              if (newP != confirm) {
                _showSnackBar('Password tidak sama.', isError: true);
                return;
              }
              Navigator.pop(ctx);
              final user = _auth.currentUser;
              if (user == null) return;
              try {
                final cred = EmailAuthProvider.credential(
                  email: user.email!,
                  password: old,
                );
                await user.reauthenticateWithCredential(cred);
                await user.updatePassword(newP);
                if (mounted) _showSnackBar('Password berhasil diubah.');
              } on FirebaseAuthException catch (e) {
                if (e.code == 'wrong-password' ||
                    e.code == 'invalid-credential') {
                  _showSnackBar('Password lama salah.', isError: true);
                } else {
                  _showSnackBar('Gagal: ${e.message}', isError: true);
                }
              }
            },
            child: const Text('Simpan'),
          ),
        ],
      ),
    );
  }

  /// Dialog ketika driver sudah terverifikasi (tidak perlu ubah lagi).
  Future<void> _showVerifikasiSudahBerhasilDialog() async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.check_circle, color: Colors.green.shade700, size: 28),
            const SizedBox(width: 8),
            const Text(
              'Verifikasi Driver',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        content: const Text(
          'Verifikasi Berhasil anda tidak perlu mengubah data verifikasi kembali. Silahkan hubungi Admin.',
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  void _showEmailDanTelpSheet() {
    final user = _auth.currentUser;
    if (user == null) return;
    final String email = user.email ?? '';
    final String phone = ((_userData['phoneNumber'] as String?) ?? '').trim();

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(context.responsive.radius(AppTheme.radiusLg)),
        ),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: DraggableScrollableSheet(
          initialChildSize: 0.5,
          minChildSize: 0.3,
          maxChildSize: 0.9,
          expand: false,
          builder: (_, scrollController) => SingleChildScrollView(
            controller: scrollController,
            padding: EdgeInsets.all(context.responsive.spacing(AppTheme.spacingLg)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'No. Telepon & Email',
                  style: TextStyle(
                    fontSize: context.responsive.fontSize(18),
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
                SizedBox(height: context.responsive.spacing(8)),
                Text(
                  'No. telepon untuk login (OTP). Email opsional untuk notifikasi, invoice, dan recovery jika nomor hilang.',
                  style: TextStyle(
                    fontSize: context.responsive.fontSize(12),
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                SizedBox(height: context.responsive.spacing(20)),
                // No. Telepon — primary (Phone Auth)
                ProfileContactRow(
                  icon: Icons.phone_outlined,
                  label: 'No. Telepon',
                  value: phone.isEmpty ? 'Belum ditambahkan' : phone,
                  actionLabel: phone.isEmpty ? 'Tambah No. Telepon' : 'Ubah No. Telepon',
                  onTap: () {
                    Navigator.pop(ctx);
                    _showTeleponVerifikasiDialog();
                  },
                ),
                SizedBox(height: context.responsive.spacing(16)),
                // Email — opsional (Tambah Email / Ubah Email)
                ProfileContactRow(
                  icon: Icons.email_outlined,
                  label: 'Email',
                  value: email.isEmpty ? 'Belum ditambahkan' : email,
                  actionLabel: email.isEmpty ? 'Tambah Email' : 'Ubah Email',
                  onTap: () {
                    Navigator.pop(ctx);
                    if (email.isEmpty) {
                      _showTambahEmailDialog();
                    } else {
                      _showUbahEmailDialog();
                    }
                  },
                ),
                if (email.isNotEmpty) ...[
                  SizedBox(height: context.responsive.spacing(8)),
                  Text(
                    'Login juga bisa menggunakan email + password.',
                    style: TextStyle(
                      fontSize: context.responsive.fontSize(11),
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
                SizedBox(height: context.responsive.spacing(24)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Tambah email ke akun Phone Auth (link EmailAuthProvider, butuh password).
  /// Verifikasi OTP ke email dulu sebelum simpan.
  Future<void> _showTambahEmailDialog() async {
    final user = _auth.currentUser;
    if (user == null) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _TambahEmailOtpDialog(
        onSuccess: () {
          Navigator.pop(ctx);
          _loadUser();
          _showSnackBar(
            'Email berhasil ditambahkan. Login bisa dengan no. telepon atau email + password.',
          );
        },
        onCancel: () => Navigator.pop(ctx),
        onError: _showSnackBar,
      ),
    );
  }

  /// Ubah email: verifikasi OTP ke email baru dulu sebelum simpan.
  Future<void> _showUbahEmailDialog() async {
    final user = _auth.currentUser;
    if (user == null) return;
    final currentEmail = (user.email ?? '').trim();
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _UbahEmailOtpDialog(
        currentEmail: currentEmail,
        onSuccess: () {
          Navigator.pop(ctx);
          _loadUser();
          _showSnackBar('Email berhasil diubah.');
        },
        onCancel: () => Navigator.pop(ctx),
        onError: _showSnackBar,
      ),
    );
  }

  Future<void> _showTeleponVerifikasiDialog() async {
    final user = _auth.currentUser;
    if (user == null) return;

    final String currentPhone = ((_userData['phoneNumber'] as String?) ?? '')
        .trim();
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _TeleponVerifikasiDialog(
        currentUserId: user.uid,
        currentPhone: currentPhone,
        onSuccess: () {
          Navigator.pop(ctx);
          _loadUser();
          _showSnackBar(
            'No. telepon berhasil ditambahkan. Login bisa dengan email atau no. telepon.',
          );
        },
        onCancel: () => Navigator.pop(ctx),
      ),
    );
  }

  /// Verifikasi wajah/foto profil sudah ada di icon kamera profil. Verifikasi Driver = hanya SIM.
  Future<void> _showVerifikasiDriverDialog() async {
    final hasFace = (_userData['faceVerificationUrl'] as String?)?.trim().isNotEmpty ?? false;
    if (!hasFace) {
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text(
            'Verifikasi Driver',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          content: const Text(
            'Foto profil (verifikasi wajah) diperlukan terlebih dahulu. '
            'Klik icon kamera di samping nama untuk mengambil foto.',
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text(
          'Verifikasi Driver',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        content: const Text(
          'Ambil foto SIM/Surat Izin Mengemudi untuk verifikasi. '
          'Foto akan digunakan untuk membaca nama dan nomor SIM.',
        ),
        actions: [
          TextButton(
            onPressed: () => safePop(ctx),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () async {
              await safePopAndComplete(ctx);
              if (!mounted) return;
              await Future.delayed(const Duration(milliseconds: 150));
              if (!mounted) return;
              final ok = await DocumentCaptureGuideDialog.show(
                context,
                documentType: DocumentCaptureType.sim,
              );
              if (ok && mounted) _scanSIM();
            },
            child: const Text('Lanjut'),
          ),
        ],
      ),
    );
  }

  Future<void> _scanSIM() async {
    final ramMb = await LowRamWarningService.getDeviceRamMb();
    final lowRam = ramMb != null && ramMb < 4096;
    if (mounted) setState(() => _isLowRamDevice = lowRam);

    final picker = ImagePicker();
    final XFile? image = await picker.pickImage(
      source: ImageSource.camera,
      imageQuality: lowRam ? 85 : 100, // HP RAM rendah: kurangi ukuran file
    );
    if (image == null || !mounted) return;

    // Validasi file foto ada dan terbaca (hindari error OCR)
    final photoFile = File(image.path);
    if (!photoFile.existsSync() || photoFile.lengthSync() == 0) {
      _showSnackBar('Foto tidak ditemukan atau rusak. Silakan ambil foto ulang.', isError: true);
      return;
    }

    AuthRedirectState.setInVerificationFlow(true);

    // Tunda agar UI selesai redraw setelah kembali dari kamera (hindari layar hitam)
    await Future<void>.delayed(const Duration(milliseconds: 150));
    if (!mounted) {
      AuthRedirectState.setInVerificationFlow(false);
      return;
    }
    setState(() => _isOcrLoading = true);
    if (!mounted) {
      AuthRedirectState.setInVerificationFlow(false);
      return;
    }

    try {
      // OCR dengan beberapa varian preprocessing + voting konsensus
      final ocrTexts = await OcrPreprocessService.runOcrVariants(image.path);

      if (!mounted) {
        AuthRedirectState.setInVerificationFlow(false);
        return;
      }
      if (!mounted) {
        AuthRedirectState.setInVerificationFlow(false);
        return;
      }
      setState(() => _isOcrLoading = false);

      // Voting: kumpulkan semua hasil valid, ambil yang paling sering muncul
      final voteCount = <String, int>{};
      for (final text in ocrTexts) {
        final extractedData = _extractSIMData(text);
        if (extractedData['nama'] != null && extractedData['nomorSIM'] != null) {
          final key = '${extractedData['nama']}|${extractedData['nomorSIM']}';
          voteCount[key] = (voteCount[key] ?? 0) + 1;
        }
      }
      Map<String, String?>? extractedData;
      if (voteCount.isNotEmpty) {
        final best = voteCount.entries.reduce(
          (a, b) => a.value >= b.value ? a : b,
        );
        final parts = best.key.split('|');
        extractedData = {'nama': parts[0], 'nomorSIM': parts[1]};
      }

      if (extractedData == null ||
          extractedData['nama'] == null ||
          extractedData['nomorSIM'] == null) {
        if (mounted) {
          setState(() => _isOcrLoading = false);
          AuthRedirectState.setInVerificationFlow(false);
          AppAnalyticsService.logOcrFailed(documentType: 'sim', reason: 'extraction_failed');
          _showSnackBarWithRetry(
            'Gagal membaca data SIM. Pastikan foto SIM jelas dan lengkap.',
            onRetry: _scanSIM,
          );
        }
        return;
      }

      if (!mounted) {
        AuthRedirectState.setInVerificationFlow(false);
        return;
      }
      await _showSIMDataConfirmationDialog(
        extractedData['nama']!,
        extractedData['nomorSIM']!,
      );
      AuthRedirectState.setInVerificationFlow(false);
    } catch (e) {
      if (mounted) {
        setState(() => _isOcrLoading = false);
        AuthRedirectState.setInVerificationFlow(false);
        final isTimeout = e.toString().contains('terlalu lama');
        AppAnalyticsService.logOcrFailed(
          documentType: 'sim',
          reason: isTimeout ? 'timeout' : 'error',
        );
        final msg = isTimeout
            ? 'Proses membaca SIM terlalu lama. Silakan coba foto ulang dengan pencahayaan yang lebih baik.'
            : 'Gagal membaca SIM: $e. Silakan coba foto ulang.';
        if (mounted) _showSnackBarWithRetry(msg, onRetry: _scanSIM);
      }
    }
  }

  /// Ekstrak nama dan nomor SIM dari teks OCR. Mendukung koreksi OCR: O↔0, I/l↔1.
  Map<String, String?> _extractSIMData(String ocrText) {
    String? nama;
    String? nomorSIM;

    // Pattern untuk nomor SIM (format Indonesia: 12-16 digit)
    final simPattern = RegExp(r'\b\d{12,16}\b');
    var simMatch = simPattern.firstMatch(ocrText);
    if (simMatch != null) {
      nomorSIM = simMatch.group(0);
    } else {
      // Pola permissive untuk OCR error (O, I, l sebagai digit)
      final ocrSimPattern = RegExp(r'\b[0-9OIl]{12,16}\b');
      simMatch = ocrSimPattern.firstMatch(ocrText);
      if (simMatch != null) {
        nomorSIM = simMatch
            .group(0)!
            .replaceAll('O', '0')
            .replaceAll('I', '1')
            .replaceAll('l', '1');
      }
    }

    // Pattern untuk mencari nama (biasanya setelah kata kunci seperti "NAMA", "NAME", atau di baris tertentu)
    final lines = ocrText.split('\n');
    for (int i = 0; i < lines.length; i++) {
      final line = lines[i].trim().toUpperCase();

      // Cari baris yang mengandung "NAMA" atau "NAME"
      if (line.contains('NAMA') || line.contains('NAME')) {
        // Ambil baris berikutnya atau bagian setelah "NAMA"
        if (line.contains('NAMA') || line.contains('NAME')) {
          final parts = line.split(RegExp(r'NAMA|NAME'));
          if (parts.length > 1) {
            nama = parts[1].trim();
            if (nama.isEmpty && i + 1 < lines.length) {
              nama = lines[i + 1].trim();
            }
          } else if (i + 1 < lines.length) {
            nama = lines[i + 1].trim();
          }
        }
      }

      // Jika belum ditemukan, coba cari pola nama (huruf besar, minimal 3 kata)
      if (nama == null || nama.isEmpty) {
        final namePattern = RegExp(r'^[A-Z\s]{10,}$');
        if (namePattern.hasMatch(line) &&
            line.split(' ').length >= 2 &&
            !line.contains('SIM') &&
            !line.contains('DRIVER') &&
            !line.contains('LICENSE')) {
          nama = line;
        }
      }
    }

    // Jika masih belum ditemukan nama, ambil baris pertama yang panjang (kemungkinan nama)
    if ((nama == null || nama.isEmpty) && lines.isNotEmpty) {
      for (final line in lines) {
        final trimmed = line.trim();
        if (trimmed.length >= 10 &&
            trimmed.split(' ').length >= 2 &&
            !trimmed.contains(
              RegExp(r'\d{4,}'),
            ) && // Tidak mengandung banyak angka
            !trimmed.contains('SIM') &&
            !trimmed.contains('DRIVER')) {
          nama = trimmed;
          break;
        }
      }
    }

    return {'nama': nama, 'nomorSIM': nomorSIM};
  }

  Future<void> _showSIMDataConfirmationDialog(
    String nama,
    String nomorSIM,
  ) async {
    final namaController = TextEditingController(text: nama);
    final simController = TextEditingController(text: nomorSIM);
    bool dataSetuju = false;
    bool isSaving = false;
    bool isSaved = false;
    String? saveError;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: Text(
              isSaved ? 'Berhasil' : 'Data SIM yang Dibaca',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            content: SingleChildScrollView(
              child: isSaved
                  ? Text(
                      saveError ?? 'Data SIM berhasil disimpan. Nama profil telah diperbarui.',
                      style: TextStyle(
                        fontSize: 14,
                        color: saveError != null
                            ? Theme.of(context).colorScheme.error
                            : Theme.of(context).colorScheme.onSurface,
                      ),
                    )
                  : Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          'Periksa data di bawah. Anda dapat mengubah jika foto kabur/buram.',
                          style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
                        ),
                        const SizedBox(height: 16),
                        TextField(
                          controller: namaController,
                          decoration: InputDecoration(
                            labelText: 'Nama',
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppTheme.radiusSm)),
                          ),
                          onChanged: (_) => setDialogState(() {}),
                        ),
                        const SizedBox(height: 16),
                        TextField(
                          controller: simController,
                          decoration: InputDecoration(
                            labelText: 'Nomor SIM',
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppTheme.radiusSm)),
                          ),
                          keyboardType: TextInputType.number,
                          onChanged: (_) => setDialogState(() {}),
                        ),
                        const SizedBox(height: 20),
                        CheckboxListTile(
                          value: dataSetuju,
                          onChanged: isSaving ? null : (value) =>
                              setDialogState(() => dataSetuju = value ?? false),
                          title: const Text(
                            'Data sudah sesuai dan setuju',
                            style: TextStyle(fontSize: 14),
                          ),
                          controlAffinity: ListTileControlAffinity.leading,
                          contentPadding: EdgeInsets.zero,
                        ),
                        if (isSaving)
                          const Padding(
                            padding: EdgeInsets.only(top: 16),
                            child: Center(child: CircularProgressIndicator()),
                          ),
                      ],
                    ),
            ),
            actions: [
              if (isSaved)
                FilledButton(
                  onPressed: () => safePop(ctx),
                  child: const Text('OK'),
                )
              else ...[
                TextButton(
                  onPressed: isSaving ? null : () => safePop(ctx),
                  child: const Text('Batal'),
                ),
                FilledButton(
                  onPressed: (dataSetuju && !isSaving)
                      ? () async {
                          setDialogState(() => isSaving = true);
                          await _saveSIMData(
                            namaController.text.trim(),
                            simController.text.trim(),
                            onSuccess: () => setDialogState(() {
                              isSaving = false;
                              isSaved = true;
                            }),
                            onError: (msg) => setDialogState(() {
                              isSaving = false;
                              saveError = msg;
                              isSaved = true;
                            }),
                          );
                        }
                      : null,
                  child: const Text('Simpan'),
                ),
              ],
            ],
          );
        },
      ),
    );
  }

  /// Hash nomor SIM dengan SHA-256
  String _hashNomorSIM(String nomorSIM) {
    final bytes = utf8.encode(nomorSIM.trim());
    final digest = sha256.convert(bytes);
    return digest.toString();
  }

  Future<void> _saveSIMData(
    String nama,
    String nomorSIM, {
    void Function()? onSuccess,
    void Function(String)? onError,
  }) async {
    if (nama.isEmpty || nomorSIM.isEmpty) {
      onError?.call('Nama dan nomor SIM wajib diisi');
      if (onError == null && mounted) _showSnackBar('Nama dan nomor SIM wajib diisi', isError: true);
      return;
    }

    final user = _auth.currentUser;
    if (user == null) return;

    final simHash = _hashNomorSIM(nomorSIM);

    try {
      final querySnapshot = await _firestore
          .collection('users')
          .where('driverSIMNomorHash', isEqualTo: simHash)
          .limit(1)
          .get();

      final usedByOther = querySnapshot.docs.any((doc) => doc.id != user.uid);

      if (usedByOther) {
        onError?.call('Nomor sim sudah pernah dipakai di akun lain.');
        if (onError == null && mounted) {
          _showSnackBar('Nomor sim sudah pernah dipakai di akun lain.', isError: true);
        }
        return;
      }

      await _firestore.collection('users').doc(user.uid).update({
        'displayName': nama,
        'driverSIMNama': nama,
        'driverSIMNomorHash': simHash,
        'driverSIMVerifiedAt': FieldValue.serverTimestamp(),
      });

      if (mounted) {
        setState(() => _nameController.text = nama);
        _loadUser();
      }
      onSuccess?.call();
      if (onSuccess == null && mounted) {
        _showSnackBar('Data SIM berhasil disimpan. Nama profil telah diperbarui.');
      }
    } catch (e) {
      final msg = e.toString().replaceAll('Exception: ', '');
      onError?.call('Gagal menyimpan data SIM: $msg');
      if (onError == null && mounted) {
        _showSnackBar('Gagal menyimpan data SIM: $msg', isError: true);
      }
    }
  }

  Future<void> _showDataKendaraanDialog() async {
    // Tampilkan keterangan dan tombol Ambil foto STNK dulu
    final shouldScan = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.directions_car, color: Theme.of(ctx).primaryColor),
            const SizedBox(width: 8),
            const Text('Data Kendaraan'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Ambil Foto STNK, nomor polisi/plat kendaraan Anda harus jelas.',
              style: TextStyle(
                fontSize: 15,
                height: 1.5,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => safePop(ctx, false),
            child: const Text('Batal'),
          ),
          FilledButton.icon(
            onPressed: () => safePop(ctx, true),
            icon: const Icon(Icons.camera_alt, size: 20),
            label: const Text('Ambil foto STNK'),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.primary,
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );

    if (!mounted || shouldScan != true) return;

    // Tampilkan panduan foto dulu
    final okGuide = await DocumentCaptureGuideDialog.show(
      context,
      documentType: DocumentCaptureType.stnk,
    );
    if (!mounted || !okGuide) return;

    // Buka kamera untuk scan STNK otomatis
    final scannedPlat = await StnkScanService.scanPlatFromCamera(context: context);
    if (!mounted) return;

    // Jika tidak scan foto (batal atau tidak terbaca), jangan tampilkan form - untuk keamanan
    if (scannedPlat == null || scannedPlat.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Scan STNK diperlukan untuk mengisi data kendaraan. Silakan ambil foto STNK.',
          ),
          backgroundColor: Colors.orange,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    // Cek apakah plat sudah dipakai driver lain
    final usedByOther = await _checkPlatUsedByOtherDriver(scannedPlat);
    if (!mounted) return;
    if (usedByOther) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Mobil milik Driver lain. Silakan scan STNK kendaraan Anda.',
          ),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return; // Jangan tampilkan form - driver harus scan STNK yang valid
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Nomor plat terdeteksi: $scannedPlat'),
        backgroundColor: Colors.green,
        behavior: SnackBarBehavior.floating,
      ),
    );

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: DraggableScrollableSheet(
          initialChildSize: 0.9,
          minChildSize: 0.5,
          maxChildSize: 0.95,
          expand: false,
          builder: (context, scrollController) => DataKendaraanFormSheet(
            scrollController: scrollController,
            initialPlatFromScan: scannedPlat,
          ),
        ),
      ),
    );
    // Refresh profil agar status verifikasi data kendaraan langsung tampil
    if (mounted) _loadUser();
  }

  /// Cek apakah nomor plat sudah dipakai driver lain (bukan driver saat ini)
  Future<bool> _checkPlatUsedByOtherDriver(String plat) async {
    final user = _auth.currentUser;
    if (user == null) return false;
    try {
      final platUpper = plat.trim().toUpperCase();
      final querySnapshot = await _firestore
          .collection('users')
          .where('vehiclePlat', isEqualTo: platUpper)
          .limit(1)
          .get();
      if (querySnapshot.docs.isNotEmpty) {
        return querySnapshot.docs.first.id != user.uid;
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  Future<void> _showHapusAkunDialog() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Hapus akun'),
        content: const Text(
          'Akun akan dijadwalkan penghapusan dalam 30 hari. Dalam masa tersebut Anda dapat batalkan dengan login kembali. Yakin ingin menghapus akun?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Hapus akun'),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    final user = _auth.currentUser;
    if (user == null) return;
    try {
      await AccountDeletionService.scheduleAccountDeletion(user.uid, 'driver');
      await DriverStatusService.removeDriverStatus();
      await RoutePersistenceService.clear();
      await _auth.signOut();
      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pushAndRemoveUntil(
        MaterialPageRoute<void>(builder: (_) => const LoginScreen()),
        (route) => false,
      );
    } catch (e) {
      if (mounted) _showSnackBar('${TrakaL10n.of(context).deleteAccountFailed}: $e', isError: true);
    }
  }

  Future<void> _onLogout() async {
    final navigator = Navigator.of(context, rootNavigator: true);
    VoiceCallIncomingService.stop();
    // JANGAN hapus deviceId saat logout - biarkan tersimpan di Firestore
    // Saat login di device baru, akan dicek apakah deviceId sama atau berbeda dengan device terakhir login
    // Jika berbeda → wajib verifikasi wajah → update deviceId ke yang baru
    try {
      await DriverStatusService.removeDriverStatus();
    } catch (_) {}
    try {
      await RoutePersistenceService.clear();
    } catch (_) {}
    try {
      await _auth.signOut();
    } catch (_) {}
    navigator.pushAndRemoveUntil(
      MaterialPageRoute<void>(builder: (_) => const LoginScreen()),
      (route) => false,
    );
  }

  void _showBiometricSheet() {
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                TrakaL10n.of(context).locale == AppLocale.id
                    ? 'Kunci dengan sidik jari/wajah'
                    : 'Lock with fingerprint/face',
                style: Theme.of(ctx).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
              const SizedBox(height: 8),
              Text(
                TrakaL10n.of(context).locale == AppLocale.id
                    ? 'Minta verifikasi saat buka app dari background'
                    : 'Require verification when opening app from background',
                style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                      color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                    ),
              ),
              const SizedBox(height: 24),
              const BiometricToggleWidget(),
              const SizedBox(height: 16),
              const BiometricLoginCredentialTile(),
            ],
          ),
        ),
      ),
    );
  }

  void _showSnackBar(String msg, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: isError ? Colors.red : null,
      ),
    );
  }

  void _showSnackBarWithRetry(String msg, {required VoidCallback onRetry}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: Colors.red,
        action: SnackBarAction(
          label: 'Coba lagi',
          textColor: Colors.white,
          onPressed: onRetry,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final photoUrl = _userData['photoUrl'] as String?;
    final daysPhoto = _daysUntilPhotoChange();

    return Scaffold(
      appBar: AppBar(
        title: const AppVersionTitle(),
        elevation: 0,
        actions: [
          Semantics(
            label: TrakaL10n.of(context).logout,
            button: true,
            child: IconButton(icon: const Icon(Icons.logout), onPressed: _onLogout),
          ),
        ],
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          Positioned.fill(
            child: DelayedLoadingBuilder(
              loading: _loading,
              loadingWidget: const Center(child: ShimmerLoading()),
              placeholder: Center(
                child: Text(
                  'Memuat...',
                  style: TextStyle(
                    fontSize: 14,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              child: SingleChildScrollView(
                  padding: EdgeInsets.only(
                    left: context.responsive.spacing(AppTheme.spacingLg),
                    right: context.responsive.spacing(AppTheme.spacingLg),
                    top: context.responsive.spacing(AppTheme.spacingLg),
                    bottom: context.responsive.spacing(AppTheme.spacingLg) + 80,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (_verificationCompleteCount < 3) ...[
                        const SizedBox(height: 8),
                        Text(
                          TrakaL10n.of(context).verificationCompleteCount(_verificationCompleteCount, 3),
                          style: TextStyle(
                            fontSize: 13,
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 8),
                      ],
                      // Layout horizontal: foto di kiri, nama dan rating di tengah, gambar admin di kanan
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Foto profil di sebelah kiri
                          GestureDetector(
                            onTap: _canChangePhoto() && !_isCheckingFace
                                ? _pickAndVerifyPhoto
                                : null,
                            child: Stack(
                              alignment: Alignment.center,
                              children: [
                                CircleAvatar(
                                  radius: 40, // Ukuran lebih kecil
                                  backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                                  backgroundImage:
                                      (photoUrl != null && photoUrl.isNotEmpty)
                                      ? CachedNetworkImageProvider(photoUrl)
                                      : null,
                                  child: (photoUrl == null || photoUrl.isEmpty)
                                      ? Icon(Icons.camera_alt, size: 32, color: Theme.of(context).colorScheme.onSurfaceVariant)
                                      : null,
                                ),
                                if (_isCheckingFace)
                                  const CircularProgressIndicator(),
                                if (!_canChangePhoto() && !_isCheckingFace)
                                  Positioned(
                                    bottom: 0,
                                    right: 0,
                                    child: Icon(
                                      Icons.lock,
                                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                                      size: 20,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          SizedBox(width: context.responsive.spacing(16)),
                          // Nama dan rating di tengah
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // Nama (dengan centang verifikasi jika semua lengkap) + tombol Platinum; nama bisa turun ke bawah jika panjang
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Expanded(
                                      child: Wrap(
                                        crossAxisAlignment:
                                            WrapCrossAlignment.center,
                                        children: [
                                          Text(
                                            _nameController.text.isNotEmpty
                                                ? _nameController.text
                                                : 'Nama Driver',
                                            style: TextStyle(
                                              fontSize: 20,
                                              fontWeight: FontWeight.bold,
                                              color: Theme.of(context).colorScheme.primary,
                                            ),
                                          ),
                                          if (_isAllProfileVerified)
                                            const SizedBox(width: 4),
                                          if (_isAllProfileVerified)
                                            Icon(
                                              Icons.verified,
                                              size: 20,
                                              color: Colors.green.shade700,
                                            ),
                                        ],
                                      ),
                                    ),
                                    // Badge tier (Basic/Gold/Platinum)
                                    FutureBuilder<(double?, int)>(
                                      future: _driverRatingFuture,
                                          builder: (context, snap) {
                                            final avg = snap.data?.$1;
                                            final count = snap.data?.$2 ?? 0;
                                            final tier = RatingService.getDriverTierLabel(avg, count);
                                            Color tierColor;
                                            switch (tier) {
                                              case 'Platinum':
                                                tierColor = Colors.deepPurple;
                                                break;
                                              case 'Gold':
                                                tierColor = Colors.amber.shade700;
                                                break;
                                              default:
                                                tierColor = Colors.grey.shade600;
                                            }
                                            return Padding(
                                              padding: const EdgeInsets.only(left: 8, right: 8),
                                              child: Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                                decoration: BoxDecoration(
                                                  color: tierColor,
                                                  borderRadius: BorderRadius.circular(12),
                                                ),
                                                child: Text(
                                                  tier,
                                                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white),
                                                ),
                                              ),
                                            );
                                          },
                                        ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                // Rating bintang (5 bintang) + angka + jumlah ulasan
                                FutureBuilder<(double?, int)>(
                                  future: _driverRatingFuture,
                                  builder: (context, snap) {
                                    final avg = snap.data?.$1;
                                    final count = snap.data?.$2 ?? 0;
                                    return Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        ...List.generate(5, (index) {
                                          final starValue = index + 1.0;
                                          IconData icon;
                                          if (avg == null || avg < starValue - 0.5) {
                                            icon = Icons.star_border;
                                          } else if (avg < starValue) {
                                            icon = Icons.star_half;
                                          } else {
                                            icon = Icons.star;
                                          }
                                          return Icon(icon, color: Colors.amber.shade700, size: 20);
                                        }),
                                        if (avg != null || count > 0) ...[
                                          const SizedBox(width: 8),
                                          Text(
                                            avg != null
                                                ? '${avg.toStringAsFixed(1)}${count > 0 ? ' ($count ulasan)' : ''}'
                                                : count > 0
                                                    ? '($count ulasan)'
                                                    : '',
                                            style: TextStyle(
                                              fontSize: 13,
                                              color: Theme.of(context).colorScheme.onSurfaceVariant,
                                            ),
                                          ),
                                        ],
                                      ],
                                    );
                                  },
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      if (daysPhoto != null) ...[
                        const SizedBox(height: 12),
                        Text(
                          'Foto profil dapat diubah setelah $daysPhoto hari lagi.',
                          style: TextStyle(
                            fontSize: 12,
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ] else if (_canChangePhoto()) ...[
                        const SizedBox(height: 12),
                        // Garis dekoratif putih-biru bergantian dari ujung kiri sampai kanan (lebih besar)
                        Row(
                          children: List.generate(20, (index) {
                            return Expanded(
                              child: Container(
                                height:
                                    4, // Lebih besar dari sebelumnya (2 -> 4)
                                color: index % 2 == 0
                                    ? Colors.white
                                    : Theme.of(context).colorScheme.primary,
                              ),
                            );
                          }),
                        ),
                      ],
                      const SizedBox(height: 32), // Jarak antara garis dan menu
                      _buildSectionHeader(TrakaL10n.of(context).verification),
                      const SizedBox(height: 8),
                      GridView.count(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        crossAxisCount: 3,
                        mainAxisSpacing: context.responsive.spacing(12),
                        crossAxisSpacing: context.responsive.spacing(12),
                        childAspectRatio: 0.95,
                        children: [
                          _buildMenuCard(
                            title: TrakaL10n.of(context).vehicleData,
                            icon: Icons.directions_car,
                            verified: _isDataKendaraanFilled,
                            onTap: _showDataKendaraanDialog,
                          ),
                          _buildMenuCard(
                            title: TrakaL10n.of(context).driverVerification,
                            icon: Icons.person_add_alt_1,
                            verified: _isDriverVerified,
                            onTap: _isDriverVerified
                                ? _showVerifikasiSudahBerhasilDialog
                                : _showVerifikasiDriverDialog,
                          ),
                          _buildMenuCard(
                            title: TrakaL10n.of(context).emailAndPhone,
                            icon: Icons.contact_phone,
                            verified: _isEmailDanTelpFilled,
                            onTap: _showEmailDanTelpSheet,
                          ),
                        ],
                      ),
                      SizedBox(height: context.responsive.spacing(16)),
                      _buildSectionHeader(TrakaL10n.of(context).settings),
                      const SizedBox(height: 8),
                      GridView.count(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        crossAxisCount: 2,
                        mainAxisSpacing: context.responsive.spacing(12),
                        crossAxisSpacing: context.responsive.spacing(12),
                        childAspectRatio: 0.95,
                        children: [
                          _buildMenuCard(
                            title: TrakaL10n.of(context).changePassword,
                            icon: Icons.lock_outline,
                            onTap: _showChangePasswordDialog,
                          ),
                          _buildMenuCard(
                            title: TrakaL10n.of(context).paymentHistory,
                            icon: Icons.receipt_long,
                            onTap: () {
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) =>
                                      const PaymentHistoryScreen(isDriver: true),
                                ),
                              );
                            },
                          ),
                          _buildMenuCard(
                            title: TrakaL10n.of(context).driverEarningsTitle,
                            icon: Icons.account_balance_wallet,
                            onTap: () {
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => const DriverEarningsScreen(),
                                ),
                              );
                            },
                          ),
                          _buildMenuCard(
                            title: TrakaL10n.of(context).contributionTariffTitle,
                            icon: Icons.info_outline,
                            onTap: () {
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => const ContributionDriverScreen(),
                                ),
                              );
                            },
                          ),
                          _buildMenuCard(
                            title: TrakaL10n.of(context).language,
                            icon: Icons.language,
                            onTap: _showLanguageSelector,
                          ),
                        ],
                      ),
                      SizedBox(height: context.responsive.spacing(16)),
                      _buildSectionHeader(TrakaL10n.of(context).help),
                      const SizedBox(height: 8),
                      GridView.count(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        crossAxisCount: 3,
                        mainAxisSpacing: context.responsive.spacing(12),
                        crossAxisSpacing: context.responsive.spacing(12),
                        childAspectRatio: 0.95,
                        children: [
                          _buildMenuCard(
                            title: TrakaL10n.of(context).infoAndPromo,
                            icon: Icons.campaign_outlined,
                            onTap: () {
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => const PromoListScreen(role: 'driver'),
                                ),
                              );
                            },
                          ),
                          _buildMenuCard(
                            title: TrakaL10n.of(context).guide,
                            icon: Icons.help_outline,
                            onTap: () {
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => const PanduanAplikasiScreen(),
                                ),
                              );
                            },
                          ),
                          _buildMenuCard(
                            title: TrakaL10n.of(context).suggestionToAdmin,
                            icon: Icons.feedback_outlined,
                            onTap: () {
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => const SaranKeAdminScreen(),
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                      SizedBox(height: context.responsive.spacing(16)),
                      _buildSectionHeader(TrakaL10n.of(context).other),
                      const SizedBox(height: 8),
                      _buildMenuCard(
                        title: TrakaL10n.of(context).locale == AppLocale.id
                            ? 'Kunci dengan sidik jari/wajah'
                            : 'Lock with fingerprint/face',
                        icon: Icons.fingerprint,
                        onTap: _showBiometricSheet,
                      ),
                      _buildLiteModeTile(),
                      _buildMenuCard(
                        title: TrakaL10n.of(context).showLowRamWarning,
                        icon: Icons.memory_outlined,
                        onTap: () async {
                          await LowRamWarningService.resetWarningFlag();
                          if (context.mounted) {
                            await LowRamWarningService.showWarningIfLowRam(context);
                          }
                        },
                      ),
                      _buildMenuCard(
                        title: TrakaL10n.of(context).deleteAccount,
                        icon: Icons.delete_outline,
                        onTap: _showHapusAkunDialog,
                        isDanger: true,
                      ),
                    ],
                  ),
                ),
            ),
          ),
          // Toggle tema (kiri) + Gambar admin (kanan): fixed di bawah viewport
          if (!_loading)
            Positioned(
              bottom: 16,
              left: 16,
              right: 16,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const ThemeToggleWidget(),
                  const AdminContactWidget(),
                ],
              ),
            ),
          // Overlay loading OCR (tanpa Navigator.pop — hindari _dependents.isEmpty)
          if (_isOcrLoading)
            Positioned.fill(
              child: ColoredBox(
                color: Colors.black54,
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surface,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircularProgressIndicator(color: Theme.of(context).colorScheme.primary),
                        const SizedBox(height: 16),
                        Text(
                          'Membaca SIM...',
                          style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Proses mungkin 30–60 detik. Mohon tunggu.',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                        ),
                        if (_isLowRamDevice) ...[
                          const SizedBox(height: 8),
                          Text(
                            'Perangkat RAM rendah terdeteksi — proses dioptimalkan.',
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Theme.of(context).colorScheme.primary,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String label) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Text(
        label,
        style: TextStyle(
          fontSize: context.responsive.fontSize(14),
          fontWeight: FontWeight.w600,
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
    );
  }

  Widget _buildLiteModeTile() {
    return ValueListenableBuilder<bool>(
      valueListenable: LiteModeService.liteModeNotifier,
      builder: (context, isLite, _) {
        return Container(
          margin: EdgeInsets.only(bottom: context.responsive.spacing(8)),
          padding: EdgeInsets.symmetric(
            horizontal: context.responsive.spacing(12),
            vertical: context.responsive.spacing(12),
          ),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(context.responsive.radius(12)),
            border: Border.all(
              color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.5),
              width: 1,
            ),
          ),
          child: Row(
            children: [
              Icon(Icons.speed, color: Theme.of(context).colorScheme.primary, size: 24),
              SizedBox(width: context.responsive.spacing(12)),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      TrakaL10n.of(context).modeLite,
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: context.responsive.fontSize(14),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      TrakaL10n.of(context).modeLiteDescription,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              Switch(
                value: isLite,
                onChanged: (v) => LiteModeService.setLiteMode(v),
              ),
            ],
          ),
        );
      },
    );
  }

  /// Widget untuk membuat menu card dengan efek 3D
  Widget _buildMenuCard({
    required String title,
    required IconData icon,
    required VoidCallback onTap,
    bool verified = false,
    bool isDanger = false,
  }) {
    final color = isDanger ? Colors.red : Theme.of(context).colorScheme.primary;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(context.responsive.radius(12)),
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: context.responsive.spacing(12),
          vertical: context.responsive.spacing(16),
        ),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(context.responsive.radius(12)),
          boxShadow: [
            BoxShadow(
              color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.08),
              blurRadius: 8,
              offset: const Offset(0, 4),
              spreadRadius: 0,
            ),
            BoxShadow(
              color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.04),
              blurRadius: 4,
              offset: const Offset(0, 2),
              spreadRadius: 0,
            ),
          ],
          border: Border.all(
            color: isDanger ? Colors.red.withValues(alpha: 0.5) : Theme.of(context).colorScheme.outline.withValues(alpha: 0.5),
            width: 1,
          ),
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final w = constraints.maxWidth;
            final isCompact = w < 130;
            final iconSize = isCompact
                ? context.responsive.iconSize(36)
                : context.responsive.iconSize(44);
            final fontSize = isCompact
                ? context.responsive.fontSize(13)
                : context.responsive.fontSize(14);
            return Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Stack(
                  alignment: Alignment.center,
                  clipBehavior: Clip.none,
                  children: [
                    Icon(icon, size: iconSize, color: color),
                    if (verified)
                      Positioned(
                        top: -4,
                        right: -4,
                        child: Icon(
                          Icons.verified,
                          size: isCompact ? 16 : 20,
                          color: Colors.green.shade700,
                        ),
                      ),
                  ],
                ),
                SizedBox(height: context.responsive.spacing(isCompact ? 6 : 10)),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: fontSize,
                    fontWeight: FontWeight.w600,
                    color: isDanger ? Colors.red : Theme.of(context).colorScheme.onSurface,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// Dialog verifikasi no. telepon dengan Firebase OTP (SMS).
class _TeleponVerifikasiDialog extends StatefulWidget {
  const _TeleponVerifikasiDialog({
    required this.currentUserId,
    required this.currentPhone,
    required this.onSuccess,
    required this.onCancel,
  });

  final String currentUserId;
  final String currentPhone;
  final VoidCallback onSuccess;
  final VoidCallback onCancel;

  @override
  State<_TeleponVerifikasiDialog> createState() =>
      _TeleponVerifikasiDialogState();
}

class _TeleponVerifikasiDialogState extends State<_TeleponVerifikasiDialog> {
  final _phoneController = TextEditingController();
  final _otpController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  bool _stepOtp = false;
  String? _verificationId;
  String _phoneE164 = '';
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (widget.currentPhone.isNotEmpty) {
      _phoneController.text = widget.currentPhone.replaceFirst(
        RegExp(r'^\+62'),
        '0',
      );
    }
  }

  @override
  void dispose() {
    _phoneController.dispose();
    _otpController.dispose();
    super.dispose();
  }

  Future<bool> _isPhoneUsedByOtherUser(String phoneE164) async {
    final snapshot = await FirebaseFirestore.instance
        .collection('users')
        .where('phoneNumber', isEqualTo: phoneE164)
        .limit(2)
        .get();
    return snapshot.docs.any((doc) => doc.id != widget.currentUserId);
  }

  Future<void> _sendOtp() async {
    _error = null;
    final phone = _phoneController.text.trim();
    if (phone.isEmpty) {
      setState(() => _error = 'No. telepon wajib diisi');
      return;
    }
    _phoneE164 = toE164(phone);
    if (_phoneE164.length < 10) {
      setState(() => _error = 'Format no. telepon tidak valid');
      return;
    }

    setState(() => _loading = true);
    final usedByOther = await _isPhoneUsedByOtherUser(_phoneE164);
    if (!mounted) return;
    if (usedByOther) {
      setState(() {
        _loading = false;
        _error = 'Nomor telepon sudah digunakan.';
      });
      return;
    }

    await FirebaseAuth.instance.verifyPhoneNumber(
      phoneNumber: _phoneE164,
      verificationCompleted: (PhoneAuthCredential credential) async {
        if (!mounted) return;
        await _linkPhone(credential);
        setState(() => _loading = false);
        widget.onSuccess();
      },
      verificationFailed: (FirebaseAuthException e) {
        if (!mounted) return;
        String message = 'Verifikasi gagal. Coba lagi.';
        final code = e.code;
        final msg = (e.message ?? '').toLowerCase();
        if (code == 'missing-client-identifier' ||
            msg.contains('app identifier') ||
            msg.contains('play integrity') ||
            msg.contains('recaptcha')) {
          message =
              'Perangkat/aplikasi belum terverifikasi oleh Firebase. '
              'Pastikan SHA-1 sudah ditambahkan di Firebase Console dan coba di HP asli (bukan emulator). '
              'Lihat docs/FIREBASE_OTP_LANGKAH.md untuk langkah perbaikan.';
        } else if (msg.contains('blocked') ||
            msg.contains('unusual activity')) {
          message =
              'Perangkat ini sementara diblokir karena aktivitas tidak biasa (terlalu banyak percobaan). '
              'Tunggu beberapa jam lalu coba lagi, atau coba dari jaringan lain.';
        } else if (e.message != null && e.message!.isNotEmpty) {
          message = e.message!;
        }
        setState(() {
          _loading = false;
          _error = message;
        });
      },
      codeSent: (String verificationId, int? resendToken) {
        if (!mounted) return;
        setState(() {
          _verificationId = verificationId;
          _stepOtp = true;
          _loading = false;
          _error = null;
        });
      },
      codeAutoRetrievalTimeout: (_) {},
    );
  }

  Future<void> _linkPhone(PhoneAuthCredential credential) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    if (user.phoneNumber != null && user.phoneNumber!.isNotEmpty) {
      try {
        await user.unlink(PhoneAuthProvider.PHONE_SIGN_IN_METHOD);
      } on FirebaseAuthException catch (_) {}
    }
    await user.linkWithCredential(credential);
    final phone = user.phoneNumber ?? _phoneE164;
    await FirebaseFirestore.instance.collection('users').doc(user.uid).update({
      'phoneNumber': phone,
    });
  }

  Future<void> _verifyOtp() async {
    final code = _otpController.text.trim();
    if (code.isEmpty || _verificationId == null) {
      setState(() => _error = 'Masukkan kode dari SMS');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    final usedByOther = await _isPhoneUsedByOtherUser(_phoneE164);
    if (!mounted) return;
    if (usedByOther) {
      setState(() {
        _loading = false;
        _error = 'Nomor telepon sudah digunakan.';
      });
      return;
    }
    try {
      final credential = PhoneAuthProvider.credential(
        verificationId: _verificationId!,
        smsCode: code,
      );
      await _linkPhone(credential);
      if (!mounted) return;
      setState(() => _loading = false);
      widget.onSuccess();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Kode salah atau kedaluwarsa. Coba kirim ulang.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(_stepOtp ? 'Masukkan kode SMS' : 'No. Telepon'),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_error != null) ...[
                Text(
                  _error!,
                  style: const TextStyle(color: Colors.red, fontSize: 12),
                ),
                const SizedBox(height: 8),
              ],
              if (!_stepOtp) ...[
                const Text(
                  'Masukkan no. telepon Indonesia (contoh: 08123456789). Kode verifikasi akan dikirim via SMS.',
                  style: TextStyle(fontSize: 12),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _phoneController,
                  decoration: InputDecoration(
                    labelText: 'No. Telepon',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppTheme.radiusSm)),
                    prefixText: '${IndonesiaConfig.phonePrefix} ',
                  ),
                  keyboardType: TextInputType.phone,
                  onChanged: (_) => setState(() => _error = null),
                ),
              ] else ...[
                Text(
                  'Kode dikirim ke $_phoneE164',
                  style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _otpController,
                  decoration: InputDecoration(
                    labelText: 'Kode verifikasi (6 digit)',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppTheme.radiusSm)),
                  ),
                  keyboardType: TextInputType.number,
                  maxLength: 6,
                  onChanged: (_) => setState(() => _error = null),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _loading ? null : widget.onCancel,
          child: const Text('Batal'),
        ),
        if (!_stepOtp)
          FilledButton(
            onPressed: _loading ? null : _sendOtp,
            child: _loading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Kirim kode SMS'),
          )
        else
          FilledButton(
            onPressed: _loading ? null : _verifyOtp,
            child: _loading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Verifikasi'),
          ),
      ],
    );
  }
}

/// Dialog tambah email dengan verifikasi OTP.
class _TambahEmailOtpDialog extends StatefulWidget {
  const _TambahEmailOtpDialog({
    required this.onSuccess,
    required this.onCancel,
    required this.onError,
  });

  final VoidCallback onSuccess;
  final VoidCallback onCancel;
  final void Function(String msg, {bool isError}) onError;

  @override
  State<_TambahEmailOtpDialog> createState() => _TambahEmailOtpDialogState();
}

class _TambahEmailOtpDialogState extends State<_TambahEmailOtpDialog> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();
  final _otpController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  bool _stepOtp = false;
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    _otpController.dispose();
    super.dispose();
  }

  Future<void> _sendOtp() async {
    if (!_formKey.currentState!.validate()) return;
    final email = _emailController.text.trim().toLowerCase();
    if (!RegExp(r'^[\w.-]+@[\w.-]+\.\w+$').hasMatch(email)) {
      setState(() => _error = 'Format email tidak valid');
      return;
    }
    if (_passwordController.text.length < 8) {
      setState(() => _error = 'Password minimal 8 karakter');
      return;
    }
    if (!RegExp(r'[0-9]').hasMatch(_passwordController.text)) {
      setState(() => _error = 'Password harus ada angka');
      return;
    }
    if (_passwordController.text != _confirmController.text) {
      setState(() => _error = 'Konfirmasi password tidak sama');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await FirebaseFunctions.instance
          .httpsCallable('requestVerificationCode')
          .call({'email': email});
      if (!mounted) return;
      setState(() {
        _stepOtp = true;
        _loading = false;
        _error = null;
      });
    } on FirebaseFunctionsException catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.message ?? 'Gagal mengirim kode OTP.';
      });
    }
  }

  Future<void> _verifyAndLink() async {
    final code = _otpController.text.trim();
    if (code.isEmpty) {
      setState(() => _error = 'Masukkan kode dari email');
      return;
    }
    final email = _emailController.text.trim().toLowerCase();
    final password = _passwordController.text;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final verifyResult = await FirebaseFunctions.instance
          .httpsCallable('verifyRegistrationCode')
          .call({'email': email, 'code': code});
      if ((verifyResult.data as Map?)?['valid'] != true) {
        if (!mounted) return;
        setState(() {
          _loading = false;
          _error = 'Kode salah atau kedaluwarsa.';
        });
        return;
      }
      final user = FirebaseAuth.instance.currentUser;
      if (user == null || !mounted) return;
      final credential = EmailAuthProvider.credential(
        email: email,
        password: password,
      );
      await user.linkWithCredential(credential);
      await user.reload(); // Refresh token setelah link agar tidak trigger logout
      await FirebaseFirestore.instance.collection('users').doc(user.uid).update({
        'email': email,
      });
      if (!mounted) return;
      widget.onSuccess();
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      String msg = e.message ?? 'Gagal menambahkan email.';
      if (e.code == 'email-already-in-use') {
        msg = 'Email sudah digunakan akun lain.';
      } else if (e.code == 'credential-already-in-use') {
        msg = 'Email sudah terhubung ke akun lain.';
      }
      setState(() {
        _loading = false;
        _error = msg;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Kode salah atau kedaluwarsa.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(_stepOtp ? 'Masukkan kode OTP' : 'Tambah Email'),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_error != null) ...[
                Text(
                  _error!,
                  style: const TextStyle(color: Colors.red, fontSize: 12),
                ),
                const SizedBox(height: 8),
              ],
              if (!_stepOtp) ...[
                const Text(
                  'Tambahkan email untuk notifikasi dan login alternatif. Verifikasi OTP ke email dulu.',
                  style: TextStyle(fontSize: 12),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _emailController,
                  decoration: InputDecoration(
                    labelText: 'Email',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppTheme.radiusSm)),
                    hintText: 'contoh@email.com',
                  ),
                  keyboardType: TextInputType.emailAddress,
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) return 'Email wajib diisi';
                    if (!RegExp(r'^[\w.-]+@[\w.-]+\.\w+$').hasMatch(v.trim())) {
                      return 'Format email tidak valid';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _passwordController,
                  decoration: InputDecoration(
                    labelText: 'Password baru',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppTheme.radiusSm)),
                    hintText: 'Min. 8 karakter, ada angka',
                  ),
                  obscureText: true,
                  validator: (v) {
                    if (v == null || v.isEmpty) return 'Password wajib diisi';
                    if (v.length < 8) return 'Minimal 8 karakter';
                    if (!RegExp(r'[0-9]').hasMatch(v)) return 'Harus ada angka';
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _confirmController,
                  decoration: InputDecoration(
                    labelText: 'Konfirmasi password',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppTheme.radiusSm)),
                  ),
                  obscureText: true,
                  validator: (v) {
                    if (v != _passwordController.text) return 'Password tidak sama';
                    return null;
                  },
                ),
              ] else ...[
                Text(
                  'Kode dikirim ke ${_emailController.text.trim().toLowerCase()}',
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _otpController,
                  decoration: InputDecoration(
                    labelText: 'Kode verifikasi (6 digit)',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppTheme.radiusSm)),
                  ),
                  keyboardType: TextInputType.number,
                  maxLength: 6,
                  onChanged: (_) => setState(() => _error = null),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _loading ? null : widget.onCancel,
          child: const Text('Batal'),
        ),
        FilledButton(
          onPressed: _loading
              ? null
              : (_stepOtp ? _verifyAndLink : _sendOtp),
          child: _loading
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(_stepOtp ? 'Simpan' : 'Kirim kode OTP'),
        ),
      ],
    );
  }
}

/// Dialog ubah email dengan verifikasi OTP.
class _UbahEmailOtpDialog extends StatefulWidget {
  const _UbahEmailOtpDialog({
    required this.currentEmail,
    required this.onSuccess,
    required this.onCancel,
    required this.onError,
  });

  final String currentEmail;
  final VoidCallback onSuccess;
  final VoidCallback onCancel;
  final void Function(String msg, {bool isError}) onError;

  @override
  State<_UbahEmailOtpDialog> createState() => _UbahEmailOtpDialogState();
}

class _UbahEmailOtpDialogState extends State<_UbahEmailOtpDialog> {
  final _emailController = TextEditingController();
  final _otpController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  bool _stepOtp = false;
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (widget.currentEmail.isNotEmpty) {
      _emailController.text = widget.currentEmail;
    }
  }

  @override
  void dispose() {
    _emailController.dispose();
    _otpController.dispose();
    super.dispose();
  }

  Future<void> _sendOtp() async {
    if (!_formKey.currentState!.validate()) return;
    final newEmail = _emailController.text.trim().toLowerCase();
    if (newEmail == widget.currentEmail) {
      setState(() => _error = 'Email sama dengan yang sekarang');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await FirebaseFunctions.instance
          .httpsCallable('requestVerificationCode')
          .call({'email': newEmail});
      if (!mounted) return;
      setState(() {
        _stepOtp = true;
        _loading = false;
        _error = null;
      });
    } on FirebaseFunctionsException catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.message ?? 'Gagal mengirim kode OTP.';
      });
    }
  }

  Future<void> _verifyAndUpdate() async {
    final code = _otpController.text.trim();
    if (code.isEmpty) {
      setState(() => _error = 'Masukkan kode dari email');
      return;
    }
    final newEmail = _emailController.text.trim().toLowerCase();
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await FirebaseFunctions.instance
          .httpsCallable('verifyAndUpdateProfileEmail')
          .call({'email': newEmail, 'code': code});
      if (!mounted) return;
      widget.onSuccess();
    } on FirebaseFunctionsException catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.message ?? 'Gagal mengubah email.';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Kode salah atau kedaluwarsa.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(_stepOtp ? 'Masukkan kode OTP' : 'Ubah Email'),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_error != null) ...[
                Text(
                  _error!,
                  style: const TextStyle(color: Colors.red, fontSize: 12),
                ),
                const SizedBox(height: 8),
              ],
              if (!_stepOtp) ...[
                const Text(
                  'Masukkan email baru. Kode verifikasi akan dikirim ke email tersebut.',
                  style: TextStyle(fontSize: 12),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _emailController,
                  decoration: InputDecoration(
                    labelText: 'Email baru',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppTheme.radiusSm)),
                    hintText: 'contoh@email.com',
                  ),
                  keyboardType: TextInputType.emailAddress,
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) return 'Email wajib diisi';
                    if (!RegExp(r'^[\w.-]+@[\w.-]+\.\w+$').hasMatch(v.trim())) {
                      return 'Format email tidak valid';
                    }
                    return null;
                  },
                ),
              ] else ...[
                Text(
                  'Kode dikirim ke ${_emailController.text.trim().toLowerCase()}',
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _otpController,
                  decoration: InputDecoration(
                    labelText: 'Kode verifikasi (6 digit)',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppTheme.radiusSm)),
                  ),
                  keyboardType: TextInputType.number,
                  maxLength: 6,
                  onChanged: (_) => setState(() => _error = null),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _loading ? null : widget.onCancel,
          child: const Text('Batal'),
        ),
        FilledButton(
          onPressed: _loading
              ? null
              : (_stepOtp ? _verifyAndUpdate : _sendOtp),
          child: _loading
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(_stepOtp ? 'Simpan' : 'Kirim kode OTP'),
        ),
      ],
    );
  }
}
