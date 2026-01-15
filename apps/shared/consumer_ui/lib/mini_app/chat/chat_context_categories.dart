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
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (var index = 0; index < categories.length; index++) ...[
            ChatContextChip(
              label: categories[index],
              active: categories[index] == activeCategory,
              onTap: () => onSelected(categories[index]),
            ),
            if (index < categories.length - 1) const SizedBox(width: 8),
          ],
        ],
      ),
    );
  }
}
