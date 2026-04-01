import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../screens/admin_chat_screen.dart';
import '../services/admin_contact_config_service.dart';
import '../services/app_analytics_service.dart';
import '../widgets/traka_l10n_scope.dart';

/// Widget kontak admin: hanya gambar admin di pojok kanan bawah.
/// Saat diklik, muncul dialog pilihan: Email, WhatsApp, Instagram, Live Chat.
/// Posisi: fixed di bawah, di atas bottom nav "Saya".
/// Nilai email/WA/IG dari Firestore (bisa diubah admin).
/// Memakai stream agar update real-time saat admin mengubah di web.
class AdminContactWidget extends StatefulWidget {
  const AdminContactWidget({super.key});

  @override
  State<AdminContactWidget> createState() => _AdminContactWidgetState();
}

class _AdminContactWidgetState extends State<AdminContactWidget> {
  StreamSubscription<Map<String, String?>>? _streamSub;

  @override
  void initState() {
    super.initState();
    AdminContactConfigService.load(force: true);
    _streamSub = AdminContactConfigService.stream().listen((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _streamSub?.cancel();
    super.dispose();
  }

  Future<void> _launchEmail() async {
    AppAnalyticsService.logAdminContactChannelTap(channel: 'email');
    final email = AdminContactConfigService.adminEmail;
    if (email.isEmpty) {
      _showError('Email admin belum dikonfigurasi');
      return;
    }
    final uri = Uri(scheme: 'mailto', path: email);
    try {
      final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!launched && mounted) {
        _showError('Tidak dapat membuka aplikasi email');
      }
    } catch (_) {
      if (mounted) _showError('Tidak dapat membuka aplikasi email');
    }
  }

  Future<void> _launchWhatsApp() async {
    final wa = AdminContactConfigService.adminWhatsApp;
    if (wa.isEmpty) {
      _showError('WhatsApp admin belum dikonfigurasi');
      return;
    }
    // Format: 628xxxxxxxxxx (tanpa +, tanpa spasi)
    final cleanWa = wa.replaceAll(RegExp(r'\D'), '');
    final uri = Uri.parse('https://wa.me/$cleanWa');
    try {
      final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!launched && mounted) {
        _showError('Tidak dapat membuka WhatsApp');
      }
    } catch (_) {
      if (mounted) _showError('Tidak dapat membuka WhatsApp');
    }
  }

  Future<void> _launchInstagram() async {
    AppAnalyticsService.logAdminContactChannelTap(channel: 'instagram');
    final ig = AdminContactConfigService.adminInstagram;
    if (ig == null || ig.isEmpty) {
      _showError('Instagram belum dikonfigurasi');
      return;
    }
    final username = ig.startsWith('@') ? ig.substring(1) : ig.trim();
    final uri = Uri.parse('https://www.instagram.com/$username');
    try {
      final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!launched && mounted) {
        _showError('Tidak dapat membuka Instagram');
      }
    } catch (_) {
      if (mounted) _showError('Tidak dapat membuka Instagram');
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _openLiveChat() {
    AppAnalyticsService.logAdminContactChannelTap(channel: 'live_chat');
    Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => const AdminChatScreen(),
      ),
    );
  }

  void _showContactDialog() {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text(
          'Hubungi Admin',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.email, color: Theme.of(ctx).colorScheme.primary),
              title: const Text('Email'),
              subtitle: Text(TrakaL10n.of(ctx).contactAdminEmail),
              onTap: () {
                Navigator.pop(ctx);
                _launchEmail();
              },
            ),
            const Divider(),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.chat_bubble_outline, color: Theme.of(ctx).colorScheme.primary),
              title: const Text('WhatsApp'),
              subtitle: Text(TrakaL10n.of(ctx).contactAdminWhatsApp),
              onTap: () {
                Navigator.pop(ctx);
                _launchWhatsApp();
              },
            ),
            const Divider(),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.camera_alt, color: Colors.purple),
              title: const Text('Instagram'),
              subtitle: Text(
                AdminContactConfigService.adminInstagram != null &&
                        AdminContactConfigService.adminInstagram!.isNotEmpty
                    ? TrakaL10n.of(ctx).contactAdminInstagram
                    : TrakaL10n.of(ctx).contactAdminNotConfigured,
              ),
              onTap: AdminContactConfigService.adminInstagram != null &&
                      AdminContactConfigService.adminInstagram!.isNotEmpty
                  ? () {
                      Navigator.pop(ctx);
                      _launchInstagram();
                    }
                  : null,
            ),
            const Divider(),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                Icons.support_agent_rounded,
                color: Theme.of(ctx).colorScheme.primary,
              ),
              title: const Text('Live Chat'),
              subtitle: const Text('Chat langsung dengan admin (dalam aplikasi)'),
              onTap: () {
                Navigator.pop(ctx);
                _openLiveChat();
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Tutup'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _showContactDialog,
      child: Image.asset(
        'assets/images/admin.png',
        width: 58,
        height: 58,
        fit: BoxFit.contain,
        filterQuality: FilterQuality.high,
      ),
    );
  }
}
