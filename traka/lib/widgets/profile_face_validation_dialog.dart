import 'package:flutter/material.dart';

import 'traka_l10n_scope.dart';
import '../services/face_validation_service.dart';

/// Dialog error validasi foto wajah.
/// Dipakai oleh ProfilePenumpangScreen dan ProfileDriverScreen.
class ProfileFaceValidationDialog {
  ProfileFaceValidationDialog._();

  /// Tampilkan dialog. Return action yang dipilih user.
  static Future<FaceValidationDialogAction?> show(
    BuildContext context, {
    required String message,
    bool isBlurError = false,
  }) {
    return showDialog<FaceValidationDialogAction>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(TrakaL10n.of(context).photoDoesNotMeetRequirements),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(message),
            if (isBlurError) ...[
              const SizedBox(height: 12),
              Text(
                'Foto kurang jelas. Anda bisa pakai foto ini jika wajah terdeteksi, atau ambil ulang untuk hasil lebih baik.',
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ],
        ),
        actions: [
          SizedBox(
            width: double.infinity,
            child: Wrap(
              alignment: WrapAlignment.end,
              spacing: 8,
              runSpacing: 8,
              children: [
                TextButton(
                  onPressed: () =>
                      Navigator.pop(ctx, FaceValidationDialogAction.cancel),
                  child: const Text('Batal'),
                ),
                if (isBlurError)
                  TextButton(
                    onPressed: () =>
                        Navigator.pop(ctx, FaceValidationDialogAction.useAnyway),
                    child: Text(TrakaL10n.of(context).useThisPhoto),
                  ),
                FilledButton(
                  onPressed: () =>
                      Navigator.pop(ctx, FaceValidationDialogAction.retry),
                  child: const Text('Coba lagi'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
