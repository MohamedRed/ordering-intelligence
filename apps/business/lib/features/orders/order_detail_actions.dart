import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../models/order.dart';
import '../../providers/order_detail_provider.dart';
import '../../providers/order_providers.dart';
import '../../util/store_id.dart';
import '../../widgets/shad_snackbar.dart';
import 'order_refund_button.dart';
import 'order_status_action_sheet.dart';
import 'order_status_helpers.dart';

class OrderDetailActions extends ConsumerWidget {
  const OrderDetailActions({super.key, required this.order});

  final Order order;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final actions = nextOrderStatusActions(order.status);
    final canNotifyDelay = order.status != OrderStatus.cancelled &&
        order.status != OrderStatus.completed;
    final canRefund = order.isCardPayment && order.totalCents > 0;
    if (actions.isEmpty && !canNotifyDelay && !canRefund) {
      return const SizedBox.shrink();
    }

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        ...actions.map(
          (status) => ShadButton.outline(
            onPressed: () => _handleStatus(context, ref, order.id, status),
            child: Text(orderStatusLabel(status)),
          ),
        ),
        if (canRefund) OrderRefundButton(order: order),
        if (canNotifyDelay)
          ShadButton.outline(
            onPressed: () => _handleDelay(context, ref, order.id),
            child: const Text('Notify delay'),
          ),
      ],
    );
  }

  Future<void> _handleStatus(
    BuildContext context,
    WidgetRef ref,
    String orderId,
    OrderStatus status,
  ) async {
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
      ref
        ..invalidate(orderDetailProvider(orderId))
        ..invalidate(ordersProvider);
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

  Future<void> _handleDelay(
    BuildContext context,
    WidgetRef ref,
    String orderId,
  ) async {
    final repo = ref.read(orderRepositoryProvider);
    try {
      final result = await showOrderDelayActionSheet(
        context: context,
        storeId: effectiveStoreId(),
      );
      if (result == null) return;
      await repo.notifyDelayWithAction(
        orderId,
        notifyMode: result.notifyMode,
        note: result.note,
        templateId: result.templateId,
      );
      if (context.mounted) {
        showShadSnack(
          context,
          title: 'Delay notice sent',
          message: 'Customer was notified for order $orderId',
          type: ShadSnackType.success,
        );
      }
    } catch (err) {
      if (context.mounted) {
        showShadSnack(
          context,
          title: 'Notify failed',
          message: '$err',
          type: ShadSnackType.error,
        );
      }
    }
  }
}
