import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../mini_app_scope.dart';

class SegmentedOption<T> {
  const SegmentedOption({required this.value, required this.label});

  final T value;
  final String label;
}

class SegmentedControl<T> extends StatelessWidget {
  const SegmentedControl({
    super.key,
    required this.value,
    required this.options,
    required this.onChanged,
  });

  final T value;
  final List<SegmentedOption<T>> options;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final haptics = MiniAppScope.hapticsOf(context);
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: theme.colorScheme.muted,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: options
            .map(
              (option) => _SegmentButton<T>(
                label: option.label,
                active: option.value == value,
                onTap: () {
                  if (option.value == value) return;
                  haptics.selection();
                  onChanged(option.value);
                },
              ),
            )
            .toList(),
      ),
    );
  }
}

class _SegmentButton<T> extends StatelessWidget {
  const _SegmentButton({
    required this.label,
    required this.active,
    required this.onTap,
  });

  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final textStyle = theme.textTheme.small.copyWith(
      color: active
          ? theme.colorScheme.primaryForeground
          : theme.colorScheme.foreground,
      fontWeight: FontWeight.w600,
    );
    return Expanded(
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        decoration: BoxDecoration(
          color: active ? theme.colorScheme.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
        ),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Center(child: Text(label, style: textStyle)),
          ),
        ),
      ),
    );
  }
}
