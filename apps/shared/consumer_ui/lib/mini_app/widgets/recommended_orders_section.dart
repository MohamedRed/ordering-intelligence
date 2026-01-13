import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import 'recommended_order_card.dart';
import 'package:consumer_core/consumer_core.dart';

class RecommendedOrdersSection extends StatelessWidget {
  const RecommendedOrdersSection({
    super.key,
    required this.title,
    required this.orders,
    this.onSelect,
    this.showStoreName = true,
    this.inline = false,
  });

  final String title;
  final List<RecommendedOrder> orders;
  final ValueChanged<RecommendedOrder>? onSelect;
  final bool showStoreName;
  final bool inline;

  @override
  Widget build(BuildContext context) {
    if (inline) {
      return _buildInline(context);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: ShadTheme.of(context).textTheme.large),
        const SizedBox(height: 8),
        for (final order in orders) ...[
          RecommendedOrderCard(
            order: order,
            showStoreName: showStoreName,
            onTap: onSelect == null ? null : () => onSelect!(order),
          ),
          const SizedBox(height: 12),
        ],
      ],
    );
  }

  Widget _buildInline(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: ShadTheme.of(context).textTheme.large),
        const SizedBox(height: 8),
        SizedBox(
          height: 92,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: orders.length,
            separatorBuilder: (_, __) => const SizedBox(width: 12),
            itemBuilder: (context, index) {
              final order = orders[index];
              return SizedBox(
                width: 260,
                child: RecommendedOrderCard(
                  order: order,
                  showStoreName: showStoreName,
                  onTap: onSelect == null ? null : () => onSelect!(order),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}