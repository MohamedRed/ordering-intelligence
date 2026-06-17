import 'package:flutter/material.dart';

class DispatchFilterChips extends StatelessWidget {
  const DispatchFilterChips({
    super.key,
    required this.options,
    required this.selected,
    required this.onSelected,
    this.replaceUnderscores = false,
  });

  final List<String> options;
  final String selected;
  final ValueChanged<String> onSelected;
  final bool replaceUnderscores;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 6,
      children: [
        for (final option in options)
          ChoiceChip(
            label: Text(_label(option)),
            selected: selected == option,
            onSelected: (_) => onSelected(option),
          ),
      ],
    );
  }

  String _label(String value) {
    final label = replaceUnderscores ? value.replaceAll('_', ' ') : value;
    return label.toUpperCase();
  }
}
