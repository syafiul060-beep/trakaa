import 'package:flutter/material.dart';

import '../services/directions_service.dart';

/// Format instruksi navigasi ke bahasa Indonesia.
class InstructionFormatter {
  InstructionFormatter._();

  /// Icon belok sesuai instruksi (kiri/kanan/lurus/tujuan).
  static IconData getIconForStep(RouteStep step) {
    final lower = step.instruction.toLowerCase();
    if (lower.contains('turn right') || lower.contains('belok kanan')) {
      return Icons.turn_right;
    }
    if (lower.contains('turn left') || lower.contains('belok kiri')) {
      return Icons.turn_left;
    }
    if (lower.contains('turn around') || lower.contains('putar balik')) {
      return Icons.u_turn_right;
    }
    if (lower.contains('keep left') || lower.contains('tetap kiri')) {
      return Icons.turn_slight_left;
    }
    if (lower.contains('keep right') || lower.contains('tetap kanan')) {
      return Icons.turn_slight_right;
    }
    if (lower.contains('destination') || lower.contains('tujuan')) {
      return Icons.flag;
    }
    return Icons.straighten; // lurus / continue
  }

  /// Format instruksi: "500 m lalu belok kanan" atau "Ambil lurus sejauh 1 km"
  static String formatStep(RouteStep step) {
    final dist = step.distanceText;
    final instr = _translateInstruction(step.instruction);
    if (dist.isEmpty || dist == '-') return instr;
    if (instr == 'lurus' || instr == 'Lanjutkan') {
      return 'Ambil lurus sejauh $dist';
    }
    return '$dist lalu $instr';
  }

  /// Terjemahkan instruksi umum dari API ke Indonesia.
  static String _translateInstruction(String raw) {
    final lower = raw.toLowerCase();
    if (lower.contains('turn right') || lower.contains('belok kanan')) {
      return 'belok kanan';
    }
    if (lower.contains('turn left') || lower.contains('belok kiri')) {
      return 'belok kiri';
    }
    if (lower.contains('turn left') && lower.contains('slight')) {
      return 'belok kiri';
    }
    if (lower.contains('turn right') && lower.contains('slight')) {
      return 'belok kanan';
    }
    if (lower.contains('turn around') || lower.contains('putar balik')) {
      return 'putar balik';
    }
    if (lower.contains('keep left') || lower.contains('tetap kiri')) {
      return 'tetap di kiri';
    }
    if (lower.contains('keep right') || lower.contains('tetap kanan')) {
      return 'tetap di kanan';
    }
    if (lower.contains('merge') || lower.contains('gabung')) {
      return 'gabung ke jalan';
    }
    if (lower.contains('continue') ||
        lower.contains('head') ||
        lower.contains('follow') ||
        lower.contains('lanjut')) {
      return 'lurus';
    }
    if (lower.contains('destination') || lower.contains('tujuan')) {
      return 'sampai tujuan';
    }
    return raw;
  }

  /// Format singkat untuk banner: instruksi + jarak.
  static String formatForBanner(RouteStep step) {
    final instr = _translateInstruction(step.instruction);
    final dist = step.distanceText;
    if (dist.isEmpty || dist == '-') return instr;
    return '$instr ($dist)';
  }
}
