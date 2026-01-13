import 'package:flutter/material.dart';

enum OrderInboxFilter {
  all,
  orders,
  groupOrders,
  delivery,
}

extension OrderInboxFilterLabel on OrderInboxFilter {
  String get label {
    switch (this) {
      case OrderInboxFilter.all:
        return 'All';
      case OrderInboxFilter.orders:
        return 'Orders';
      case OrderInboxFilter.groupOrders:
        return 'Group orders';
      case OrderInboxFilter.delivery:
        return 'Delivery';
    }
  }
}

class OrderInboxFilterBar extends StatelessWidget {
  const OrderInboxFilterBar({
    super.key,
    required this.filter,
    required this.onChanged,
    required this.availableFilters,
    this.counts = const {},
  });

  final OrderInboxFilter filter;
  final ValueChanged<OrderInboxFilter> onChanged;
  final List<OrderInboxFilter> availableFilters;
  final Map<OrderInboxFilter, int> counts;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 6,
      children: availableFilters
          .map((option) => ChoiceChip(
                label: _FilterLabel(
                  label: option.label,
                  count: counts[option] ?? 0,
                ),
                selected: option == filter,
                onSelected: (_) => onChanged(option),
              ))
          .toList(),
    );
  }
}

class _FilterLabel extends StatelessWidget {
  const _FilterLabel({required this.label, required this.count});
  final String label;
  final int count;

  @override
  Widget build(BuildContext context) {
    final showCount = count > 0;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label),
        if (showCount) ...[
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              '$count',
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ],
    );
  }
}
