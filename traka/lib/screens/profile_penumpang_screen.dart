import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:crypto/crypto.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';

import '../services/ocr_preprocess_service.dart';
import '../utils/ktp_ocr_extraction.dart';
import 'package:image_picker/image_picker.dart';
import 'package:cached_network_image/cached_network_image.dart';

import 'active_liveness_screen.dart';
import '../config/indonesia_config.dart';
import '../services/face_validation_service.dart';
import '../services/permission_service.dart';
import '../services/verification_log_service.dart';
import '../services/verification_service.dart';
import '../services/face_duplicate_check_service.dart';
import '../services/account_deletion_service.dart';
import '../services/app_analytics_service.dart';
import '../services/auth_redirect_state.dart';
import '../services/low_ram_warning_service.dart';
import '../services/lite_mode_service.dart';
import '../services/image_compression_service.dart';
import '../theme/app_theme.dart';
import '../theme/traka_ui_helpers.dart';
import '../l10n/app_localizations.dart';
import '../services/locale_service.dart';
import '../widgets/traka_l10n_scope.dart';
import '../theme/responsive.dart';
import '../utils/phone_utils.dart';
import '../utils/safe_navigation_utils.dart';
import '../widgets/admin_contact_widget.dart';
import '../widgets/document_capture_guide_dialog.dart';
import '../widgets/admin_verification_banner.dart';
import '../widgets/profile_app_bar_title.dart';
import '../widgets/profile_contact_row.dart';
import '../widgets/profile_face_validation_dialog.dart';
import '../widgets/delayed_loading_builder.dart';
import '../widgets/shimmer_loading.dart';
import '../widgets/theme_toggle_widget.dart';
import '../widgets/biometric_login_credential_tile.dart';
import '../widgets/biometric_toggle_widget.dart';
import '../services/driver_status_service.dart';
import '../services/passenger_proximity_notification_service.dart';
import '../services/receiver_proximity_notification_service.dart';
import '../services/voice_call_incoming_service.dart';
import '../services/passenger_tier_service.dart';
import 'login_screen.dart';
import 'payment_history_screen.dart';
import 'notification_settings_screen.dart';
import 'panduan_aplikasi_screen.dart';
import 'promo_list_screen.dart';
import 'saran_ke_admin_screen.dart';

/// Halaman profil penumpang: tampilan & menu sama seperti driver.
/// Menu: 1. Verifikasi data (KTP), 2. Email & No.Telp, 3. Ubah password.
class ProfilePenumpangScreen extends StatefulWidget {
  const ProfilePenumpangScreen({super.key});

  @override
  State<ProfilePenumpangScreen> createState() => _ProfilePenumpangScreenState();
}

class _ProfilePenumpangScreenState extends State<ProfilePenumpangScreen> {
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

