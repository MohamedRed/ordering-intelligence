import 'package:flutter/material.dart';

import '../../models/order.dart';

Color orderStatusColor(OrderStatus status) {
  switch (status) {
    case OrderStatus.pending:
      return Colors.orange;
    case OrderStatus.confirmed:
      return Colors.blue;
    case OrderStatus.ready:
      return Colors.teal;
    case OrderStatus.completed:
      return Colors.green;
    case OrderStatus.cancelled:
      return Colors.grey;
  }
}

String orderStatusLabel(OrderStatus status) {
  switch (status) {
    case OrderStatus.pending:
      return 'Pending';
    case OrderStatus.confirmed:
      return 'Confirmed';
    case OrderStatus.ready:
      return 'Ready';
    case OrderStatus.completed:
      return 'Completed';
    case OrderStatus.cancelled:
      return 'Cancelled';
  }
}

List<OrderStatus> nextOrderStatusActions(OrderStatus current) {
  switch (current) {
    case OrderStatus.pending:
      return [OrderStatus.confirmed, OrderStatus.cancelled];
    case OrderStatus.confirmed:
      return [OrderStatus.ready, OrderStatus.cancelled];
    case OrderStatus.ready:
      return [OrderStatus.completed, OrderStatus.cancelled];
    case OrderStatus.completed:
    case OrderStatus.cancelled:
      return [];
  }
}

class OrderStatusPill extends StatelessWidget {
  const OrderStatusPill({super.key, required this.status});

  final OrderStatus status;

  @override
  Widget build(BuildContext context) {
    final color = orderStatusColor(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(orderStatusLabel(status), style: TextStyle(color: color)),
    );
  }
}
