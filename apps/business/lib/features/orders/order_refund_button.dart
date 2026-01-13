import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../models/order.dart';
import '../../providers/order_api.dart';
import '../../providers/order_providers.dart';
import '../../providers/order_detail_provider.dart';
import '../../widgets/shad_snackbar.dart';
import 'order_refund_sheet.dart';

class OrderRefundButton extends ConsumerWidget {
  const OrderRefundButton({super.key, required this.order});
  final Order order;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ShadButton.outline(
      onPressed: () => _handleRefund(context, ref),
      child: const Text('Refund'),
    );
  }

  Future<void> _handleRefund(BuildContext context, WidgetRef ref) async {
    final action = await showOrderRefundSheet(context: context, order: order);
    if (action == null) return;
    final repo = ref.read(orderRepositoryProvider);
    try {
      await repo.refundOrder(
        order.id,
        amountCents: action.amountCents,
        reason: action.reason,
        note: action.note,
      );
      ref.invalidate(orderDetailProvider(order.id));
      if (context.mounted) {
        showShadSnack(
          context,
          title: 'Refund issued',
          message: 'Refund processed for order ${order.id}.',
          type: ShadSnackType.success,
        );
      }
    } catch (err) {
      if (context.mounted) {
        showShadSnack(
          context,
          title: 'Refund failed',
          message: '$err',
          type: ShadSnackType.error,
        );
      }
    }
  }
}
