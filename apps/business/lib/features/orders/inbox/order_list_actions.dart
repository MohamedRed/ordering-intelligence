import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../models/order.dart';
import '../../../providers/order_providers.dart';
import '../../../util/store_id.dart';
import '../../../widgets/shad_snackbar.dart';
import '../order_status_action_sheet.dart';

class OrderActionButtons extends StatelessWidget {
  const OrderActionButtons({super.key, required this.order, required this.ref});
  final Order order;
  final WidgetRef ref;

  @override
  Widget build(BuildContext context) {
    final actions = nextOrderActions(order.status);
    if (actions.isEmpty) return const SizedBox.shrink();
    return Wrap(
      spacing: 8,
      children: actions
          .map((status) => ShadButton.outline(
                onPressed: () => _handleStatus(context, ref, order.id, status),
                child: Text(orderStatusLabel(status)),
              ))
          .toList(),
    );
  }

  Future<void> _handleStatus(BuildContext context, WidgetRef ref,
      String orderId, OrderStatus status) async {
    final repo = ref.read(orderRepositoryProvider);
    try {
      final result = await showOrderStatusActionSheet(
        context: context,
        storeId: effectiveStoreId(),
        status: status,
      );
      if (result == null) return;
      await repo.setStatusWithAction(
        orderId,
        status,
        notifyMode: result.notifyMode,
        note: result.note,
        templateId: result.templateId,
      );
      ref.invalidate(ordersProvider);
      if (context.mounted) {
        showShadSnack(
          context,
          title: 'Order updated',
          message: 'Order $orderId → ${orderStatusLabel(status)}',
          type: ShadSnackType.success,
        );
      }
    } catch (err) {
      if (context.mounted) {
        showShadSnack(
          context,
          title: 'Update failed',
          message: '$err',
          type: ShadSnackType.error,
        );
      }
    }
  }
}

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

List<OrderStatus> nextOrderActions(OrderStatus current) {
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
