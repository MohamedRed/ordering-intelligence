import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

class MinimalCard extends StatelessWidget {
  const MinimalCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.backgroundColor,
  });

  final Widget child;
  final EdgeInsets padding;
  final Color? backgroundColor;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: backgroundColor ?? theme.colorScheme.muted,
        borderRadius: BorderRadius.circular(16),
      ),
      child: child,
    );
  }
}
