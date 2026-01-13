import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../models/group_order.dart';
import '../../models/group_order_allocation.dart';
import '../../providers/group_order_providers.dart';
import '../../widgets/business_scaffold.dart';
import 'group_order_refund_button.dart';
import 'group_order_status_pill.dart';

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
        error: (err, _) => _ErrorState(
          message: 'Failed to load group order',
          detail: '$err',
          onRetry: () => ref.refresh(groupOrderDetailProvider(groupOrderId)),
        ),
        data: (groupOrder) {
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _SummaryCard(groupOrder: groupOrder),
              const SizedBox(height: 12),
              _ParticipantsCard(groupOrder: groupOrder),
              const SizedBox(height: 12),
              _ItemsCard(groupOrder: groupOrder),
              if (groupOrder.pricing != null) ...[
                const SizedBox(height: 12),
                _PricingCard(groupOrder: groupOrder),
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

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.groupOrder});
  final GroupOrder groupOrder;

  @override
  Widget build(BuildContext context) {
    final created = _formatDate(groupOrder.createdAt);
    final expires = _formatDate(groupOrder.expiresAt);
    final fulfillment = groupOrder.fulfillmentType.isEmpty
        ? 'Pickup'
        : groupOrder.fulfillmentType;
    return ShadCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(groupOrder.hostLabel,
                    style: Theme.of(context).textTheme.titleLarge),
              ),
              GroupOrderStatusPill(status: groupOrder.status),
            ],
          ),
          const SizedBox(height: 10),
          _InfoRow(label: 'Join code', value: _joinCode(groupOrder)),
          if (groupOrder.orderId.isNotEmpty)
            _InfoRow(label: 'Order ID', value: groupOrder.orderId),
          _InfoRow(
              label: 'Payment',
              value:
                  '${groupOrder.paymentModeLabel} • ${groupOrder.paymentMethodLabel}'),
          _InfoRow(label: 'Total', value: groupOrder.formattedTotal),
          _InfoRow(label: 'Fulfillment', value: fulfillment),
          _InfoRow(label: 'Participants', value: '${groupOrder.participants.length}'),
          _InfoRow(label: 'Created', value: created),
          _InfoRow(label: 'Expires', value: expires),
        ],
      ),
    );
  }
}

class _ParticipantsCard extends StatelessWidget {
  const _ParticipantsCard({required this.groupOrder});
  final GroupOrder groupOrder;

  @override
  Widget build(BuildContext context) {
    return ShadCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Participants', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          if (groupOrder.participants.isEmpty)
            const Text('No participants yet.'),
          ...groupOrder.participants.map((participant) {
            final allocation = groupOrder.allocationFor(participant.participantId);
            final amount = allocation != null
                ? _formatCents(allocation.totalCents)
                : '';
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      participant.label,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ),
                  if (amount.isNotEmpty) Text(amount),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}

class _ItemsCard extends StatelessWidget {
  const _ItemsCard({required this.groupOrder});
  final GroupOrder groupOrder;

  @override
  Widget build(BuildContext context) {
    return ShadCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Items', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          if (groupOrder.items.isEmpty) const Text('No items added yet.'),
          ...groupOrder.items.map((item) {
            final lineTotal = item.priceCents * item.quantity;
            final participant = item.participantLabel.isNotEmpty
                ? item.participantLabel
                : (item.participantId.isNotEmpty
                    ? groupOrder.participantLabel(item.participantId)
                    : '');
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text('${item.quantity}x ${item.name}'),
                      ),
                      Text(_formatCents(lineTotal)),
                    ],
                  ),
                  if (participant.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        'Added by $participant',
                        style: TextStyle(color: Colors.grey[700], fontSize: 12),
                      ),
                    ),
                  if (item.modifierLabels.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        item.modifierLabels.join(', '),
                        style: TextStyle(color: Colors.grey[700], fontSize: 12),
                      ),
                    ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}

class _PricingCard extends StatelessWidget {
  const _PricingCard({required this.groupOrder});
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
          _PricingRow(label: 'Subtotal', value: _formatCents(pricing.subtotalCents)),
          _PricingRow(label: 'Tax', value: _formatCents(pricing.taxCents)),
          _PricingRow(label: 'Fee', value: _formatCents(pricing.feeCents)),
          _PricingRow(
              label: 'Discount', value: _formatCents(pricing.discountCents)),
          const Divider(height: 24),
          _PricingRow(label: 'Total', value: _formatCents(pricing.totalCents)),
          if (pricing.allocations.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text('Allocations',
                style: Theme.of(context).textTheme.bodyMedium),
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
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(child: Text(label)),
          Text(_formatCents(allocation.totalCents)),
        ],
      ),
    );
  }
}

class _PricingRow extends StatelessWidget {
  const _PricingRow({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(child: Text(label)),
          Text(value),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(color: Colors.grey[700]),
            ),
          ),
          Text(value),
        ],
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState(
      {required this.message, required this.detail, required this.onRetry});
  final String message;
  final String detail;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ShadAlert.destructive(
              title: Text(message),
              description: Text(detail),
            ),
            const SizedBox(height: 12),
            ShadButton.outline(
              onPressed: onRetry,
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}

String _formatCents(int cents) {
  if (cents == 0) return '—';
  final value = (cents / 100).toStringAsFixed(2);
  return '\$$value';
}

String _formatDate(DateTime? value) {
  if (value == null) return '—';
  final local = value.toLocal();
  final mm = local.month.toString().padLeft(2, '0');
  final dd = local.day.toString().padLeft(2, '0');
  final hh = local.hour.toString().padLeft(2, '0');
  final min = local.minute.toString().padLeft(2, '0');
  return '${local.year}-$mm-$dd $hh:$min';
}

String _joinCode(GroupOrder order) {
  return order.joinCode.isNotEmpty ? order.joinCode : order.id;
}
