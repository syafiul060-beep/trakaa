import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../services/verification_service.dart';
import '../theme/app_theme.dart';
import '../theme/app_interaction_styles.dart';

/// Banner saat admin meminta data verifikasi tambahan + pembatasan fitur.
class AdminVerificationBanner extends StatefulWidget {
  const AdminVerificationBanner({
    super.key,
    required this.userData,
    this.onSubmitted,
  });

  final Map<String, dynamic> userData;
  final VoidCallback? onSubmitted;

  @override
  State<AdminVerificationBanner> createState() =>
      _AdminVerificationBannerState();
}

class _AdminVerificationBannerState extends State<AdminVerificationBanner> {
  bool _loading = false;

  Future<void> _markSubmitted() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    setState(() => _loading = true);
    try {
      await FirebaseFirestore.instance.collection('users').doc(uid).update({
        'adminVerificationUserSubmittedAt': FieldValue.serverTimestamp(),
      });
      widget.onSubmitted?.call();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Terima kasih. Tim akan meninjau data Anda.',
            ),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Gagal memperbarui: $e'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final pending = widget.userData['adminVerificationPendingAt'];
    if (pending == null) return const SizedBox.shrink();

    final restrict =
        widget.userData['adminVerificationRestrictFeatures'] == true;
    final submitted = widget.userData['adminVerificationUserSubmittedAt'];
    final msg = (widget.userData['adminVerificationMessage'] as String?)
            ?.trim() ??
        '';
    final deadline = widget.userData['adminVerificationDeadlineAt'];
    DateTime? deadlineDt;
    if (deadline is Timestamp) deadlineDt = deadline.toDate();

    if (!restrict) {
      return const SizedBox.shrink();
    }

    if (submitted != null) {
      return Container(
        padding: const EdgeInsets.all(14),
        margin: const EdgeInsets.only(bottom: 20),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.secondaryContainer.withValues(
                alpha: 0.65,
              ),
          borderRadius: BorderRadius.circular(AppTheme.radiusSm),
          border: Border.all(
            color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.35),
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Icons.hourglass_top_outlined,
              size: 22,
              color: Theme.of(context).colorScheme.secondary,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Data Anda sudah dikirim. Menunggu konfirmasi admin.',
                style: TextStyle(
                  fontSize: 13,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(14),
      margin: const EdgeInsets.only(bottom: 20),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.errorContainer.withValues(
              alpha: 0.45,
            ),
        borderRadius: BorderRadius.circular(AppTheme.radiusSm),
        border: Border.all(
          color: Theme.of(context).colorScheme.error.withValues(alpha: 0.35),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.warning_amber_rounded,
                size: 22,
                color: Theme.of(context).colorScheme.error,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Admin meminta dokumen verifikasi',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                    if (msg.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        msg,
                        style: TextStyle(
                          fontSize: 13,
                          height: 1.35,
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                      ),
                    ],
                    if (deadlineDt != null) ...[
                      const SizedBox(height: 6),
                      Text(
                        'Batas waktu: ${deadlineDt.toLocal()}',
                        style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                    const SizedBox(height: 6),
                    Text(
                      VerificationService.adminVerificationBlockingHintId,
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: _loading ? null : _markSubmitted,
            style: AppInteractionStyles.destructive(
              Theme.of(context).colorScheme,
            ),
            child: _loading
                ? SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Theme.of(context).colorScheme.onError,
                    ),
                  )
                : const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.send_outlined, size: 18),
                      SizedBox(width: 8),
                      Text('Sudah kirim data'),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}
