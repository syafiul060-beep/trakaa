import 'dart:async';
import 'dart:io';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/geocoding_service.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:just_audio/just_audio.dart';

import '../models/chat_message_model.dart';
import '../models/order_model.dart';
import '../theme/responsive.dart';
import '../widgets/chat_message_content.dart';
import '../widgets/full_screen_image_viewer.dart';
import '../services/audio_recorder_service.dart';
import '../services/chat_service.dart';
import '../services/fake_gps_overlay_service.dart';
import '../services/location_service.dart';
import '../services/chat_badge_service.dart';
import '../services/order_service.dart';
import '../utils/phone_utils.dart';
import '../widgets/traka_l10n_scope.dart';
import 'package:cached_network_image/cached_network_image.dart';

import 'package:url_launcher/url_launcher.dart';

import 'cek_lokasi_driver_screen.dart';
import 'voice_call_screen.dart';

/// Halaman ruang chat penumpang dengan satu driver (seperti satu percakapan WhatsApp).
/// AppBar: foto + nama driver (dengan ikon verifikasi jika driver terverifikasi), icon Telp.
/// Body: daftar pesan + input kirim pesan. Tanpa kartu Dari/Tujuan dan tanpa tombol Batalkan.
class ChatRoomPenumpangScreen extends StatefulWidget {
  const ChatRoomPenumpangScreen({
    super.key,
    required this.orderId,
    required this.driverUid,
    required this.driverName,
    this.driverPhotoUrl,
    this.driverVerified = false,

    /// Jika diisi, pesan ini dikirim otomatis sekali saat chat dibuka (untuk jenis pesanan).
    this.sendJenisPesananMessage,

    /// URL foto barang (kargo). Dikirim sebagai pesan gambar setelah sendJenisPesananMessage.
    this.sendJenisPesananImageUrl,

    /// True jika user adalah penerima (receiver) kirim barang. Untuk update receiverLastReadAt.
    this.isReceiver = false,
  });

  final String orderId;
  final String driverUid;
  final String driverName;
  final String? driverPhotoUrl;
  final bool driverVerified;
  final String? sendJenisPesananMessage;
  final String? sendJenisPesananImageUrl;
  final bool isReceiver;

  @override
  State<ChatRoomPenumpangScreen> createState() =>
      _ChatRoomPenumpangScreenState();
}

class _ChatRoomPenumpangScreenState extends State<ChatRoomPenumpangScreen> {
  OrderModel? _order;
  bool _orderLoading = true;
  bool _popupShown = false; // Flag agar tidak double-schedule timer
  Timer? _kesepakatanPopupTimer; // Timer 3 detik sebelum popup kesepakatan
  Timer?
  _orderRefreshTimer; // Refresh order berkala agar deteksi saat driver kirim harga
  Timer? _passengerLocationUpdateTimer; // Update lokasi penumpang ke order saat menunggu jemput
  (double, double)? _lastPassengerLocationUpdate; // Lokasi terakhir yang di-push ke Firestore
  /// Foto driver dari widget atau hasil load Firestore (fallback).
  String? _driverPhotoUrl;
  final TextEditingController _textController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _focusNode = FocusNode();

  // Audio recording state
  bool _isRecording = false;
  bool _isRecordingLocked = false; // Untuk locked recording (geser ke atas)
  bool _isButtonPressed = false; // Untuk animasi tombol membesar
  double _buttonDragOffset = 0.0; // Offset Y untuk animasi tombol naik
  int _recordingDuration = 0;
  Timer? _recordingTimer;
  Offset? _panStartPosition; // Untuk tracking posisi awal saat pan

  // Audio player untuk playback
  final Map<String, AudioPlayer> _audioPlayers = {};
  final Map<String, bool> _audioPlaying = {};

