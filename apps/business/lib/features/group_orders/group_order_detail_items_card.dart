import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../models/group_order.dart';
import 'group_order_detail_formatters.dart';
import 'group_order_detail_rows.dart';

class GroupOrderDetailItemsCard extends StatelessWidget {
  const GroupOrderDetailItemsCard({super.key, required this.groupOrder});

  final GroupOrder groupOrder;

  @override
  Widget build(BuildContext context) {
    return ShadCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Items', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          if (groupOrder.items.isEmpty) const Text('No items added yet.'),
          ...groupOrder.items.map((item) {
            final lineTotal = item.priceCents * item.quantity;
            final participant = item.participantLabel.isNotEmpty
                ? item.participantLabel
                : (item.participantId.isNotEmpty
                    ? groupOrder.participantLabel(item.participantId)
                    : '');

            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  GroupOrderDetailValueRow(
                    label: '${item.quantity}x ${item.name}',
                    value: formatGroupOrderCents(lineTotal),
                    verticalPadding: 0,
                  ),
                  if (participant.isNotEmpty)
                    _ItemDetailText(value: 'Added by $participant'),
                  if (item.modifierLabels.isNotEmpty)
                    _ItemDetailText(value: item.modifierLabels.join(', ')),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}

class _ItemDetailText extends StatelessWidget {
  const _ItemDetailText({required this.value});

  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Text(
        value,
        style: TextStyle(color: Colors.grey[700], fontSize: 12),
      ),
    );
  }
}
