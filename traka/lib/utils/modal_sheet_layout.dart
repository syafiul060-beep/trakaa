import 'dart:math' as math;

import 'package:flutter/widgets.dart';

/// Nilai [DraggableScrollableSheet] + padding scroll yang konsisten antar layar,
/// supaya aman di berbagai tinggi layar, inset sistem, dan keyboard — tanpa angka per ROM.
abstract final class ModalSheetLayout {
  ModalSheetLayout._();

  static double safeBottom(MediaQueryData mq) =>
      math.max(mq.padding.bottom, mq.viewPadding.bottom);

  static double keyboardTail(MediaQueryData mq) {
    final bi = mq.viewInsets.bottom;
    return bi > 0 ? math.min(bi * 0.2, 56) : 0;
  }

  /// Padding bawah konten di dalam [SingleChildScrollView] sheet (aman + keyboard).
  static double scrollableContentBottom(MediaQueryData mq, {double base = 40}) =>
      base + safeBottom(mq) + keyboardTail(mq);

  /// [maxChildSize] sheet: layar pendek dapat lebih tinggi agar tombol tidak ketutup.
  static double maxChildSizeForScreenHeight(double height) {
    if (height < 620) return 0.98;
    if (height < 720) return 0.96;
    return 0.94;
  }

  static double textFieldScrollPaddingBottom(MediaQueryData mq) =>
      200.0 + mq.viewInsets.bottom * 0.35;
}
