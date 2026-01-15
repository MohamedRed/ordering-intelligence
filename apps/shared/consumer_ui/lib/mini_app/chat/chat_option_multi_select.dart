import 'package:consumer_core/consumer_core.dart';
import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../mini_app_scope.dart';

class ChatOptionMultiSelect extends StatefulWidget {
  const ChatOptionMultiSelect({
    super.key,
    required this.options,
    required this.onConfirm,
    this.confirmLabel,
    this.minSelections,
    this.maxSelections,
  });

  final List<ChatOption> options;
  final void Function(List<ChatOption>) onConfirm;
  final String? confirmLabel;
  final int? minSelections;
  final int? maxSelections;

  @override
  State<ChatOptionMultiSelect> createState() => _ChatOptionMultiSelectState();
}

class _ChatOptionMultiSelectState extends State<ChatOptionMultiSelect> {
  final Set<int> _selected = <int>{};

  @override
  Widget build(BuildContext context) {
    if (widget.options.isEmpty) return const SizedBox.shrink();
    final theme = ShadTheme.of(context);
    final haptics = MiniAppScope.hapticsOf(context);
    final minSelections = widget.minSelections ?? 1;
    final maxSelections = widget.maxSelections;
    final canConfirm =
        _selected.length >= minSelections &&
        (maxSelections == null || _selected.length <= maxSelections);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (var index = 0; index < widget.options.length; index++)
              _MultiSelectChip(
                option: widget.options[index],
                isSelected: _selected.contains(index),
                onTap: () {
                  setState(() {
                    if (_selected.contains(index)) {
                      _selected.remove(index);
                    } else if (maxSelections == null ||
                        _selected.length < maxSelections) {
                      _selected.add(index);
                    }
                  });
                  haptics.selection();
                },
              ),
          ],
        ),
        const SizedBox(height: 8),
        ShadButton(
          size: ShadButtonSize.sm,
          onPressed: canConfirm
              ? () {
                  final selections = _selected.toList()..sort();
                  widget.onConfirm(
                    selections.map((idx) => widget.options[idx]).toList(),
                  );
                }
              : null,
          child: Text(widget.confirmLabel ?? 'Confirm'),
        ),
        if (!canConfirm)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              _buildHelperText(minSelections, maxSelections),
              style: theme.textTheme.small.copyWith(
                color: theme.colorScheme.mutedForeground,
              ),
            ),
          ),
      ],
    );
  }

  String _buildHelperText(int minSelections, int? maxSelections) {
    if (maxSelections != null && maxSelections != minSelections) {
      return 'Select $minSelections-$maxSelections options to continue.';
    }
    if (maxSelections != null && maxSelections == minSelections) {
      return 'Select $minSelections option${minSelections == 1 ? '' : 's'} to continue.';
    }
    return 'Select at least $minSelections option${minSelections == 1 ? '' : 's'} to continue.';
  }
}

class _MultiSelectChip extends StatelessWidget {
  const _MultiSelectChip({
    required this.option,
    required this.isSelected,
    required this.onTap,
  });

  final ChatOption option;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    if (isSelected) {
      return ShadButton(
        size: ShadButtonSize.sm,
        onPressed: onTap,
        child: Text(option.label),
      );
    }
    return ShadButton.outline(
      size: ShadButtonSize.sm,
      onPressed: onTap,
      child: Text(option.label),
    );
  }
}
