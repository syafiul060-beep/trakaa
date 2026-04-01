import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../services/app_analytics_service.dart';
import '../widgets/traka_l10n_scope.dart';
import '../services/chat_filter_service.dart';
import '../services/feedback_service.dart';
import '../theme/app_interaction_styles.dart';
import '../theme/traka_snackbar.dart';

/// Form saran/masukan ke admin. Data disimpan di Firestore app_feedback.
class SaranKeAdminScreen extends StatefulWidget {
  const SaranKeAdminScreen({super.key});

  @override
  State<SaranKeAdminScreen> createState() => _SaranKeAdminScreenState();
}

class _SaranKeAdminScreenState extends State<SaranKeAdminScreen> {
  final _controller = TextEditingController();
  String _type = 'saran';
  bool _sending = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (FirebaseAuth.instance.currentUser == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        TrakaSnackBar.error(context, Text('Sesi tidak valid. Silakan login kembali.'), behavior: SnackBarBehavior.floating),
      );
      return;
    }
    final text = _controller.text.trim();
    if (text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Isi saran atau masukan terlebih dahulu'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    if (text.length > FeedbackService.maxTextLength) {
      ScaffoldMessenger.of(context).showSnackBar(
        TrakaSnackBar.error(context, Text('Maksimal ${FeedbackService.maxTextLength} karakter.'), behavior: SnackBarBehavior.floating),
      );
      return;
    }
    if (ChatFilterService.containsBlockedContent(text)) {
      ScaffoldMessenger.of(context).showSnackBar(
        TrakaSnackBar.error(context, Text('Saran tidak boleh berisi kontak atau nomor untuk transaksi di luar aplikasi.'), behavior: SnackBarBehavior.floating),
      );
      return;
    }

    setState(() => _sending = true);
    try {
      final (ok, errMsg) = await FeedbackService.submit(text: text, type: _type);
      if (!mounted) return;
      if (ok) {
        _controller.clear();
        AppAnalyticsService.logFeedbackSubmit(type: _type);
        ScaffoldMessenger.of(context).showSnackBar(
          TrakaSnackBar.success(context, Text('Terima kasih! Saran Anda telah dikirim ke admin.'), behavior: SnackBarBehavior.floating),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          TrakaSnackBar.error(context, Text(errMsg ?? 'Gagal mengirim. Coba lagi.'), behavior: SnackBarBehavior.floating),
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(TrakaL10n.of(context).suggestionToAdminTitle),
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
              Row(
                children: [
                  Icon(Icons.feedback_outlined, size: 32, color: Theme.of(context).colorScheme.primary),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Berikan saran atau masukan untuk pengembangan aplikasi Traka. Admin akan menerima dan menindaklanjuti.',
                      style: TextStyle(
                        fontSize: 14,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              DropdownButtonFormField<String>(
                initialValue: _type,
                decoration: InputDecoration(
                  labelText: 'Jenis',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  prefixIcon: const Icon(Icons.category_outlined),
                ),
                items: const [
                  DropdownMenuItem(value: 'saran', child: Text('Saran')),
                  DropdownMenuItem(value: 'masukan', child: Text('Masukan')),
                  DropdownMenuItem(value: 'keluhan', child: Text('Keluhan')),
                ],
                onChanged: _sending ? null : (v) => setState(() => _type = v ?? 'saran'),
              ),
              const SizedBox(height: 20),
              TextFormField(
                controller: _controller,
                maxLines: 5,
                maxLength: FeedbackService.maxTextLength,
                enabled: !_sending,
                decoration: InputDecoration(
                  labelText: 'Saran / Masukan',
                  hintText: 'Tulis saran atau masukan Anda di sini...',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  alignLabelWithHint: true,
                ),
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: _sending ? null : _submit,
                icon: _sending
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.send),
                label: Text(_sending ? 'Mengirim...' : 'Kirim ke Admin'),
                style: AppInteractionStyles.filledFromTheme(
                  context,
                  padding:
                      const EdgeInsets.symmetric(vertical: 16),
                ),
              ),
            ],
          ),
        ),
    );
  }
}
