import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

class ActionIconButton extends StatelessWidget {
  const ActionIconButton({
    super.key,
    required this.icon,
    required this.onPressed,
    this.size = 34,
    this.backgroundColor,
    this.iconColor,
  });

  final IconData icon;
  final VoidCallback onPressed;
  final double size;
  final Color? backgroundColor;
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final resolvedBackground = backgroundColor ?? Colors.white;
    final resolvedIconColor = iconColor ?? theme.colorScheme.foreground;
    return InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: resolvedBackground,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: theme.colorScheme.border),
        ),
        child: Icon(icon, size: 16, color: resolvedIconColor),
      ),
    );
  }
}
