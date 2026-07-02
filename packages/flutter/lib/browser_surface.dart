import 'package:flutter/material.dart';

import 'browser_controller.dart';

/// Widget that renders the embedded browser backend driven by a
/// [NapaxiBrowserController], showing [placeholder] while no page is loaded.
class NapaxiBrowserSurface extends StatelessWidget {
  /// Creates a surface bound to [controller], with an optional empty-state
  /// [placeholder] shown until a page is open.
  const NapaxiBrowserSurface({
    super.key,
    required this.controller,
    this.placeholder,
  });

  /// Controller whose backend web view is rendered and whose state is observed.
  final NapaxiBrowserController controller;

  /// Widget shown when the controller has no active page.
  final Widget? placeholder;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        if (!controller.hasPage && placeholder != null) {
          return placeholder!;
        }
        return controller.buildWebView();
      },
    );
  }
}
