import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../models/group_order.dart';
import 'group_order_status_pill.dart';

class GroupOrderCard extends StatelessWidget {
  const GroupOrderCard({super.key, required this.groupOrder});

  final GroupOrder groupOrder;

  @override
  Widget build(BuildContext context) {
    final subtitle = groupOrder.itemsSummary();
    return ShadCard(
      padding: const EdgeInsets.all(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => context.push('/group-orders/${groupOrder.id}'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    groupOrder.hostLabel,
                    style: Theme.of(context).textTheme.titleMedium,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                GroupOrderStatusPill(status: groupOrder.status),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'Join: ${groupOrder.joinCode.isEmpty ? groupOrder.id : groupOrder.joinCode}',
              style: TextStyle(color: Colors.grey[700]),
            ),
            if (subtitle.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(subtitle),
            ],
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                _MetaChip(label: '${groupOrder.participants.length} participants'),
                _MetaChip(label: groupOrder.paymentModeLabel),
                _MetaChip(label: groupOrder.paymentMethodLabel),
              ],
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: Text(
                groupOrder.formattedTotal,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MetaChip extends StatelessWidget {
  const _MetaChip({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Text(label, style: const TextStyle(fontSize: 12)),
    );
  }
}