  Future<int>? _cachedCompletedCountFuture;
  Future<int> get _passengerCompletedCountFuture {
    _cachedCompletedCountFuture ??= () async {
      final uid = _auth.currentUser?.uid;
      if (uid == null) return 0;
      return PassengerTierService.getPassengerCompletedOrderCount(uid);
    }();
    return _cachedCompletedCountFuture!;
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

  /// Centang verifikasi: kuning jika admin masih punya permintaan terbuka (sinkron field Firestore / panel admin).
  Color get _verificationCheckColor => VerificationService.hasOpenAdminVerificationRequest(
        _userData,
      )
      ? Colors.amber.shade800
      : Colors.green.shade700;

  /// Penumpang sudah isi verifikasi KTP (nama + NIK tersimpan sebagai hash).
  bool get _isPassengerKTPVerified =>
      _userData['passengerKTPVerifiedAt'] != null ||
      _userData['passengerKTPNomorHash'] != null;

  bool get _hasFaceVerification =>
      (_userData['faceVerificationUrl'] as String?)?.trim().isNotEmpty ?? false;

  /// Selaras [VerificationService.isPenumpangVerified]: nomor HP wajib (bukan cukup email).
  bool get _hasVerifiedPhone =>
      ((_userData['phoneNumber'] as String?) ?? '').trim().isNotEmpty;

  int get _verificationCompleteCount =>
      (_isPassengerKTPVerified ? 1 : 0) +
      (_hasVerifiedPhone ? 1 : 0) +
      (_hasFaceVerification ? 1 : 0);

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

  void _onFacePhotoFromMenu() {
    if (_isCheckingFace) return;
    if (!_canChangePhoto()) {
      final d = _daysUntilPhotoChange();
      if (d != null && mounted) {
        _showSnackBar(TrakaL10n.of(context).photoLockedForDays(d));
      }
      return;
    }
    _pickAndVerifyPhoto();
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
        if (!mounted) return;
        if (mounted) Navigator.of(context).pop();
        if (!skipBlurResult.isValid) {
          if (!mounted) return;
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
        builder: (ctx) => AlertDialog(
          content: Row(
            children: [
              const CircularProgressIndicator(),
              const SizedBox(width: 16),
              Expanded(
                child: Text(TrakaL10n.of(context).checkingFaceUniqueness),
              ),
            ],
          ),
        ),
      );
    }
    try {
      final role = ((_userData['role'] as String?) ?? 'penumpang').trim();
      final dup = await FaceDuplicateCheckService.isDuplicateFace(
        file.path,
        role.isEmpty ? 'penumpang' : role,
        excludeUserId: user.uid,
      );
      if (mounted) Navigator.of(context).pop();
      if (dup) {
        if (mounted) {
          _showSnackBar(TrakaL10n.of(context).duplicateFaceDetected, isError: true);
        }
        return;
      }
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
      final compressedPath = await ImageCompressionService.compressForUpload(file.path);
      final fileToUpload = File(compressedPath);
      final photoRef = FirebaseStorage.instance.ref().child(
        'users/${user.uid}/photo.jpg',
      );
      await photoRef.putFile(fileToUpload);
      final photoUrl = await photoRef.getDownloadURL();
      final updates = <String, dynamic>{
        'photoUrl': photoUrl,
        'photoUpdatedAt': FieldValue.serverTimestamp(),
      };
      final faceRef = FirebaseStorage.instance.ref().child(
        'users/${user.uid}/face_verification.jpg',
      );
      await faceRef.putFile(fileToUpload);
      final faceUrl = await faceRef.getDownloadURL();
      updates['faceVerificationUrl'] = faceUrl;
      updates['faceVerificationLastVerifiedAt'] = FieldValue.serverTimestamp();
      await _firestore.collection('users').doc(user.uid).update(updates);
      VerificationLogService.log(
        userId: user.uid,
        success: true,
        source: VerificationLogSource.profilePenumpang,
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
        source: VerificationLogSource.profilePenumpang,
        errorMessage: 'Gagal mengunggah foto: $e',
      );
      if (mounted) _showSnackBar('Gagal mengunggah foto: $e', isError: true);
    }
  }

