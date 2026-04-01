import 'dart:io';

import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart' as ph;

import '../services/app_analytics_service.dart';
import '../widgets/traka_l10n_scope.dart';
import 'privacy_screen.dart';
import 'terms_screen.dart';

/// Halaman panduan aplikasi: fungsi, fitur, peraturan, kontribusi, pelanggaran.
class PanduanAplikasiScreen extends StatefulWidget {
  const PanduanAplikasiScreen({super.key});

  @override
  State<PanduanAplikasiScreen> createState() => _PanduanAplikasiScreenState();
}

class _PanduanAplikasiScreenState extends State<PanduanAplikasiScreen> {
  @override
  void initState() {
    super.initState();
    AppAnalyticsService.logPanduanOpen();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bodyStyle = TextStyle(
      fontSize: 14,
      color: theme.colorScheme.onSurface,
      height: 1.6,
    );
    return Scaffold(
      appBar: AppBar(
        title: Text(TrakaL10n.of(context).appGuide),
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildSection(
            context,
            sectionName: 'spesifikasi',
            icon: Icons.phone_android,
            iconColor: theme.colorScheme.primary,
            title: TrakaL10n.of(context).panduanSpesifikasiTitle,
            content: TrakaL10n.of(context).panduanSpesifikasiContent,
            bodyStyle: bodyStyle,
          ),
          _buildSection(
            context,
            sectionName: 'fungsi',
            icon: Icons.info_outline,
            iconColor: theme.colorScheme.primary,
            title: TrakaL10n.of(context).panduanFungsiTitle,
            content: TrakaL10n.of(context).panduanFungsiContent,
            bodyStyle: bodyStyle,
          ),
          _buildSection(
            context,
            sectionName: 'fitur',
            icon: Icons.star_outline,
            iconColor: theme.colorScheme.secondary,
            title: TrakaL10n.of(context).panduanFiturTitle,
            content: TrakaL10n.of(context).panduanFiturContent,
            bodyStyle: bodyStyle,
          ),
          _buildSection(
            context,
            sectionName: 'peraturan',
            icon: Icons.gavel,
            iconColor: theme.colorScheme.tertiary,
            title: TrakaL10n.of(context).panduanPeraturanTitle,
            content: TrakaL10n.of(context).panduanPeraturanContent,
            bodyStyle: bodyStyle,
          ),
          _buildSection(
            context,
            sectionName: 'kontribusi_pembayaran',
            icon: Icons.account_balance_wallet_outlined,
            iconColor: theme.colorScheme.primaryContainer,
            title: TrakaL10n.of(context).panduanKontribusiTitle,
            content: TrakaL10n.of(context).panduanKontribusiContent,
            bodyStyle: bodyStyle,
          ),
          _buildSection(
            context,
            sectionName: 'kenapa_ada_biaya',
            icon: Icons.visibility_outlined,
            iconColor: theme.colorScheme.primaryContainer,
            title: TrakaL10n.of(context).panduanKenapaBiayaTitle,
            content: TrakaL10n.of(context).panduanKenapaBiayaContent,
            bodyStyle: bodyStyle,
          ),
          _buildSection(
            context,
            sectionName: 'pelanggaran',
            icon: Icons.warning_amber_rounded,
            iconColor: theme.colorScheme.error,
            title: TrakaL10n.of(context).panduanPelanggaranTitle,
            content: TrakaL10n.of(context).panduanPelanggaranContent,
            bodyStyle: bodyStyle,
          ),
          const SizedBox(height: 8),
          if (Platform.isAndroid)
            Card(
              margin: const EdgeInsets.only(bottom: 12),
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor:
                      theme.colorScheme.primary.withValues(alpha: 0.2),
                  child: Icon(
                    Icons.notifications_off_outlined,
                    color: theme.colorScheme.primary,
                  ),
                ),
                title: Text(
                  TrakaL10n.of(context).panduanNotifikasiTitle,
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
                subtitle: Text(
                  TrakaL10n.of(context).panduanNotifikasiContent,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 13, color: theme.colorScheme.onSurfaceVariant),
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _showNotifikasiHelpDialog(context),
              ),
            ),
          Card(
            margin: const EdgeInsets.only(bottom: 12),
            child: Column(
              children: [
                ListTile(
                  leading: CircleAvatar(
                    backgroundColor: theme.colorScheme.primaryContainer.withValues(alpha: 0.5),
                    child: Icon(Icons.description_outlined, color: theme.colorScheme.primary),
                  ),
                  title: Text(TrakaL10n.of(context).termsOfService),
                  subtitle: Text(TrakaL10n.of(context).termsSubtitle),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute<void>(
                        builder: (_) => const TermsScreen(),
                      ),
                    );
                  },
                ),
                const Divider(height: 1),
                ListTile(
                  leading: CircleAvatar(
                    backgroundColor: theme.colorScheme.primaryContainer.withValues(alpha: 0.5),
                    child: Icon(Icons.privacy_tip_outlined, color: theme.colorScheme.primary),
                  ),
                  title: Text(TrakaL10n.of(context).privacyPolicy),
                  subtitle: Text(TrakaL10n.of(context).privacySubtitle),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute<void>(
                        builder: (_) => const PrivacyScreen(),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showNotifikasiHelpDialog(BuildContext context) {
    AppAnalyticsService.logPanduanSectionView('notifikasi_layar_mati');
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.notifications_active, color: Theme.of(ctx).colorScheme.primary),
            const SizedBox(width: 8),
            Expanded(child: Text(TrakaL10n.of(ctx).panduanNotifikasiTitle)),
          ],
        ),
        content: SingleChildScrollView(
          child: SelectableText(
            TrakaL10n.of(ctx).panduanNotifikasiContent,
            style: TextStyle(fontSize: 14, height: 1.5, color: Theme.of(ctx).colorScheme.onSurface),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(TrakaL10n.of(ctx).cancel),
          ),
          FilledButton.icon(
            onPressed: () async {
              Navigator.pop(ctx);
              await ph.openAppSettings();
            },
            icon: const Icon(Icons.settings, size: 20),
            label: Text(TrakaL10n.of(ctx).panduanNotifikasiBukaPengaturan),
          ),
        ],
      ),
    );
  }

  Widget _buildSection(
    BuildContext context, {
    required String sectionName,
    required IconData icon,
    required Color iconColor,
    required String title,
    required String content,
    required TextStyle bodyStyle,
  }) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ExpansionTile(
        onExpansionChanged: (expanded) {
          if (expanded) AppAnalyticsService.logPanduanSectionView(sectionName);
        },
        leading: CircleAvatar(
          backgroundColor: iconColor.withValues(alpha: 0.2),
          child: Icon(icon, color: iconColor, size: 24),
        ),
        title: Text(
          title,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: SelectableText(content, style: bodyStyle),
          ),
        ],
      ),
    );
  }
}
