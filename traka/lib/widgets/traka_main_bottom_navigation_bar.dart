import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n/app_localizations.dart';
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

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = TrakaL10n.of(context);
    final selected = _selectedHint(l10n);

    Widget homeIcon() {
      final on = currentIndex == 0;
      return Semantics(
        label: '${l10n.navHome}${on ? ', $selected' : ''}',
        button: true,
        child: Icon(
          on ? Icons.home : Icons.home_outlined,
          color: on ? cs.primary : cs.onSurfaceVariant,
        ),
      );
    }

    Widget scheduleIcon() {
      final on = currentIndex == 1;
      final icon = scheduleTabIcon == TrakaScheduleTabIcon.calendar
          ? (on ? Icons.calendar_month : Icons.calendar_month_outlined)
          : (on ? Icons.schedule : Icons.schedule_outlined);
      return Semantics(
        label: '${l10n.navSchedule}${on ? ', $selected' : ''}',
        button: true,
        child: Icon(
          icon,
          color: on ? cs.primary : cs.onSurfaceVariant,
        ),
      );
    }

    Widget chatIcon() {
      final on = currentIndex == 2;
      final base = Icon(
        on ? Icons.chat_bubble : Icons.chat_bubble_outline,
        color: on ? cs.primary : cs.onSurfaceVariant,
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
      final base = Icon(
        on ? Icons.receipt_long : Icons.receipt_long_outlined,
        color: on ? cs.primary : cs.onSurfaceVariant,
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
        child: Icon(
          on ? Icons.person : Icons.person_outline,
          color: on ? cs.primary : cs.onSurfaceVariant,
        ),
      );
    }

    return Semantics(
      container: true,
      label: l10n.locale == AppLocale.id
          ? 'Navigasi utama lima tab'
          : 'Main navigation, five tabs',
      child: BottomNavigationBar(
        currentIndex: currentIndex,
        onTap: (i) {
          HapticFeedback.selectionClick();
          onTap(i);
        },
        type: BottomNavigationBarType.fixed,
        selectedItemColor: cs.primary,
        unselectedItemColor: cs.onSurfaceVariant,
        backgroundColor: cs.surface,
        selectedLabelStyle: const TextStyle(
          fontWeight: FontWeight.w600,
          fontSize: 10,
        ),
        unselectedLabelStyle: TextStyle(
          fontWeight: FontWeight.w600,
          fontSize: 10,
          color: cs.onSurfaceVariant,
        ),
        items: [
          BottomNavigationBarItem(icon: homeIcon(), label: l10n.navHome),
          BottomNavigationBarItem(
            icon: scheduleIcon(),
            label: l10n.navSchedule,
          ),
          BottomNavigationBarItem(icon: chatIcon(), label: l10n.navChat),
          BottomNavigationBarItem(icon: ordersIcon(), label: l10n.navOrders),
          BottomNavigationBarItem(icon: profileIcon(), label: l10n.navProfile),
        ],
      ),
    );
  }
}
