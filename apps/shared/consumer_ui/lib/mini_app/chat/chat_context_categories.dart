import 'package:flutter/material.dart';

import 'chat_context_chip.dart';

class ChatCategoryRow extends StatelessWidget {
  const ChatCategoryRow({
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
    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: categories.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final category = categories[index];
          return ChatContextChip(
            label: category,
            active: category == activeCategory,
            onTap: () => onSelected(category),
          );
        },
      ),
    );
  }
}
