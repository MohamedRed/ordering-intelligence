import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../models/group_order.dart';
import 'group_order_detail_formatters.dart';
import 'group_order_detail_rows.dart';

class GroupOrderDetailParticipantsCard extends StatelessWidget {
  const GroupOrderDetailParticipantsCard({super.key, required this.groupOrder});

  final GroupOrder groupOrder;

  @override
  Widget build(BuildContext context) {
    return ShadCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Participants', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          if (groupOrder.participants.isEmpty)
            const Text('No participants yet.'),
          ...groupOrder.participants.map((participant) {
            final allocation =
                groupOrder.allocationFor(participant.participantId);
            final amount = allocation == null
                ? ''
                : formatGroupOrderCents(allocation.totalCents);

            return GroupOrderDetailValueRow(
              label: participant.label,
              value: amount,
              labelStyle: Theme.of(context).textTheme.bodyMedium,
              verticalPadding: 6,
            );
          }),
        ],
      ),
    );
  }
}
