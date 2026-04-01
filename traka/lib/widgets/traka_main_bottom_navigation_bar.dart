import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n/app_localizations.dart';
import '../widgets/traka_bottom_nav_glyph.dart';
import '../widgets/traka_l10n_scope.dart';

/// Ikon tab Jadwal: penumpang pakai kalender, driver pakai jam/jadwal.
enum TrakaScheduleTabIcon { calendar, schedule }

/// Bottom navigation utama penumpang & driver — satu pola visual + semantics.
class TrakaMainBottomNavigationBar extends StatelessWidget {
  const TrakaMainBottomNavigationBar({
    super.key,
    required this.currentIndex,
    required this.onTap,
    required this.chatUnreadCount,
    this.ordersAttentionCount = 0,
    this.scheduleTabIcon = TrakaScheduleTabIcon.calendar,
  });

  final int currentIndex;
  final ValueChanged<int> onTap;
  final int chatUnreadCount;
  /// Driver: jumlah order menunggu tindakan (pending agreement / pending receiver).
  final int ordersAttentionCount;
  final TrakaScheduleTabIcon scheduleTabIcon;

  String _selectedHint(AppLocalizations l10n) =>
      l10n.locale == AppLocale.id ? 'dipilih' : 'selected';

  /// Ikon sedikit lebih besar — lebih dekat tampilan bottom bar klasik (pra-M3).
  static const double _iconSize = 28;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final bnb = theme.bottomNavigationBarTheme;
    final l10n = TrakaL10n.of(context);
    final selected = _selectedHint(l10n);
    final selectedColor = bnb.selectedItemColor ?? cs.primary;
    final unselectedColor = bnb.unselectedItemColor ?? cs.onSurfaceVariant;
    final barBg = bnb.backgroundColor ?? cs.surface;

    Widget homeIcon() {
      final on = currentIndex == 0;
      return Semantics(
        label: l10n.locale == AppLocale.id
            ? '${l10n.navTrakaTab}, ${l10n.navHome.toLowerCase()}${on ? ', $selected' : ''}'
            : '${l10n.navTrakaTab}, ${l10n.navHome}${on ? ', $selected' : ''}',
        button: true,
        child: TrakaBottomNavGlyph(
          icon: Icons.directions_car_rounded,
          outlinedIcon: Icons.directions_car_outlined,
          selected: on,
          selectedColor: selectedColor,
          unselectedColor: unselectedColor,
          size: _iconSize,
        ),
      );
    }

    Widget scheduleIcon() {
      final on = currentIndex == 1;
      final filled = scheduleTabIcon == TrakaScheduleTabIcon.calendar
          ? Icons.calendar_month_rounded
          : Icons.schedule_rounded;
      final outline = scheduleTabIcon == TrakaScheduleTabIcon.calendar
          ? Icons.calendar_month_outlined
          : Icons.schedule_outlined;
      return Semantics(
        label: '${l10n.navSchedule}${on ? ', $selected' : ''}',
        button: true,
        child: TrakaBottomNavGlyph(
          icon: filled,
          outlinedIcon: outline,
          selected: on,
          selectedColor: selectedColor,
          unselectedColor: unselectedColor,
          size: _iconSize,
        ),
      );
    }

    Widget chatIcon() {
      final on = currentIndex == 2;
      final base = TrakaBottomNavGlyph(
        icon: Icons.chat_bubble_rounded,
        outlinedIcon: Icons.chat_bubble_outline_rounded,
        selected: on,
        selectedColor: selectedColor,
        unselectedColor: unselectedColor,
        size: _iconSize,
      );
      final label = chatUnreadCount > 0
          ? (l10n.locale == AppLocale.id
              ? '${l10n.navChat}, $chatUnreadCount pesan belum dibaca${on ? ', $selected' : ''}'
              : '${l10n.navChat}, $chatUnreadCount unread${on ? ', $selected' : ''}')
          : '${l10n.navChat}${on ? ', $selected' : ''}';
      return Semantics(
        label: label,
        button: true,
        child: chatUnreadCount > 0
            ? Badge(
                label: Text('$chatUnreadCount'),
                child: base,
              )
            : base,
      );
    }

    Widget ordersIcon() {
      final on = currentIndex == 3;
      final base = TrakaBottomNavGlyph(
        icon: Icons.receipt_long_rounded,
        outlinedIcon: Icons.receipt_long_outlined,
        selected: on,
        selectedColor: selectedColor,
        unselectedColor: unselectedColor,
        size: _iconSize,
      );
      final label = ordersAttentionCount > 0
          ? (l10n.locale == AppLocale.id
              ? '${l10n.navOrders}, $ordersAttentionCount perlu ditinjau${on ? ', $selected' : ''}'
              : '${l10n.navOrders}, $ordersAttentionCount need review${on ? ', $selected' : ''}')
          : '${l10n.navOrders}${on ? ', $selected' : ''}';
      return Semantics(
        label: label,
        button: true,
        child: ordersAttentionCount > 0
            ? Badge(
                label: Text('$ordersAttentionCount'),
                child: base,
              )
            : base,
      );
    }

    Widget profileIcon() {
      final on = currentIndex == 4;
      return Semantics(
        label: '${l10n.navProfile}${on ? ', $selected' : ''}',
        button: true,
        child: TrakaBottomNavGlyph(
          icon: Icons.person_rounded,
          outlinedIcon: Icons.person_outline_rounded,
          selected: on,
          selectedColor: selectedColor,
          unselectedColor: unselectedColor,
          size: _iconSize,
        ),
      );
    }

    return Semantics(
      container: true,
      label: l10n.locale == AppLocale.id
          ? 'Navigasi utama lima tab'
          : 'Main navigation, five tabs',
      child: Material(
        elevation: bnb.elevation ?? 8,
        shadowColor: Colors.black.withValues(alpha: 0.12),
        surfaceTintColor: Colors.transparent,
        color: barBg,
        child: BottomNavigationBar(
          currentIndex: currentIndex,
          onTap: (i) {
            HapticFeedback.selectionClick();
            onTap(i);
          },
          type: BottomNavigationBarType.fixed,
          selectedItemColor: selectedColor,
          unselectedItemColor: unselectedColor,
          backgroundColor: Colors.transparent,
          elevation: 0,
          showSelectedLabels: true,
          showUnselectedLabels: true,
          selectedFontSize: 11,
          unselectedFontSize: 11,
          selectedLabelStyle: bnb.selectedLabelStyle ??
              const TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 11,
                height: 1.15,
              ),
          unselectedLabelStyle: bnb.unselectedLabelStyle ??
              TextStyle(
                fontWeight: FontWeight.w500,
                fontSize: 11,
                height: 1.15,
                color: unselectedColor,
              ),
          items: [
            BottomNavigationBarItem(
              icon: homeIcon(),
              label: l10n.navTrakaTab,
            ),
            BottomNavigationBarItem(
              icon: scheduleIcon(),
              label: l10n.navSchedule,
            ),
            BottomNavigationBarItem(icon: chatIcon(), label: l10n.navChat),
            BottomNavigationBarItem(icon: ordersIcon(), label: l10n.navOrders),
            BottomNavigationBarItem(
              icon: profileIcon(),
              label: l10n.navProfile,
            ),
          ],
        ),
      ),
    );
  }
}
