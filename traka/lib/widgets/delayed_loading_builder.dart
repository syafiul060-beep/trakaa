import 'dart:async';

import 'package:flutter/material.dart';

/// Menunda tampilan loading widget agar terasa lebih responsif.
/// Jika loading selesai dalam [delay], loading widget tidak pernah ditampilkan.
/// Saat delay: tampilkan [placeholder]. Setelah delay: tampilkan [loadingWidget].
class DelayedLoadingBuilder extends StatefulWidget {
  final bool loading;
  final Widget loadingWidget;
  final Widget child;
  final Widget placeholder;
  final Duration delay;

  const DelayedLoadingBuilder({
    super.key,
    required this.loading,
    required this.loadingWidget,
    required this.child,
    this.placeholder = const SizedBox.shrink(),
    this.delay = const Duration(milliseconds: 200),
  });

  @override
  State<DelayedLoadingBuilder> createState() => _DelayedLoadingBuilderState();
}

class _DelayedLoadingBuilderState extends State<DelayedLoadingBuilder> {
  bool _showLoading = false;
  Timer? _timer;

  void _syncLoadingTimer() {
    if (widget.loading) {
      if (!_showLoading) {
        _timer?.cancel();
        _timer = Timer(widget.delay, () {
          if (mounted && widget.loading) {
            setState(() => _showLoading = true);
          }
        });
      }
    } else {
      _timer?.cancel();
      _showLoading = false;
    }
  }

  @override
  void initState() {
    super.initState();
    _syncLoadingTimer();
  }

  @override
  void didUpdateWidget(DelayedLoadingBuilder oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncLoadingTimer();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.loading) return widget.child;
    if (!_showLoading) return widget.placeholder;
    return widget.loadingWidget;
  }
}
