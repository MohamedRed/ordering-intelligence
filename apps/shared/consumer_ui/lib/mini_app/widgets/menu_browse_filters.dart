import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import 'package:consumer_core/consumer_core.dart';
import '../chat/chat_context_categories.dart';
import '../chat/chat_context_fulfillment.dart';
import '../chat/chat_context_participants.dart';
import '../chat/chat_context_section.dart';

class MenuBrowseFilters extends StatelessWidget {
  const MenuBrowseFilters({
    super.key,
    required this.categories,
    required this.activeCategory,
    required this.onCategorySelected,
    required this.participants,
    required this.selectedParticipantId,
    required this.onParticipantSelected,
    required this.deliveryEnabled,
    required this.isDelivery,
    required this.onFulfillmentChanged,
  });

  final List<String> categories;
  final String activeCategory;
  final ValueChanged<String> onCategorySelected;
  final List<GroupOrderParticipant> participants;
  final String? selectedParticipantId;
  final ValueChanged<GroupOrderParticipant> onParticipantSelected;
  final bool deliveryEnabled;
  final bool isDelivery;
  final ValueChanged<bool> onFulfillmentChanged;

  @override
  Widget build(BuildContext context) {
    final sections = <Widget>[];
    if (participants.isNotEmpty) {
      sections.add(
        ChatContextSection(
          label: 'Group',
          child: ChatParticipantRow(
            participants: participants,
            selectedParticipantId: selectedParticipantId,
            onSelected: onParticipantSelected,
          ),
        ),
      );
    }
    if (deliveryEnabled) {
      sections.add(
        ChatContextSection(
          label: null,
          child: ChatFulfillmentRow(
            isDelivery: isDelivery,
            onChanged: onFulfillmentChanged,
          ),
        ),
      );
    }
    if (categories.isNotEmpty) {
      sections.add(
        ChatContextSection(
          label: null,
          child: ChatCategoryRow(
            categories: categories,
            activeCategory: activeCategory,
            onSelected: onCategorySelected,
          ),
        ),
      );
    }
    if (sections.isEmpty) {
      return const SizedBox.shrink();
    }
    return ShadCard(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < sections.length; i++) ...[
            if (i > 0) const SizedBox(height: 10),
            sections[i],
          ],
        ],
      ),
    );
  }
}
