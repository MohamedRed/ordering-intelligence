import 'package:consumer_core/consumer_core.dart';
import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'chat_context_categories.dart';
import 'chat_context_fulfillment.dart';
import 'chat_context_participants.dart';
import 'chat_context_section.dart';
import 'chat_context_selected_product.dart';

class ChatContextBar extends StatelessWidget {
  const ChatContextBar({
    super.key,
    required this.categories,
    required this.activeCategory,
    required this.onCategorySelected,
    required this.selectedProduct,
    required this.onClearProduct,
    required this.participants,
    required this.selectedParticipantId,
    required this.onParticipantSelected,
    required this.deliveryEnabled,
    required this.isDelivery,
    required this.onFulfillmentChanged,
    this.embedded = false,
  });

  final List<String> categories;
  final String activeCategory;
  final ValueChanged<String> onCategorySelected;
  final ChatProduct? selectedProduct;
  final VoidCallback? onClearProduct;
  final List<GroupOrderParticipant> participants;
  final String? selectedParticipantId;
  final ValueChanged<GroupOrderParticipant> onParticipantSelected;
  final bool deliveryEnabled, isDelivery;
  final ValueChanged<bool> onFulfillmentChanged;
  final bool embedded;

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
    if (selectedProduct != null) {
      sections.add(
        ChatContextSection(
          label: 'Selected',
          child: ChatSelectedProductChip(
            product: selectedProduct!,
            onClear: onClearProduct,
          ),
        ),
      );
    }
    if (sections.isEmpty) {
      return const SizedBox.shrink();
    }
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < sections.length; i++) ...[
          if (i > 0) const SizedBox(height: 10),
          sections[i],
        ],
      ],
    );
    if (embedded) {
      return content;
    }
    return ShadCard(padding: const EdgeInsets.all(12), child: content);
  }
}