  /// Verifikasi wajah/foto profil sudah ada di icon kamera profil. Verifikasi Data = hanya KTP.
  void _showVerifikasiKTPDialog() {
    if (_isPassengerKTPVerified) {
      _showSnackBar(
        'Verifikasi data KTP sudah berhasil. Tidak perlu mengubah kembali.',
      );
      return;
    }
    final hasFace = (_userData['faceVerificationUrl'] as String?)?.trim().isNotEmpty ?? false;
    if (!hasFace) {
      showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text(
            'Verifikasi Data',
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
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text(
          'Verifikasi Data',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        content: const Text(
          'Ambil foto KTP Indonesia. Hanya nomor KTP (NIK) yang disimpan dalam bentuk terenkripsi (SHA-256). '
          'Foto KTP tidak disimpan. Nama akan dibaca untuk dikoreksi lalu disimpan ke profil.',
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
                documentType: DocumentCaptureType.ktp,
              );
              if (ok && mounted) _scanKTP();
            },
            child: const Text('Lanjut'),
          ),
        ],
      ),
    );
  }

  Future<void> _scanKTP() async {
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
        final extracted = KtpOcrExtraction.extractNikAndNama(text);
        if (extracted['nik'] != null && extracted['nama'] != null) {
          final key = '${extracted['nik']}|${extracted['nama']}';
          voteCount[key] = (voteCount[key] ?? 0) + 1;
        }
      }
      Map<String, String?>? extracted;
      if (voteCount.isNotEmpty) {
        final best = voteCount.entries.reduce(
          (a, b) => a.value >= b.value ? a : b,
        );
        final parts = best.key.split('|');
        extracted = {'nik': parts[0], 'nama': parts[1]};
      }

      if (extracted == null || extracted['nik'] == null || extracted['nama'] == null) {
        if (mounted) {
          setState(() => _isOcrLoading = false);
          AuthRedirectState.setInVerificationFlow(false);
          AppAnalyticsService.logOcrFailed(documentType: 'ktp', reason: 'extraction_failed');
          _showSnackBarWithRetry(
            'Gagal membaca data KTP. Pastikan foto KTP jelas dan NIK/NAMA terbaca.',
            onRetry: _scanKTP,
          );
        }
        return;
      }
      if (!mounted) {
        AuthRedirectState.setInVerificationFlow(false);
        return;
      }
      await _showKTPDataConfirmationDialog(
        extracted['nama']!,
        extracted['nik']!,
      );
      AuthRedirectState.setInVerificationFlow(false);
    } catch (e) {
      if (mounted) {
        setState(() => _isOcrLoading = false);
        AuthRedirectState.setInVerificationFlow(false);
        final isTimeout = e.toString().contains('terlalu lama');
        AppAnalyticsService.logOcrFailed(
          documentType: 'ktp',
          reason: isTimeout ? 'timeout' : 'error',
        );
        final msg = isTimeout
            ? 'Proses membaca KTP terlalu lama. Silakan coba foto ulang dengan pencahayaan yang lebih baik.'
            : 'Gagal membaca KTP: $e. Silakan coba foto ulang.';
        if (mounted) _showSnackBarWithRetry(msg, onRetry: _scanKTP);
      }
    }
  }

  Future<void> _showKTPDataConfirmationDialog(String nama, String nik) async {
    final nikController = TextEditingController(text: nik);
    final namaController = TextEditingController(text: nama);
    bool setuju = false;
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
              isSaved ? 'Berhasil' : 'Data KTP yang Dibaca',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            content: SingleChildScrollView(
              child: isSaved
                  ? Text(
                      saveError ?? 'Verifikasi data berhasil. Nama profil mengikuti nama KTP.',
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
                          'Periksa dan koreksi jika perlu. NIK disimpan dalam bentuk terenkripsi (hash).',
                          style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
                        ),
                        const SizedBox(height: 16),
                        TextField(
                          controller: nikController,
                          autocorrect: false,
                          enableSuggestions: false,
                          decoration: InputDecoration(
                            labelText: 'NIK',
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppTheme.radiusSm)),
                            hintText: '16 digit nomor NIK KTP',
                          ),
                          keyboardType: TextInputType.number,
                          maxLength: 16,
                          onChanged: (_) => setDialogState(() {}),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'NIK harus sesuai identitas.',
                          style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
                        ),
                        const SizedBox(height: 16),
                        TextField(
                          controller: namaController,
                          autocorrect: false,
                          enableSuggestions: false,
                          decoration: InputDecoration(
                            labelText: 'Nama sesuai KTP',
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppTheme.radiusSm)),
                          ),
                          onChanged: (_) => setDialogState(() {}),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Nama harus sesuai identitas.',
                          style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
                        ),
                        const SizedBox(height: 16),
                        CheckboxListTile(
                          value: setuju,
                          onChanged: isSaving ? null : (value) =>
                              setDialogState(() => setuju = value ?? false),
                          title: const Text(
                            'Data sudah sesuai dan saya setuju',
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
                  onPressed: (setuju && !isSaving)
                      ? () async {
                          setDialogState(() => isSaving = true);
                          await _saveKTPData(
                            namaController.text.trim(),
                            nikController.text.trim(),
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
    nikController.dispose();
    namaController.dispose();
  }

  String _hashNIK(String nik) {
    final bytes = utf8.encode(nik.trim());
    final digest = sha256.convert(bytes);
    return digest.toString();
  }

  Future<void> _saveKTPData(
    String nama,
    String nik, {
    void Function()? onSuccess,
    void Function(String)? onError,
  }) async {
    final nikClean = nik.replaceAll(RegExp(r'\D'), '');
    if (nama.isEmpty) {
      onError?.call('Nama wajib diisi.');
      if (onError == null && mounted) _showSnackBar('Nama wajib diisi.', isError: true);
      return;
    }
    if (nikClean.length != 16) {
      onError?.call('NIK harus 16 digit sesuai identitas.');
      if (onError == null && mounted) _showSnackBar('NIK harus 16 digit sesuai identitas.', isError: true);
      return;
    }
    final user = _auth.currentUser;
    if (user == null) return;

    final ktpHash = _hashNIK(nikClean);
    try {
      final q = await _firestore
          .collection('users')
          .where('passengerKTPNomorHash', isEqualTo: ktpHash)
          .limit(2)
          .get();
      final dipakaiLain = q.docs.any((doc) => doc.id != user.uid);
      if (dipakaiLain) {
        onError?.call('Nomor KTP sudah digunakan oleh penumpang lain.');
        if (onError == null && mounted) {
          _showSnackBar('Nomor KTP sudah digunakan oleh penumpang lain.', isError: true);
        }
        return;
      }

      await _firestore.collection('users').doc(user.uid).update({
        'displayName': nama,
        'passengerKTPNomorHash': ktpHash,
        'passengerKTPVerifiedAt': FieldValue.serverTimestamp(),
      });
      if (mounted) {
        setState(() => _nameController.text = nama);
        _loadUser();
      }
      onSuccess?.call();
      if (onSuccess == null && mounted) {
        _showSnackBar('Verifikasi data berhasil. Nama profil mengikuti nama KTP.');
      }
    } catch (e) {
      final msg = e.toString().replaceAll('Exception: ', '');
      onError?.call('Gagal menyimpan: $msg');
      if (onError == null && mounted) {
        _showSnackBar('Gagal menyimpan: $msg', isError: true);
      }
    }
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
      shape: TrakaUiHelpers.modalSheetShape(context),
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
                  'No. telepon untuk login (OTP). Email opsional untuk notifikasi dan recovery jika nomor hilang.',
                  style: TextStyle(
                    fontSize: context.responsive.fontSize(12),
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                SizedBox(height: context.responsive.spacing(20)),
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
    final currentPhone = ((_userData['phoneNumber'] as String?) ?? '').trim();
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
            'No. telepon berhasil. Login bisa dengan email atau no. telepon.',
          );
        },
        onCancel: () => Navigator.pop(ctx),
      ),
    );
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
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  l10n.language,
                  style: Theme.of(ctx).textTheme.titleLarge,
                ),
              ),
            ),
            ListTile(
              leading: CircleAvatar(
                radius: 18,
                backgroundColor: Theme.of(ctx).colorScheme.primaryContainer,
                child: Text(
                  'ID',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: Theme.of(ctx).colorScheme.onPrimaryContainer,
                  ),
                ),
              ),
              title: Text(TrakaL10n.of(context).languageIndonesia),
              onTap: () {
                LocaleService.setLocale(AppLocale.id);
                Navigator.pop(ctx);
              },
            ),
            ListTile(
              leading: CircleAvatar(
                radius: 18,
                backgroundColor: Theme.of(ctx).colorScheme.secondaryContainer,
                child: Text(
                  'EN',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: Theme.of(ctx).colorScheme.onSecondaryContainer,
                  ),
                ),
              ),
              title: Text(TrakaL10n.of(context).languageEnglish),
              onTap: () {
                LocaleService.setLocale(AppLocale.en);
                Navigator.pop(ctx);
              },
            ),
            const SizedBox(height: 8),
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
                autocorrect: false,
                enableSuggestions: false,
                decoration: InputDecoration(
                  labelText: TrakaL10n.of(context).oldPassword,
                  border: const OutlineInputBorder(),
                ),
                obscureText: true,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: newC,
                autocorrect: false,
                enableSuggestions: false,
                decoration: InputDecoration(
                  labelText: TrakaL10n.of(context).newPassword,
                  border: const OutlineInputBorder(),
                ),
                obscureText: true,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: confirmC,
                autocorrect: false,
                enableSuggestions: false,
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
      await AccountDeletionService.scheduleAccountDeletion(user.uid, 'penumpang');
      PassengerProximityNotificationService.stop();
      ReceiverProximityNotificationService.stop();
      await DriverStatusService.removeDriverStatus();
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
    PassengerProximityNotificationService.stop();
    ReceiverProximityNotificationService.stop();
    VoiceCallIncomingService.stop();
    // JANGAN hapus deviceId saat logout - biarkan tersimpan untuk verifikasi saat login di device baru
    try {
      await DriverStatusService.removeDriverStatus();
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
        elevation: 0,
        title: const ProfileAppBarTitle(),
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
                  TrakaL10n.of(context).loadingGeneric,
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
                      if (_userData['adminVerificationPendingAt'] != null)
                        AdminVerificationBanner(
                          userData: _userData,
                          onSubmitted: () => _loadUser(),
                        ),
                      if (!VerificationService.isPenumpangVerified(_userData)) ...[
                        Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: Theme.of(context)
                                .colorScheme
                                .primaryContainer
                                .withValues(alpha: 0.6),
                            borderRadius:
                                BorderRadius.circular(AppTheme.radiusSm),
                            border: Border.all(
                              color: Theme.of(context)
                                  .colorScheme
                                  .primary
                                  .withValues(alpha: 0.3),
                            ),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(
                                Icons.info_outline,
                                size: 22,
                                color: Theme.of(context).colorScheme.primary,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  TrakaL10n.of(context).completeDataHint,
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurface,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 20),
                      ],
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
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          GestureDetector(
                            onTap: _isCheckingFace
                                ? null
                                : () {
                                    if (_canChangePhoto()) {
                                      _pickAndVerifyPhoto();
                                    } else {
                                      final d = _daysUntilPhotoChange();
                                      if (d != null && mounted) {
                                        _showSnackBar(
                                          TrakaL10n.of(context).photoLockedForDays(d),
                                        );
                                      }
                                    }
                                  },
                            child: Stack(
                              alignment: Alignment.center,
                              children: [
                                CircleAvatar(
                                  radius: 40,
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
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
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
                                                : 'Nama Penumpang',
                                            style: TextStyle(
                                              fontSize: 20,
                                              fontWeight: FontWeight.bold,
                                              color: Theme.of(context).colorScheme.primary,
                                            ),
                                          ),
                                          if (_isPassengerKTPVerified) ...[
                                            const SizedBox(width: 4),
                                            Icon(
                                              Icons.verified,
                                              size: 20,
                                              color: _verificationCheckColor,
                                            ),
                                          ],
                                        ],
                                      ),
                                    ),
                                    FutureBuilder<int>(
                                      future: _passengerCompletedCountFuture,
                                      builder: (context, snap) {
                                        final count = snap.data ?? 0;
                                        final tier = PassengerTierService.getPassengerTierLabel(count);
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
                                          padding: const EdgeInsets.only(left: 8),
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
                                FutureBuilder<int>(
                                  future: _passengerCompletedCountFuture,
                                  builder: (context, snap) {
                                    final count = snap.data ?? 0;
                                    return Text(
                                      '$count pesanan selesai',
                                      style: TextStyle(
                                        fontSize: 13,
                                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                                      ),
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
                        const SizedBox(height: 8),
                        Text(
                          TrakaL10n.of(context).profileTapPhotoToChangeHint,
                          style: TextStyle(
                            fontSize: 12,
                            height: 1.35,
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                      const SizedBox(height: 32),
                      // Section: Verifikasi
                      _buildSectionHeader(TrakaL10n.of(context).verification),
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
                            title: TrakaL10n.of(context).verifyFacePhoto,
                            icon: Icons.face_retouching_natural_outlined,
                            verified: _hasFaceVerification,
                            verifiedIconColor: _verificationCheckColor,
                            onTap: _onFacePhotoFromMenu,
                          ),
                          _buildMenuCard(
                            title: TrakaL10n.of(context).verifyData,
                            icon: Icons.badge_outlined,
                            verified: _isPassengerKTPVerified,
                            verifiedIconColor: _verificationCheckColor,
                            onTap: _showVerifikasiKTPDialog,
                          ),
                          _buildMenuCard(
                            title: TrakaL10n.of(context).emailAndPhone,
                            icon: Icons.contact_phone,
                            verified: _hasVerifiedPhone,
                            verifiedIconColor: _verificationCheckColor,
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
                                  builder: (_) => const PaymentHistoryScreen(),
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
                                  builder: (_) => const PromoListScreen(role: 'penumpang'),
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
                      SizedBox(height: context.responsive.spacing(12)),
                      _buildMenuCard(
                        title: TrakaL10n.of(context).notificationSettingsTitle,
                        icon: Icons.notifications_outlined,
                        onTap: () {
                          Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => const NotificationSettingsScreen(),
                            ),
                          );
                        },
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
                      SizedBox(height: context.responsive.spacing(10)),
                      _buildLiteModeTile(),
                      SizedBox(height: context.responsive.spacing(10)),
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
                      SizedBox(height: context.responsive.spacing(10)),
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
                          'Membaca KTP...',
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
          fontSize: 14,
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
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.5),
              width: 1,
            ),
          ),
          child: Row(
            children: [
              Icon(Icons.speed, color: Theme.of(context).colorScheme.primary, size: 24),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      TrakaL10n.of(context).modeLite,
                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
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

  Widget _buildMenuCard({
    required String title,
    required IconData icon,
    required VoidCallback onTap,
    bool verified = false,
    Color? verifiedIconColor,
    bool isDanger = false,
  }) {
    final color = isDanger ? Colors.red : Theme.of(context).colorScheme.primary;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(12),
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
            final iconSize = isCompact ? 36.0 : 44.0;
            final fontSize = isCompact ? 13.0 : 14.0;
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
                          color: verifiedIconColor ?? Colors.green.shade700,
                        ),
                      ),
                  ],
                ),
                SizedBox(height: isCompact ? 6 : 10),
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
        setState(() {
          _loading = false;
          _error = e.message ?? 'Verifikasi gagal. Coba lagi.';
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
        _error = 'Kode salah atau kedaluwarsa.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(_stepOtp ? 'Masukkan kode SMS' : 'No. Telepon'),
      content: SingleChildScrollView(
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
                'Masukkan no. telepon Indonesia. Kode verifikasi akan dikirim via SMS.',
                style: TextStyle(fontSize: 12),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _phoneController,
                decoration: InputDecoration(
                  labelText: 'No. Telepon',
                  border: const OutlineInputBorder(),
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
                  'Tambahkan email untuk notifikasi. Verifikasi OTP ke email dulu.',
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
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppTheme.radiusSm),
                    ),
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
