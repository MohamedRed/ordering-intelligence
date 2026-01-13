import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../mini_app_scope.dart';

class CategoryChips extends StatelessWidget {
  const CategoryChips({
    super.key,
    required this.categories,
    required this.activeCategory,
    required this.onSelected,
  });

  final List<String> categories;
  final String activeCategory;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final haptics = MiniAppScope.of(context).haptics;
    return SizedBox(
      height: 40,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: categories.length,
        separatorBuilder: (context, _) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final category = categories[index];
          final selected = category == activeCategory;
          final selectedColor = theme.colorScheme.primary;
          final selectedTextColor = theme.colorScheme.primaryForeground;
          final unselectedColor = theme.colorScheme.muted;
          final unselectedTextColor = theme.colorScheme.foreground;
          return ChoiceChip(
            label: Text(category),
            selected: selected,
            showCheckmark: false,
            selectedColor: selectedColor,
            backgroundColor: unselectedColor,
            labelStyle: theme.textTheme.small.copyWith(
              color: selected ? selectedTextColor : unselectedTextColor,
            ),
            shape: const StadiumBorder(
              side: BorderSide(color: Colors.transparent),
            ),
            onSelected: (_) {
              haptics.selection();
              onSelected(category);
            },
          );
        },
      ),
    );
  }
}
