import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../services/biometric_login_service.dart';
import 'traka_l10n_scope.dart';

/// Tile untuk hapus kredensial login sidik jari (jika tersimpan).
class BiometricLoginCredentialTile extends StatefulWidget {
  const BiometricLoginCredentialTile({super.key});

  @override
  State<BiometricLoginCredentialTile> createState() =>
      _BiometricLoginCredentialTileState();
}

class _BiometricLoginCredentialTileState extends State<BiometricLoginCredentialTile> {
  bool _hasCred = false;

  @override
  void initState() {
    super.initState();
    BiometricLoginService.hasStoredCredentials().then((v) {
      if (mounted) setState(() => _hasCred = v);
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_hasCred) return const SizedBox.shrink();
    final isId = TrakaL10n.of(context).locale == AppLocale.id;
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () async {
            await BiometricLoginService.clearCredentials();
            if (context.mounted) {
              setState(() => _hasCred = false);
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(isId ? 'Login sidik jari dihapus' : 'Fingerprint login removed')),
              );
            }
          },
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: colorScheme.error.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.delete_outline_rounded, color: colorScheme.error, size: 22),
                ),
                const SizedBox(width: 14),
                Text(
                  isId ? 'Hapus login sidik jari' : 'Remove fingerprint login',
                  style: TextStyle(
                    color: colorScheme.error,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
