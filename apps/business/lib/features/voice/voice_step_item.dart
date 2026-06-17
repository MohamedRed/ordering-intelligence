import 'package:flutter/material.dart';

class VoiceStepItem extends StatelessWidget {
  const VoiceStepItem({
    super.key,
    required this.label,
    required this.active,
    required this.done,
  });

  final String label;
  final bool active;
  final bool done;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: done || active ? Colors.green : cs.outlineVariant,
          ),
        ),
        const SizedBox(width: 8),
        Text(
          label,
          style: TextStyle(
            fontWeight: active ? FontWeight.w700 : FontWeight.w500,
            color: active ? null : cs.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}
