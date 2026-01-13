import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../mini_app_platform.dart';

class GroupOrderShareTargets extends StatelessWidget {
  const GroupOrderShareTargets({
    super.key,
    required this.targets,
    required this.onSelected,
    this.disabled = false,
  });

  final List<MiniAppShareTarget> targets;
  final ValueChanged<MiniAppShareTarget> onSelected;
  final bool disabled;

  @override
  Widget build(BuildContext context) {
    if (targets.isEmpty) return const SizedBox.shrink();
    final theme = ShadTheme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Quick share', style: theme.textTheme.small),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: targets
              .map(
                (target) => ShadButton.outline(
                  onPressed: disabled ? null : () => onSelected(target),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(_iconForTarget(target.id), size: 16),
                      const SizedBox(width: 6),
                      Text(target.label),
                    ],
                  ),
                ),
              )
              .toList(),
        ),
      ],
    );
  }

  IconData _iconForTarget(String id) {
    switch (id) {
      case 'telegram':
        return Icons.send;
      case 'whatsapp':
        return Icons.chat;
      case 'messenger':
        return Icons.message;
      case 'discord':
        return Icons.forum;
      case 'sms':
        return Icons.sms;
      case 'system':
        return Icons.share;
      default:
        return Icons.share;
    }
  }
}