  @override
  void initState() {
    super.initState();
    _driverPhotoUrl = widget.driverPhotoUrl;
    _focusNode.addListener(_onFocusChange);
    _loadOrder();
    // Refresh order tiap 5 detik agar ketika driver kirim kesepakatan harga kita deteksi dan jadwalkan popup 3 detik
    _orderRefreshTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (!mounted) return;
      if (_order != null &&
          _order!.agreedPrice != null &&
          !_order!.canPassengerAgree)
        return; // sudah setuju, stop refresh
      _loadOrder();
    });
    if (widget.driverPhotoUrl == null || widget.driverPhotoUrl!.isEmpty) {
      _loadDriverPhoto();
    }
    _markReceivedMessagesAsDeliveredAndRead();
    if (widget.sendJenisPesananMessage != null &&
        widget.sendJenisPesananMessage!.trim().isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _sendJenisPesananMessageOnce();
      });
    }
  }

  void _onFocusChange() {
    if (mounted) setState(() {});
  }

  /// Kirim sekali pesan jenis pesanan hanya jika ini pesan pertama di chat; selanjutnya pengguna isi manual.
  /// Jika ada sendJenisPesananImageUrl (foto barang kargo), kirim juga sebagai pesan gambar setelah teks.
  Future<void> _sendJenisPesananMessageOnce() async {
    final text = widget.sendJenisPesananMessage?.trim();
    if (text == null || text.isEmpty || widget.orderId.isEmpty) return;
    final alreadyHasMessage = await ChatService.hasAnyMessage(widget.orderId);
    if (alreadyHasMessage) return;
    await ChatService.sendMessage(widget.orderId, text);
    final imageUrl = widget.sendJenisPesananImageUrl?.trim();
    if (imageUrl != null && imageUrl.isNotEmpty) {
      await ChatService.sendImageMessageFromUrl(widget.orderId, imageUrl);
    }
  }

  /// Penerima (penumpang/receiver) buka chat: tandai pesan driver jadi delivered lalu read.
  Future<void> _markReceivedMessagesAsDeliveredAndRead() async {
    // Optimistic: badge hilang segera
    ChatBadgeService.instance.markAsReadOptimistic(widget.orderId);
    // Update lastReadAt segera (tanpa tunggu markAsDelivered/Read)
    if (widget.isReceiver) {
      await OrderService.setReceiverLastReadAt(widget.orderId);
    } else {
      await OrderService.setPassengerLastReadAt(widget.orderId);
    }
    // Mark delivered & read di background (untuk status pesan)
    unawaited(ChatService.markAsDelivered(widget.orderId));
    Future.delayed(const Duration(milliseconds: 600)).then((_) async {
      if (!mounted) return;
      await ChatService.markAsRead(widget.orderId);
    });
  }

  Future<void> _loadDriverPhoto() async {
    final info = await ChatService.getUserInfo(widget.driverUid);
    final photoUrl = info['photoUrl'] as String?;
    if (mounted && (photoUrl != null && photoUrl.isNotEmpty)) {
      setState(() => _driverPhotoUrl = photoUrl);
    }
  }

  @override
  void dispose() {
    _kesepakatanPopupTimer?.cancel();
    _orderRefreshTimer?.cancel();
    _passengerLocationUpdateTimer?.cancel();
    _focusNode.removeListener(_onFocusChange);
    _focusNode.dispose();
    _textController.dispose();
    _scrollController.dispose();
    _recordingTimer?.cancel();
    // Dispose semua audio player
    for (final player in _audioPlayers.values) {
      player.dispose();
    }
    _audioPlayers.clear();
    super.dispose();
  }

  Future<void> _loadOrder() async {
    final order = await OrderService.getOrderById(widget.orderId);
    if (mounted) {
      final shouldSchedulePopup =
          order != null &&
          order.canPassengerAgree &&
          order.agreedPrice != null &&
          !_popupShown;

      setState(() {
        _order = order;
        _orderLoading = false;
      });

      // Driver sudah kirim harga: jadwalkan popup konfirmasi kesepakatan setelah 3 detik, muncul terus sampai penumpang setuju
      if (shouldSchedulePopup) {
        _scheduleKesepakatanPopup();
      }

      // Order agreed & belum dijemput: mulai update lokasi penumpang ke Firestore (untuk live tracking driver)
      _startOrStopPassengerLocationUpdates();
    }
  }

  /// Mulai atau hentikan timer update lokasi penumpang ke order.
  void _startOrStopPassengerLocationUpdates() {
    final order = _order;
    final shouldUpdate = order != null &&
        order.status == OrderService.statusAgreed &&
        !order.hasDriverScannedPassenger;

    if (shouldUpdate && _passengerLocationUpdateTimer == null) {
      _passengerLocationUpdateTimer =
          Timer.periodic(const Duration(seconds: 30), (_) {
        _updatePassengerLocationToOrder();
      });
    } else if (!shouldUpdate && _passengerLocationUpdateTimer != null) {
      _passengerLocationUpdateTimer?.cancel();
      _passengerLocationUpdateTimer = null;
      _lastPassengerLocationUpdate = null;
    }
  }

  /// Ambil lokasi saat ini dan update ke order jika berubah ≥50m.
  Future<void> _updatePassengerLocationToOrder() async {
    if (!mounted || _order == null) return;
    if (_order!.status != OrderService.statusAgreed ||
        _order!.hasDriverScannedPassenger) {
      return;
    }
    try {
      final result = await LocationService.getCurrentPositionWithMockCheck();
      if (result.isFakeGpsDetected) {
        if (mounted) FakeGpsOverlayService.showOverlay();
        return;
      }
      final position = result.position;
      if (!mounted || position == null) return;
      final lat = position.latitude;
      final lng = position.longitude;
      final last = _lastPassengerLocationUpdate;
      final shouldUpdate = last == null ||
          Geolocator.distanceBetween(last.$1, last.$2, lat, lng) >= 50;
      if (shouldUpdate) {
        final ok = await OrderService.updatePassengerLocation(
          widget.orderId,
          passengerLat: lat,
          passengerLng: lng,
        );
        if (ok && mounted) {
          _lastPassengerLocationUpdate = (lat, lng);
        }
      }
    } catch (_) {}
  }

  /// Jadwalkan popup kesepakatan 3 detik lagi; setelah tampil, jika penumpang tutup (Batal) akan dijadwalkan lagi.
  void _scheduleKesepakatanPopup() {
    _kesepakatanPopupTimer?.cancel();
    _popupShown = true;
    _kesepakatanPopupTimer = Timer(const Duration(seconds: 3), () {
      _kesepakatanPopupTimer = null;
      if (!mounted) return;
      if (_order == null ||
          !_order!.canPassengerAgree ||
          _order!.agreedPrice == null) {
        _popupShown = false;
        return;
      }
      _showDialogKesepakatanPenumpangAuto();
    });
  }

  /// Format alamat: hanya kecamatan dan kabupaten, tanpa provinsi.
  String _formatAlamatKecamatanKabupaten(String alamat) {
    if (alamat.isEmpty) return alamat;
    final parts = alamat
        .split(',')
        .map((p) => p.trim())
        .where((p) => p.isNotEmpty)
        .toList();
    if (parts.isEmpty) return alamat;

    String? kecamatan;
    String? kabupaten;

    for (final part in parts) {
      final lower = part.toLowerCase();
      if (lower.contains('kecamatan') || lower.contains('kec.')) {
        kecamatan = part;
      } else if (lower.contains('kabupaten') ||
          lower.contains('kab.') ||
          lower.contains('kota ') ||
          (lower.contains('kota') && !lower.contains('kabupaten'))) {
        kabupaten = part;
      }
    }

    if (kecamatan == null && kabupaten == null && parts.length >= 2) {
      kecamatan = parts[0];
      kabupaten = parts[1];
    } else if (kecamatan == null && parts.isNotEmpty) {
      kecamatan = parts[0];
    }

    final result = <String>[];
    if (kecamatan != null) result.add(kecamatan);
    if (kabupaten != null && kabupaten != kecamatan) result.add(kabupaten);

    return result.isEmpty ? alamat : result.join(', ');
  }

  Future<void> _sendMessage() async {
    final text = _textController.text.trim();
    if (text.isEmpty) return;

    final orderId = widget.orderId;
    if (orderId.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(TrakaL10n.of(context).invalidOrderData),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }

    _textController.clear();
    final ok = await ChatService.sendMessage(orderId, text);
    if (!mounted) return;
    if (!ok) {
      _textController.text = text;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            ChatService.lastBlockedReason ??
                TrakaL10n.of(context).failedToSendMessage,
          ),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 4),
        ),
      );
      return;
    }
    _scrollToBottom(); // Scroll ke bawah (pesan terbaru)
  }

  /// Mulai rekam audio (hold to record)
  Future<void> _startRecording({bool isLocked = false}) async {
    if (_isRecording) return;

    // Getaran saat pertama kali mulai rekam
    HapticFeedback.mediumImpact();

    final path = await AudioRecorderService.startRecording();
    if (path == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Tidak dapat mengakses mikrofon. Periksa izin aplikasi.',
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }

    setState(() {
      _isRecording = true;
      _isRecordingLocked = isLocked;
      _recordingDuration = 0;
    });

    // Timer untuk update durasi rekaman
    _recordingTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) {
        setState(() {
          _recordingDuration = AudioRecorderService.currentDuration;
        });
      }
    });
  }

  /// Stop rekam audio dan kirim
  Future<void> _stopRecording({bool send = true}) async {
    if (!_isRecording) return;

    _recordingTimer?.cancel();
    _recordingTimer = null;

    final result = await AudioRecorderService.stopRecording();
    setState(() {
      _isRecording = false;
      _isRecordingLocked = false;
      _isButtonPressed = false;
      _buttonDragOffset = 0.0;
      _recordingDuration = 0;
    });

    if (!send || result == null) {
      // Jika tidak dikirim, hapus file rekaman
      if (result != null) {
        try {
          await result.file.delete();
        } catch (e) {
          // Ignore error saat hapus file
        }
      }
      return;
    }

    final orderId = widget.orderId;
    if (orderId.isEmpty) return;

    // Validasi file sebelum kirim
    if (!await result.file.exists()) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('File audio tidak ditemukan. Coba rekam lagi.'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }

    // Validasi durasi minimal 1 detik
    if (result.duration < 1) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Durasi rekaman terlalu pendek. Minimal 1 detik.'),
            backgroundColor: Colors.red,
          ),
        );
      }
      // Hapus file yang terlalu pendek
      try {
        await result.file.delete();
      } catch (e) {
        // Ignore
      }
      return;
    }

    // Kirim audio dengan loading indicator
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Row(
            children: [
              SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              ),
              SizedBox(width: 12),
              Text('Mengirim pesan suara...'),
            ],
          ),
          duration: Duration(seconds: 2),
          backgroundColor: Theme.of(context).colorScheme.primary,
        ),
      );
    }

    final ok = await ChatService.sendAudioMessage(
      orderId,
      result.file,
      result.duration,
    );

    if (!mounted) return;

    // Tutup loading indicator
    ScaffoldMessenger.of(context).hideCurrentSnackBar();

    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            ChatService.lastBlockedReason ??
                TrakaL10n.of(context).failedToSendVoice,
          ),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 4),
        ),
      );
    } else {
      _scrollToBottom();
    }
  }

  /// Cancel rekaman (hapus tanpa kirim)
  Future<void> _cancelRecording() async {
    await _stopRecording(send: false);
  }

  /// Build tombol voice dengan gesture seperti WhatsApp
  Widget _buildVoiceButton() {
    return GestureDetector(
      onPanStart: (details) {
        _panStartPosition = details.globalPosition;
        setState(() {
          _isButtonPressed = true;
          _buttonDragOffset = 0.0;
        });
        _startRecording();
      },
      onPanUpdate: (details) {
        if (!_isRecording || _panStartPosition == null) return;

        // Hitung offset Y (negatif = naik ke atas)
        final dy = _panStartPosition!.dy - details.globalPosition.dy;

        // Update posisi tombol (maksimal naik 200px)
        setState(() {
          _buttonDragOffset = dy.clamp(0.0, 200.0);
        });

        // Jika digeser ke atas lebih dari 50px, lock recording
        if (dy > 50 && !_isRecordingLocked) {
          // Lock recording
          HapticFeedback.mediumImpact();
          setState(() {
            _isRecordingLocked = true;
          });
        } else if (dy <= 50 && _isRecordingLocked) {
          // Unlock recording
          setState(() {
            _isRecordingLocked = false;
          });
        }
      },
      onPanEnd: (details) {
        setState(() {
          _isButtonPressed = false;
          _buttonDragOffset = 0.0;
        });
        _panStartPosition = null;

        // Jika tidak locked, kirim langsung saat dilepas
        if (_isRecording && !_isRecordingLocked) {
          _stopRecording(send: true);
        }
        // Jika locked, tetap rekam (user harus klik tombol kirim)
      },
      onPanCancel: () {
        setState(() {
          _isButtonPressed = false;
          _buttonDragOffset = 0.0;
        });
        _panStartPosition = null;
        // Jika tidak locked, kirim langsung saat cancel
        if (_isRecording && !_isRecordingLocked) {
          _stopRecording(send: true);
        }
      },
      child: Transform.translate(
        offset: Offset(0, -_buttonDragOffset),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeInOut,
          width: _isButtonPressed ? 56 : 48,
          height: _isButtonPressed ? 56 : 48,
          decoration: BoxDecoration(
            color: _isRecordingLocked
                ? Colors.green
                : Theme.of(context).colorScheme.primary, // Biru, hijau jika locked
            shape: BoxShape.circle,
            boxShadow: _isButtonPressed
                ? [
                    BoxShadow(
                      color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.3),
                      blurRadius: 8,
                      offset: const Offset(0, 4),
                    ),
                  ]
                : null,
          ),
          child: IconButton(
            icon: Icon(
              _isRecordingLocked ? Icons.lock : Icons.mic,
              color: Colors.white,
            ),
            onPressed: null, // Disabled, hanya gesture yang bekerja
          ),
        ),
      ),
    );
  }

  /// Pick gambar dari gallery
  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final image = await picker.pickImage(source: ImageSource.gallery);
    if (image == null) return;

    final orderId = widget.orderId;
    if (orderId.isEmpty) return;

    final ok = await ChatService.sendImageMessage(orderId, File(image.path));
    if (!mounted) return;
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            ChatService.lastBlockedReason ??
                TrakaL10n.of(context).failedToSendImage,
          ),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 4),
        ),
      );
    } else {
      _scrollToBottom();
    }
  }

  /// Pick video dari gallery
  Future<void> _pickVideo() async {
    final picker = ImagePicker();
    final video = await picker.pickVideo(source: ImageSource.gallery);
    if (video == null) return;

    final orderId = widget.orderId;
    if (orderId.isEmpty) return;

    final ok = await ChatService.sendVideoMessage(orderId, File(video.path));
    if (!mounted) return;
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(TrakaL10n.of(context).failedToSendVideo),
          backgroundColor: Colors.red,
        ),
      );
    } else {
      _scrollToBottom();
    }
  }

  /// Tampilkan dialog pilih gambar atau video
  void _showMediaPicker() {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('Pilih Gambar'),
              onTap: () {
                Navigator.pop(context);
                _pickImage();
              },
            ),
            ListTile(
              leading: const Icon(Icons.video_library),
              title: const Text('Pilih Video'),
              onTap: () {
                Navigator.pop(context);
                _pickVideo();
              },
            ),
          ],
        ),
      ),
    );
  }

  void _openFullScreenImage(String? url) {
    if (url == null || url.isEmpty) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => FullScreenImageViewer(imageUrl: url),
      ),
    );
  }

  /// Toggle audio playback
  Future<void> _toggleAudioPlayback(ChatMessageModel msg) async {
    if (msg.audioUrl == null) return;

    final messageId = msg.id;
    final isPlaying = _audioPlaying[messageId] ?? false;

    if (isPlaying) {
      // Stop playback
      final player = _audioPlayers[messageId];
      await player?.stop();
      setState(() {
        _audioPlaying[messageId] = false;
      });
    } else {
      // Start playback
      AudioPlayer player;
      if (_audioPlayers.containsKey(messageId)) {
        player = _audioPlayers[messageId]!;
      } else {
        player = AudioPlayer();
        _audioPlayers[messageId] = player;
        await player.setUrl(msg.audioUrl!);
        player.playerStateStream.listen((state) {
          if (state.processingState == ProcessingState.completed) {
            if (mounted) {
              setState(() {
                _audioPlaying[messageId] = false;
              });
            }
          }
        });
      }

      await player.play();
      if (mounted) {
        setState(() {
          _audioPlaying[messageId] = true;
        });
      }
    }
  }

  /// Scroll ke bawah (pesan terbaru) seperti WhatsApp standar
  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController
              .position
              .maxScrollExtent, // Scroll ke bawah (pesan terbaru)
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  /// Dialog Kesepakatan otomatis: muncul 3 detik setelah driver kirim harga, muncul terus sampai penumpang setuju.
  void _showDialogKesepakatanPenumpangAuto() {
    if (_order == null ||
        !_order!.canPassengerAgree ||
        _order!.agreedPrice == null)
      return;
    final order = _order!;
    final harga = order.agreedPrice!;
    bool checkboxValue = false;

    void onBatalTapped() {
      Navigator.of(context).pop(); // Tutup dialog kesepakatan dulu
      showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (ctx2) => AlertDialog(
          title: const Text('Konfirmasi'),
          content: const Text(
            'Apakah Anda ingin membatalkan kesepakatan ini / ingin membuat kesepakatan baru?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx2, false),
              child: const Text('Tidak'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx2, true),
              child: const Text('Ya'),
            ),
          ],
        ),
      ).then((yes) async {
        if (yes == true && mounted && _order != null) {
          await OrderService.resetAgreementByPassenger(_order!.id);
          await ChatService.sendMessage(
            _order!.id,
            'Penumpang membatalkan kesepakatan dan ingin membuat kesepakatan baru.',
          );
          if (mounted) {
            _popupShown = true; // Agar popup tidak muncul lagi
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  'Pesan telah dikirim ke driver. Driver dapat mengirim kesepakatan harga baru.',
                ),
                behavior: SnackBarBehavior.floating,
              ),
            );
          }
        }
      });
    }

    // Teks dinamis sesuai jenis pesanan (penumpang sendiri / kerabat / kirim barang)
    final String dialogTitle = order.isKirimBarang
        ? 'Konfirmasi Tawaran Biaya Pengiriman'
        : order.isTravelKerabat
            ? 'Konfirmasi Tawaran Harga Perjalanan'
            : 'Konfirmasi Tawaran Harga Perjalanan';
    final String pengantar = order.isKirimBarang
        ? 'Driver mengirim tawaran biaya untuk pengiriman barang Anda:'
        : order.isTravelKerabat
            ? 'Driver mengirim tawaran harga untuk perjalanan Anda dan kerabat (${order.totalPenumpang} orang):'
            : 'Driver mengirim tawaran harga untuk perjalanan Anda:';
    final String labelHarga = order.isKirimBarang
        ? 'Biaya pengiriman yang ditawarkan'
        : order.isTravelKerabat
            ? 'Harga yang ditawarkan (${order.totalPenumpang} orang)'
            : 'Harga yang ditawarkan';
    final String catatanBayar = order.isKirimBarang
        ? 'Pembayaran langsung ke driver saat barang dijemput/diantar. Harga wajib sesuai kesepakatan.'
        : 'Pembayaran langsung ke driver saat bertemu. Harga wajib sesuai kesepakatan.';
    final String checkboxText = order.isKirimBarang
        ? 'Saya setuju dengan biaya pengiriman di atas. Jika driver meminta harga berbeda, saya akan melaporkan.'
        : order.isTravelKerabat
            ? 'Saya setuju dengan harga di atas untuk perjalanan kami (${order.totalPenumpang} orang). Jika driver meminta harga berbeda, saya akan melaporkan.'
            : 'Saya setuju dengan harga di atas untuk perjalanan saya. Jika driver meminta harga berbeda, saya akan melaporkan.';
    final hargaFormatted = harga.toStringAsFixed(0).replaceAllMapped(
        RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]}.');

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (dialogContext, setDialogState) {
          return PopScope(
            canPop: false,
            child: AlertDialog(
              titlePadding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
              contentPadding: const EdgeInsets.fromLTRB(24, 8, 24, 8),
              actionsPadding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
              title: SizedBox(
                width: double.maxFinite,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      dialogTitle,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      textAlign: TextAlign.left,
                    ),
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Theme.of(context)
                            .colorScheme
                            .primaryContainer
                            .withValues(alpha: 0.6),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        order.orderTypeDisplayLabel,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Theme.of(context).colorScheme.onPrimaryContainer,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      pengantar,
                      style: TextStyle(
                        fontSize: 13,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.maxFinite,
                      child: Text(
                        widget.driverName,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    if (order.originText.isNotEmpty) ...[
                      SizedBox(
                        width: double.maxFinite,
                        child: Text(
                          'Dari: ${_formatAlamatKecamatanKabupaten(order.originText)}',
                          style: TextStyle(
                            fontSize: 13,
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                      const SizedBox(height: 4),
                    ],
                    if (order.destText.isNotEmpty) ...[
                      SizedBox(
                        width: double.maxFinite,
                        child: Text(
                          'Tujuan: ${_formatAlamatKecamatanKabupaten(order.destText)}',
                          style: TextStyle(
                            fontSize: 13,
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],
                    SizedBox(
                      width: double.maxFinite,
                      child: Text(
                        '$labelHarga: Rp $hargaFormatted',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      catatanBayar,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 16),
                    CheckboxListTile(
                      value: checkboxValue,
                      onChanged: (v) {
                        setDialogState(() {
                          checkboxValue = v ?? false;
                        });
                      },
                      title: Text(
                        checkboxText,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => onBatalTapped(),
                  child: const Text('Tolak'),
                ),
                FilledButton(
                  onPressed: checkboxValue
                      ? () {
                          Navigator.pop(dialogContext);
                          _onSetujuiKesepakatan();
                        }
                      : null,
                  child: const Text('Setujui & Lanjutkan'),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Future<void> _onSetujuiKesepakatan() async {
    if (_order == null) return;

    final hasPermission = await LocationService.requestPermission();
    if (!hasPermission) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Izin lokasi diperlukan untuk menyelesaikan kesepakatan.',
            ),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return;
    }

    final result = await LocationService.getCurrentPositionWithMockCheck();
    if (result.isFakeGpsDetected) {
      if (mounted) FakeGpsOverlayService.showOverlay();
      return;
    }
    final position = result.position;
    if (position == null || !mounted) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Tidak dapat memperoleh lokasi. Coba lagi.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return;
    }

    String locationText = '${position.latitude}, ${position.longitude}';
    try {
      final placemarks = await GeocodingService.placemarkFromCoordinates(
        position.latitude,
        position.longitude,
      );
      if (placemarks.isNotEmpty) {
        final p = placemarks.first;
        final parts = <String>[];
        if ((p.name ?? '').isNotEmpty) parts.add(p.name!);
        if ((p.thoroughfare ?? '').isNotEmpty) parts.add(p.thoroughfare!);
        if ((p.subLocality ?? '').isNotEmpty) parts.add(p.subLocality!);
        if ((p.administrativeArea ?? '').isNotEmpty) {
          parts.add(p.administrativeArea!);
        }
        if (parts.isNotEmpty) locationText = parts.join(', ');
      }
    } catch (_) {}

    setState(() {});
    final (ok, barcodePayload) = await OrderService.setPassengerAgreed(
      _order!.id,
      passengerLat: position.latitude,
      passengerLng: position.longitude,
      passengerLocationText: locationText,
    );
    if (!mounted) return;
    setState(() {});
    if (ok) {
      _popupShown = false;
      await ChatService.sendMessage(
        _order!.id,
        'Penumpang sudah mensetujui kesepakatan.',
      );
      // Barcode tidak dikirim ke chat. Driver tampilkan barcode di Data Order untuk di-scan penumpang.
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Kesepakatan berhasil. Pesanan aktif di menu Pesanan.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      _loadOrder();
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    return Scaffold(
      appBar: AppBar(
        elevation: 0,
        title: Row(
          children: [
            CircleAvatar(
              radius: 20,
              backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
              backgroundImage:
                  _driverPhotoUrl != null && _driverPhotoUrl!.isNotEmpty
                  ? CachedNetworkImageProvider(_driverPhotoUrl!)
                  : null,
              child: _driverPhotoUrl == null || _driverPhotoUrl!.isEmpty
                  ? Icon(Icons.person, color: Theme.of(context).colorScheme.onSurfaceVariant)
                  : null,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          widget.driverName,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (widget.driverVerified) ...[
                        const SizedBox(width: 6),
                        Icon(
                          Icons.verified,
                          size: 20,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ],
                    ],
                  ),
                  if (_order?.orderTypeDisplayLabel != null &&
                      _order!.orderTypeDisplayLabel.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (_order!.isKirimBarang)
                          Padding(
                            padding: const EdgeInsets.only(right: 4),
                            child: Icon(
                              _order!.barangCategory == OrderModel.barangCategoryDokumen
                                  ? Icons.mail_outline
                                  : Icons.inventory_2_outlined,
                              size: 14,
                              color: Theme.of(context).colorScheme.onSurfaceVariant,
                            ),
                          ),
                        Expanded(
                          child: Text(
                            _order!.orderTypeDisplayLabel,
                            style: TextStyle(
                              fontSize: 12,
                              color: Theme.of(context).colorScheme.onSurfaceVariant,
                              fontWeight: FontWeight.w500,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
        actions: [
          if (_order?.status == OrderService.statusCancelled)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: 'Hapus chat',
              onPressed: () async {
                final confirmed = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('Hapus Chat'),
                    content: const Text(
                      'Hapus obrolan ini dari daftar Pesan? Pesanan yang dibatalkan tetap tersimpan di Data Order.',
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        child: const Text('Batal'),
                      ),
                      FilledButton(
                        onPressed: () => Navigator.pop(ctx, true),
                        style: FilledButton.styleFrom(backgroundColor: Colors.red),
                        child: const Text('Hapus'),
                      ),
                    ],
                  ),
                );
                if (confirmed == true && mounted) {
                  final err = widget.isReceiver
                      ? await OrderService.hideChatForReceiver(widget.orderId)
                      : await OrderService.hideChatForPassenger(widget.orderId);
                  if (mounted) {
                    if (err == null) {
                      Navigator.of(context).pop();
                    } else {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(err), backgroundColor: Colors.red),
                      );
                    }
                  }
                }
              },
            ),
          if (_order?.isKirimBarang == true)
            IconButton(
              icon: const Icon(Icons.location_on),
              tooltip: 'Cek lokasi driver',
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                    builder: (_) => CekLokasiDriverScreen(
                      orderId: widget.orderId,
                      order: _order,
                    ),
                  ),
                );
              },
            ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.call),
            tooltip: 'Panggilan suara atau telepon',
            onSelected: (value) async {
              if (value == 'voice') {
                final uid = FirebaseAuth.instance.currentUser?.uid;
                if (uid == null || _order == null) return;
                final (canUse, reason) = await OrderService.canUseVoiceCall(_order!);
                if (!mounted) return;
                if (!canUse) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('$reason. Gunakan telepon biasa jika driver punya no. telepon.'),
                      backgroundColor: Colors.orange,
                    ),
                  );
                  return;
                }
                final callerName = _order?.passengerName ??
                    FirebaseAuth.instance.currentUser?.displayName ??
                    'Penumpang';
                if (!mounted) return;
                Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                    builder: (_) => VoiceCallScreen(
                      orderId: widget.orderId,
                      remoteUid: widget.driverUid,
                      remoteName: widget.driverName,
                      remotePhotoUrl: _driverPhotoUrl ?? widget.driverPhotoUrl,
                      isCaller: true,
                      callerName: callerName,
                    ),
                  ),
                );
              } else if (value == 'phone') {
                final info = await ChatService.getUserInfo(widget.driverUid);
                final phone = (info['phoneNumber'] as String?)?.trim();
                if (!mounted) return;
                if (phone == null || phone.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Driver belum menambahkan nomor telepon di profil.'),
                      backgroundColor: Colors.orange,
                    ),
                  );
                  return;
                }
                final phoneE164 = toE164(phone);
                final uri = Uri.parse('tel:$phoneE164');
                try {
                  if (await canLaunchUrl(uri)) {
                    await launchUrl(uri, mode: LaunchMode.externalApplication);
                  } else {
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Tidak dapat membuka aplikasi telepon')),
                      );
                    }
                  }
                } catch (_) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Gagal membuka telepon')),
                    );
                  }
                }
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'voice',
                child: Row(
                  children: [
                    Icon(Icons.voice_chat),
                    SizedBox(width: 12),
                    Text('Panggilan suara (dalam radius 5 km)'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'phone',
                child: Row(
                  children: [
                    Icon(Icons.phone),
                    SizedBox(width: 12),
                    Text('Telepon biasa'),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: SafeArea(
        child: Container(
          decoration: BoxDecoration(
            image: DecorationImage(
              image: AssetImage('assets/images/logo_traka.png'),
              fit: BoxFit.contain,
              opacity:
                  0.05, // Logo semi-transparent agar tidak mengganggu pembacaan pesan
              alignment: Alignment.center,
            ),
          ),
          child: Column(
            children: [
              if (_order != null && _order!.hasDriverScannedPassenger)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                  color: Colors.green.shade50,
                  child: Row(
                    children: [
                      Icon(
                        Icons.directions_car,
                        color: Colors.green.shade700,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Perjalanan aktif. Saat sampai tujuan, buka Data Order > Driver lalu scan barcode driver.',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.green.shade900,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              Expanded(
                child: StreamBuilder<List<ChatMessageModel>>(
                  stream: ChatService.streamMessages(widget.orderId),
                  builder: (context, snap) {
                    // Loading hanya saat benar-benar masih waiting pertama kali dan belum ada data
                    if (snap.connectionState == ConnectionState.waiting &&
                        !snap.hasData) {
                      return const Center(child: CircularProgressIndicator());
                    }

                    // Ambil data messages
                    final messages = snap.data ?? [];

                    // Jika belum ada pesan, tampilkan pemberitahuan yang profesional
                    if (messages.isEmpty) {
                      return Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.chat_bubble_outline,
                              size: 64,
                              color: Theme.of(context).colorScheme.onSurfaceVariant,
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'Belum ada pesan.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 16,
                                color: Theme.of(context).colorScheme.onSurfaceVariant,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Mulai obrolan dengan driver.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 14,
                                color: Theme.of(context).colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      );
                    }

                    // Jika ada pesan, tampilkan daftar pesan
                    // Auto-scroll ke bawah (pesan terbaru) saat pertama kali load
                    if (messages.isNotEmpty) {
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (_scrollController.hasClients) {
                          _scrollController.jumpTo(
                            _scrollController.position.maxScrollExtent,
                          );
                        }
                      });
                    }

                    return ListView.builder(
                      controller: _scrollController,
                      reverse:
                          false, // Pesan terbaru di bawah (tidak di-reverse)
                      padding: EdgeInsets.symmetric(
                        horizontal: context.responsive.spacing(16),
                        vertical: context.responsive.spacing(12),
                      ),
                      cacheExtent: 300,
                      itemCount: messages.length,
                      itemBuilder: (context, i) {
                        final msg = messages[i];
                        final isMe = user != null && msg.senderUid == user.uid;
                        return Align(
                          alignment: isMe
                              ? Alignment.centerRight
                              : Alignment.centerLeft,
                          child: Container(
                            margin: const EdgeInsets.only(bottom: 8),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 10,
                            ),
                            decoration: BoxDecoration(
                              color: isMe
                                  ? Theme.of(context).colorScheme.primary
                                  : Theme.of(context).colorScheme.surfaceContainerHighest,
                              borderRadius: BorderRadius.circular(18),
                            ),
                            constraints: BoxConstraints(
                              maxWidth:
                                  MediaQuery.of(context).size.width * 0.75,
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                ChatMessageContent(
                                  msg: msg,
                                  isMe: isMe,
                                  barcodeSnippet: 'Scan di Data Order',
                                  isAudioPlaying: _audioPlaying[msg.id] ?? false,
                                  onToggleAudioPlayback: _toggleAudioPlayback,
                                  onOpenFullScreenImage: (url) =>
                                      _openFullScreenImage(url),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
              // Indikator rekaman audio
              if (_isRecording)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  color: _isRecordingLocked
                      ? (Theme.of(context).brightness == Brightness.dark
                          ? Colors.green.shade900.withValues(alpha: 0.5)
                          : Colors.green.shade50)
                      : (Theme.of(context).brightness == Brightness.dark
                          ? Colors.red.shade900.withValues(alpha: 0.5)
                          : Colors.red.shade50),
                  child: Row(
                    children: [
                      Icon(
                        _isRecordingLocked ? Icons.lock : Icons.mic,
                        color: _isRecordingLocked ? Colors.green : Colors.red,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _isRecordingLocked
                            ? 'Rekam terkunci: ${_recordingDuration}s'
                            : 'Rekam: ${_recordingDuration}s',
                        style: TextStyle(
                          color: _isRecordingLocked ? Colors.green : Colors.red,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const Spacer(),
                      if (_isRecordingLocked)
                        IconButton(
                          onPressed: () => _stopRecording(send: true),
                          icon: const Icon(Icons.send, color: Colors.green),
                          tooltip: 'Kirim pesan suara',
                        ),
                      TextButton(
                        onPressed: _cancelRecording,
                        child: const Text('Batal'),
                      ),
                    ],
                  ),
                ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                color: Theme.of(context).colorScheme.surface,
                child: Row(
                  children: [
                    // Tombol pick media (gambar/video)
                    IconButton(
                      onPressed: _showMediaPicker,
                      icon: const Icon(Icons.attach_file),
                                color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                    Expanded(
                      child: TextField(
                        controller: _textController,
                        focusNode: _focusNode,
                        onChanged: (_) => setState(() {}),
                        decoration: InputDecoration(
                          hintText: 'Ketik pesan...',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(24),
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 10,
                          ),
                        ),
                        textCapitalization: TextCapitalization.sentences,
                        onSubmitted: (_) {
                          if (_textController.text.trim().isNotEmpty) {
                            _sendMessage();
                          }
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    // Keyboard tidak muncul → tombol pesan suara; keyboard muncul → tombol kirim teks
                    _focusNode.hasFocus
                        ? IconButton.filled(
                            onPressed: _textController.text.trim().isEmpty
                                ? null
                                : _sendMessage,
                            icon: const Icon(Icons.send),
                          )
                        : _buildVoiceButton(),
                  ],
                ),
              ),
              if (_orderLoading)
                const Padding(
                  padding: EdgeInsets.all(8),
                  child: SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              // Tombol Kesepakatan tidak ditampilkan lagi karena sudah diganti dengan popup otomatis
            ],
          ),
        ),
      ),
    );
  }
}
