import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../models/order_model.dart';
import '../services/app_config_service.dart';
import '../services/chat_service.dart';
import '../services/driver_schedule_service.dart';
import '../services/order_service.dart';
import '../theme/app_theme.dart';
import 'traka_bottom_sheet.dart';
import 'traka_empty_state.dart';
import '../theme/traka_snackbar.dart';

/// Sheet pilih jadwal target untuk pindah pesanan terjadwal.
void showPindahJadwalSheet(
  BuildContext context, {
  required OrderModel order,
  required String currentScheduleId,
  required String driverUid,
}) {
  showTrakaModalBottomSheet<void>(
    context: context,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(AppTheme.radiusMd)),
    ),
    builder: (ctx) => _PindahJadwalSheet(
      order: order,
      currentScheduleId: currentScheduleId,
      driverUid: driverUid,
    ),
  );
}

class _PindahJadwalSheet extends StatefulWidget {
  final OrderModel order;
  final String currentScheduleId;
  final String driverUid;

  const _PindahJadwalSheet({
    required this.order,
    required this.currentScheduleId,
    required this.driverUid,
  });

  @override
  State<_PindahJadwalSheet> createState() => _PindahJadwalSheetState();
}

class _PindahJadwalSheetState extends State<_PindahJadwalSheet> {
  List<Map<String, dynamic>> _otherSchedules = [];
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final list = await DriverScheduleService.getOtherSchedulesForPindah(
      widget.driverUid,
      excludeScheduleId: widget.currentScheduleId,
    );
    if (mounted) {
      setState(() {
        _otherSchedules = list;
        _loading = false;
      });
    }
  }

  Future<void> _pindahTo(Map<String, dynamic> target) async {
    final scheduleId = target['scheduleId'] as String?;
    final scheduledDate = target['scheduledDate'] as String?;
    if (scheduleId == null || scheduledDate == null) return;

    final orderType = widget.order.orderType;
    final totalPenumpang = widget.order.totalPenumpang;

    if (orderType == OrderModel.typeTravel) {
      final counts =
          await OrderService.getScheduledBookingCounts(scheduleId);
      final kargoSlot = await AppConfigService.getKargoSlotPerOrder();
      final usedSlots = counts.totalPenumpang +
          ((counts.kargoCount * kargoSlot).ceil()).clamp(0, 100);
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(widget.driverUid)
          .get();
      final maxPassengers =
          (userDoc.data()?['vehicleJumlahPenumpang'] as num?)?.toInt() ?? 0;
      if (maxPassengers > 0 && usedSlots + totalPenumpang > maxPassengers) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            TrakaSnackBar.error(context, Text(
                'Kapasitas jadwal target tidak cukup (sudah $usedSlots slot terpakai, max $maxPassengers).',
              )),
          );
        }
        return;
      }
    }

    setState(() => _saving = true);
    final (ok, err) = await OrderService.updateOrderSchedule(
      widget.order.id,
      scheduleId,
      scheduledDate,
    );
    if (!mounted) return;
    setState(() => _saving = false);
    if (ok) {
      final dep = target['departureTime'] as DateTime?;
      final dateStr = dep != null
          ? '${dep.day.toString().padLeft(2, '0')}/${dep.month.toString().padLeft(2, '0')}/${dep.year} ${dep.hour.toString().padLeft(2, '0')}:${dep.minute.toString().padLeft(2, '0')}'
          : scheduledDate;
      await ChatService.sendMessage(
        widget.order.id,
        'Driver memindah jadwal Anda ke $dateStr. Silakan cek detail di Data Order.',
      );
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        TrakaSnackBar.success(context, Text('Pesanan berhasil dipindah. Penumpang akan dapat notifikasi.')),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        TrakaSnackBar.error(context, Text(err ?? 'Gagal')),
      );
    }
  }

  static String _formatSchedule(Map<String, dynamic> m) {
    final dep = m['departureTime'] as DateTime?;
    final origin = (m['origin'] as String?) ?? '';
    final dest = (m['destination'] as String?) ?? '';
    final dateStr = dep != null
        ? '${dep.day}/${dep.month}/${dep.year} ${dep.hour.toString().padLeft(2, '0')}:${dep.minute.toString().padLeft(2, '0')}'
        : '';
    if (origin.isNotEmpty && dest.isNotEmpty) {
      return '$origin → $dest\n$dateStr';
    }
    return dateStr;
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Pindah ke jadwal lain',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '${widget.order.passengerName} - ${widget.order.destText}',
              style: TextStyle(
                fontSize: 13,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 16),
            if (_loading)
              const Center(child: CircularProgressIndicator())
            else if (_otherSchedules.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: TrakaEmptyState(
                  icon: Icons.event_busy,
                  title: 'Tidak ada jadwal lain',
                  subtitle: 'Buat jadwal baru di kalender.',
                ),
              )
            else
              ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _otherSchedules.length,
                separatorBuilder: (_, _) => const SizedBox(height: 8),
                itemBuilder: (context, i) {
                  final m = _otherSchedules[i];
                  return ListTile(
                    leading: Icon(
                      Icons.schedule,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    title: Text(
                      _formatSchedule(m).split('\n').first,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(
                      _formatSchedule(m).split('\n').length > 1
                          ? _formatSchedule(m).split('\n').last
                          : '',
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    onTap: _saving ? null : () => _pindahTo(m),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }
}
