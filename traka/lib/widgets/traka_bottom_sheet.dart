import 'package:flutter/material.dart';

/// [showModalBottomSheet] dengan barrier, bentuk, dan warna mengikuti tema Traka.
Future<T?> showTrakaModalBottomSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool isScrollControlled = false,
  bool isDismissible = true,
  bool enableDrag = true,
  bool useRootNavigator = false,
  bool useSafeArea = true,
  bool showDragHandle = true,
  Color? backgroundColor,
  ShapeBorder? shape,
  double? elevation,
  /// Jika false, caller menangani [MediaQuery.viewInsets] sendiri (hindari dobel padding).
  bool applyViewInsetsPadding = true,
}) {
  final theme = Theme.of(context);
  final cs = theme.colorScheme;
  final effectiveShape = shape ?? theme.bottomSheetTheme.shape;
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: isScrollControlled,
    isDismissible: isDismissible,
    enableDrag: enableDrag,
    useRootNavigator: useRootNavigator,
    useSafeArea: useSafeArea,
    showDragHandle: showDragHandle,
    backgroundColor:
        backgroundColor ?? theme.bottomSheetTheme.backgroundColor ?? cs.surface,
    barrierColor: cs.scrim.withValues(alpha: 0.52),
    elevation: elevation ?? theme.bottomSheetTheme.elevation ?? 10,
    shape: effectiveShape,
    clipBehavior: Clip.antiAlias,
    builder: (ctx) {
      Widget child = builder(ctx);
      if (applyViewInsetsPadding) {
        final bottomInset = MediaQuery.viewInsetsOf(ctx).bottom;
        child = Padding(
          padding: EdgeInsets.only(bottom: bottomInset),
          child: child,
        );
      }
      return child;
    },
  );
}
