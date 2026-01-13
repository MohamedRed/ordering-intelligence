import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../mini_app_scope.dart';

class ToggleOptionRow extends StatelessWidget {
  const ToggleOptionRow({
    super.key,
    required this.title,
    required this.value,
    required this.onChanged,
    this.offLabel,
    this.onLabel,
  });

  final String title;
  final bool value;
  final ValueChanged<bool> onChanged;
  final String? offLabel;
  final String? onLabel;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final detail = value ? onLabel : offLabel;
    final haptics = MiniAppScope.of(context).haptics;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: theme.colorScheme.muted,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: theme.textTheme.small),
                if (detail != null) ...[
                  const SizedBox(height: 2),
                  Text(detail, style: theme.textTheme.muted),
                ],
              ],
            ),
          ),
          Switch(
            value: value,
            activeThumbColor: theme.colorScheme.primary,
            onChanged: (next) {
              haptics.selection();
              onChanged(next);
            },
          ),
        ],
      ),
    );
  }
}
