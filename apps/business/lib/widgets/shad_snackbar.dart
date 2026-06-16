import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

enum ShadSnackType { info, success, warning, error }

void showShadSnack(
  BuildContext context, {
  required String title,
  String? message,
  ShadSnackType type = ShadSnackType.info,
  Duration duration = const Duration(seconds: 3),
}) {
  final theme = ShadTheme.of(context);
  final colors = theme.colorScheme;

  Color bg = colors.primary;
  if (type == ShadSnackType.success) bg = colors.accent;
  if (type == ShadSnackType.warning) bg = colors.secondary;
  if (type == ShadSnackType.error) bg = colors.destructive;

  final snack = SnackBar(
    behavior: SnackBarBehavior.floating,
    backgroundColor: Colors.transparent,
    elevation: 0,
    duration: duration,
    content: ShadAlert.raw(
      variant: type == ShadSnackType.error
          ? ShadAlertVariant.destructive
          : ShadAlertVariant.primary,
      decoration: ShadDecoration(
        color: bg.withValues(alpha: 0.1),
        border: ShadBorder.all(
          color: bg.withValues(alpha: 0.35),
          width: 1,
          radius: BorderRadius.circular(10),
        ),
      ),
      leading: ShadBadge.outline(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        backgroundColor: Colors.transparent,
        foregroundColor: bg,
        child: Text(type.name),
      ),
      title: Text(
        title,
        style: TextStyle(color: colors.foreground),
      ),
      description: message != null
          ? Text(
              message,
              style: TextStyle(color: colors.mutedForeground),
            )
          : null,
    ),
  );

  ScaffoldMessenger.of(context).showSnackBar(snack);
}
