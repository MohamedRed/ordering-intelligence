import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/group_order_providers.dart';
import '../../widgets/business_scaffold.dart';
import 'group_order_detail_error_state.dart';
import 'group_order_detail_items_card.dart';
import 'group_order_detail_participants_card.dart';
import 'group_order_detail_pricing_card.dart';
import 'group_order_detail_summary_card.dart';
import 'group_order_refund_button.dart';

class GroupOrderDetailScreen extends ConsumerWidget {
  const GroupOrderDetailScreen({super.key, required this.groupOrderId});
  final String groupOrderId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final groupOrderAsync = ref.watch(groupOrderDetailProvider(groupOrderId));
    return BusinessScaffold(
      title: Text('Group order $groupOrderId'),
      body: groupOrderAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => GroupOrderDetailErrorState(
          message: 'Failed to load group order',
          detail: '$err',
          onRetry: () => ref.refresh(groupOrderDetailProvider(groupOrderId)),
        ),
        data: (groupOrder) {
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              GroupOrderDetailSummaryCard(groupOrder: groupOrder),
              const SizedBox(height: 12),
              GroupOrderDetailParticipantsCard(groupOrder: groupOrder),
              const SizedBox(height: 12),
              GroupOrderDetailItemsCard(groupOrder: groupOrder),
              if (groupOrder.pricing != null) ...[
                const SizedBox(height: 12),
                GroupOrderDetailPricingCard(groupOrder: groupOrder),
              ],
              if (groupOrder.isCardPayment) ...[
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerLeft,
                  child: GroupOrderRefundButton(groupOrder: groupOrder),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}
