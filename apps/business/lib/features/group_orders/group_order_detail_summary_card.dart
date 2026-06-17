import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../models/group_order.dart';
import 'group_order_detail_formatters.dart';
import 'group_order_detail_rows.dart';
import 'group_order_status_pill.dart';

class GroupOrderDetailSummaryCard extends StatelessWidget {
  const GroupOrderDetailSummaryCard({super.key, required this.groupOrder});

  final GroupOrder groupOrder;

  @override
  Widget build(BuildContext context) {
    final created = formatGroupOrderDate(groupOrder.createdAt);
    final expires = formatGroupOrderDate(groupOrder.expiresAt);
    final fulfillment = groupOrder.fulfillmentType.isEmpty
        ? 'Pickup'
        : groupOrder.fulfillmentType;
    final payment =
        '${groupOrder.paymentModeLabel} • ${groupOrder.paymentMethodLabel}';

    return ShadCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  groupOrder.hostLabel,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              const SizedBox(width: 12),
              GroupOrderStatusPill(status: groupOrder.status),
            ],
          ),
          const SizedBox(height: 10),
          GroupOrderDetailValueRow(
            label: 'Join code',
            value: joinCodeForGroupOrder(groupOrder),
            labelStyle: TextStyle(color: Colors.grey[700]),
          ),
          if (groupOrder.orderId.isNotEmpty)
            GroupOrderDetailValueRow(
              label: 'Order ID',
              value: groupOrder.orderId,
              labelStyle: TextStyle(color: Colors.grey[700]),
            ),
          GroupOrderDetailValueRow(
            label: 'Payment',
            value: payment,
            labelStyle: TextStyle(color: Colors.grey[700]),
          ),
          GroupOrderDetailValueRow(
            label: 'Total',
            value: groupOrder.formattedTotal,
            labelStyle: TextStyle(color: Colors.grey[700]),
          ),
          GroupOrderDetailValueRow(
            label: 'Fulfillment',
            value: fulfillment,
            labelStyle: TextStyle(color: Colors.grey[700]),
          ),
          GroupOrderDetailValueRow(
            label: 'Participants',
            value: '${groupOrder.participants.length}',
            labelStyle: TextStyle(color: Colors.grey[700]),
          ),
          GroupOrderDetailValueRow(
            label: 'Created',
            value: created,
            labelStyle: TextStyle(color: Colors.grey[700]),
          ),
          GroupOrderDetailValueRow(
            label: 'Expires',
            value: expires,
            labelStyle: TextStyle(color: Colors.grey[700]),
          ),
        ],
      ),
    );
  }
}
