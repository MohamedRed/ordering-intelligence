import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import 'package:consumer_core/consumer_core.dart';

class GasOrderGradeSelector extends StatelessWidget {
  const GasOrderGradeSelector({
    super.key,
    required this.grades,
    required this.selectedGrade,
    required this.formatPrice,
    required this.onSelectGrade,
  });

  final List<MenuItem> grades;
  final MenuItem? selectedGrade;
  final String Function(int) formatPrice;
  final ValueChanged<MenuItem> onSelectGrade;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Select fuel grade', style: ShadTheme.of(context).textTheme.h4),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: grades
              .map((grade) => ChoiceChip(
                    label: Text(
                      '${grade.name} • ${formatPrice(grade.priceCents)} / L',
                    ),
                    selected: grade.id == selectedGrade?.id,
                    onSelected: (_) => onSelectGrade(grade),
                  ))
              .toList(),
        ),
      ],
    );
  }
}