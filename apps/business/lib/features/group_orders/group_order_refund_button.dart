import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../models/group_order.dart';
import '../../providers/group_order_providers.dart';
import '../../widgets/shad_snackbar.dart';
import 'group_order_refund_sheet.dart';

class GroupOrderRefundButton extends ConsumerWidget {
  const GroupOrderRefundButton({super.key, required this.groupOrder});
  final GroupOrder groupOrder;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ShadButton.outline(
      onPressed: () => _handleRefund(context, ref),
      child: const Text('Refund'),
    );
  }

  Future<void> _handleRefund(BuildContext context, WidgetRef ref) async {
    final action =
        await showGroupOrderRefundSheet(context: context, groupOrder: groupOrder);
    if (action == null) return;
    final repo = ref.read(groupOrderRepositoryProvider);
    try {
      await repo.refundGroupOrder(
        groupOrder.id,
        amountCents: action.amountCents,
        reason: action.reason,
        note: action.note,
        participantId: action.participantId,
      );
      ref
        ..invalidate(groupOrderDetailProvider(groupOrder.id))
        ..invalidate(groupOrdersProvider);
      if (context.mounted) {
        showShadSnack(
          context,
          title: 'Refund issued',
          message: 'Refund processed for group order ${groupOrder.id}.',
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
