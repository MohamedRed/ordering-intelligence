import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../models/group_order.dart';
import '../../models/group_order_allocation.dart';
import 'group_order_detail_formatters.dart';
import 'group_order_detail_rows.dart';

class GroupOrderDetailPricingCard extends StatelessWidget {
  const GroupOrderDetailPricingCard({super.key, required this.groupOrder});

  final GroupOrder groupOrder;

  @override
  Widget build(BuildContext context) {
    final pricing = groupOrder.pricing;
    if (pricing == null) return const SizedBox.shrink();

    return ShadCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Pricing', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          GroupOrderDetailValueRow(
            label: 'Subtotal',
            value: formatGroupOrderCents(pricing.subtotalCents),
          ),
          GroupOrderDetailValueRow(
            label: 'Tax',
            value: formatGroupOrderCents(pricing.taxCents),
          ),
          GroupOrderDetailValueRow(
            label: 'Fee',
            value: formatGroupOrderCents(pricing.feeCents),
          ),
          GroupOrderDetailValueRow(
            label: 'Discount',
            value: formatGroupOrderCents(pricing.discountCents),
          ),
          const Divider(height: 24),
          GroupOrderDetailValueRow(
            label: 'Total',
            value: formatGroupOrderCents(pricing.totalCents),
          ),
          if (pricing.allocations.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              'Allocations',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 6),
            ...pricing.allocations.map((allocation) {
              return _AllocationRow(
                allocation: allocation,
                label: groupOrder.participantLabel(allocation.participantId),
              );
            }),
          ],
        ],
      ),
    );
  }
}

class _AllocationRow extends StatelessWidget {
  const _AllocationRow({required this.allocation, required this.label});

  final GroupOrderAllocation allocation;
  final String label;

  @override
  Widget build(BuildContext context) {
    return GroupOrderDetailValueRow(
      label: label,
      value: formatGroupOrderCents(allocation.totalCents),
    );
  }
}
