import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app_navigator.dart';
import '../models/order_model.dart';
import '../screens/admin_chat_screen.dart';
import 'admin_contact_config_service.dart';
import 'location_service.dart';

/// Service untuk fitur SOS / Darurat.
/// Menyimpan event ke Firestore; WhatsApp ke admin jika dikonfigurasi, selain itu buka Live Chat dengan pesan awal.
class SosService {
  static const String _collectionSosEvents = 'sos_events';

  static String _buildSosMessage({
    required OrderModel order,
    required bool isDriver,
    required double lat,
    required double lng,
  }) {
    final mapsUrl = 'https://www.google.com/maps?q=$lat,$lng';
    final now = DateTime.now();
    final timeStr = '${now.day.toString().padLeft(2, '0')}/${now.month.toString().padLeft(2, '0')}/${now.year} ${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
    return '''🚨 SOS - Traka

Lokasi: $mapsUrl
Pesanan: ${order.orderNumber ?? order.id}
Asal: ${order.originText}
Tujuan: ${order.destText}
Status: ${order.status}
Waktu: $timeStr
${isDriver ? 'Trigger: Driver' : 'Trigger: Penumpang'}''';
  }

  static void _openAdminChatWithSosMessage(String message) {
    final nav = appNavigatorKey.currentState;
    if (nav == null) return;
    void push() {
      nav.push(
        MaterialPageRoute<void>(
          builder: (_) => AdminChatScreen(initialMessage: message),
        ),
      );
    }

    final phase = SchedulerBinding.instance.schedulerPhase;
    if (phase == SchedulerPhase.idle) {
      push();
    } else {
      SchedulerBinding.instance.addPostFrameCallback((_) => push());
    }
  }

  /// Trigger SOS: simpan ke Firestore; WhatsApp atau Live Chat sesuai konfigurasi admin.
  /// [order] pesanan aktif. [isDriver] true jika yang trigger adalah driver.
  static Future<void> triggerSOS({
    required OrderModel order,
    required bool isDriver,
    required double lat,
    required double lng,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final message = _buildSosMessage(
      order: order,
      isDriver: isDriver,
      lat: lat,
      lng: lng,
    );

    await FirebaseFirestore.instance.collection(_collectionSosEvents).add({
      'uid': user.uid,
      'orderId': order.id,
      'orderNumber': order.orderNumber,
      'isDriver': isDriver,
      'lat': lat,
      'lng': lng,
      'originText': order.originText,
      'destText': order.destText,
      'status': order.status,
      'triggeredAt': FieldValue.serverTimestamp(),
    });

    await AdminContactConfigService.load(force: true);
    final wa = AdminContactConfigService.adminWhatsApp;
    final cleanWa = wa.replaceAll(RegExp(r'\D'), '');
    if (cleanWa.isEmpty) {
      _openAdminChatWithSosMessage(message);
      return;
    }
    final uri = Uri.parse(
      'https://wa.me/$cleanWa?text=${Uri.encodeComponent(message)}',
    );
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {}
  }

  /// Ambil lokasi saat ini dan trigger SOS.
  static Future<void> triggerSOSWithLocation({
    required OrderModel order,
    required bool isDriver,
  }) async {
    try {
      final result = await LocationService.getCurrentPositionWithMockCheck();
      if (result.isFakeGpsDetected || result.position == null) {
        await triggerSOS(order: order, isDriver: isDriver, lat: 0, lng: 0);
        return;
      }
      final pos = result.position!;
      await triggerSOS(
        order: order,
        isDriver: isDriver,
        lat: pos.latitude,
        lng: pos.longitude,
      );
    } catch (_) {
      await triggerSOS(
        order: order,
        isDriver: isDriver,
        lat: 0,
        lng: 0,
      );
    }
  }
}
