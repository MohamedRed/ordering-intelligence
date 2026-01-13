import 'package:flutter/material.dart';

import 'telegram_webapp.dart';

class TelegramSafeArea extends StatelessWidget {
  const TelegramSafeArea({
    super.key,
    required this.child,
    this.extraTop = 24,
    this.extraBottom = 12,
  });

  final Widget child;
  final double extraTop;
  final double extraBottom;

  @override
  Widget build(BuildContext context) {
    final insets = TelegramWebApp.safeAreaInsets;
    return Padding(
      padding: EdgeInsets.only(
        top: insets.top + extraTop,
        left: insets.left,
        right: insets.right,
        bottom: insets.bottom + extraBottom,
      ),
      child: SafeArea(child: child),
    );
  }
}
