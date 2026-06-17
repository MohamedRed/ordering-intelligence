import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../models/order.dart';

class OrderDetailItemsSection extends StatelessWidget {
  const OrderDetailItemsSection({super.key, required this.items});

  final List<OrderItem> items;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Items', style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        ..._buildItems(theme, items),
      ],
    );
  }

  List<Widget> _buildItems(ThemeData theme, List<OrderItem> items) {
    final unbundled = <OrderItem>[];
    final bundles = <String, List<OrderItem>>{};

    for (final item in items) {
      final bundleId = item.bundleId.trim();
      if (bundleId.isEmpty) {
        unbundled.add(item);
        continue;
      }
      (bundles[bundleId] ??= []).add(item);
    }

    return [
      for (final item in unbundled)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: _OrderItemCard(theme: theme, item: item),
        ),
      for (final entry in bundles.entries)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: _BundleCard(
              theme: theme, bundleId: entry.key, items: entry.value),
        ),
    ];
  }
}

class _BundleCard extends StatelessWidget {
  const _BundleCard({
    required this.theme,
    required this.bundleId,
    required this.items,
  });

  final ThemeData theme;
  final String bundleId;
  final List<OrderItem> items;

  @override
  Widget build(BuildContext context) {
    final bundleItems = List<OrderItem>.from(items)
      ..sort((a, b) => bundleRoleSortKey(a.bundleRole)
          .compareTo(bundleRoleSortKey(b.bundleRole)));

    return ShadCard(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Bundle: $bundleId', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          for (final item in bundleItems)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _OrderItemCard(
                theme: theme,
                item: item,
                leadingLabel: item.bundleRole.trim().isEmpty
                    ? null
                    : '${item.bundleRole.trim()}: ',
              ),
            ),
        ],
      ),
    );
  }
}

class _OrderItemCard extends StatelessWidget {
  const _OrderItemCard({
    required this.theme,
    required this.item,
    this.leadingLabel,
  });

  final ThemeData theme;
  final OrderItem item;
  final String? leadingLabel;

  @override
  Widget build(BuildContext context) {
    final mods = item.modifierLabels;
    final label = leadingLabel ?? '';
    return ShadCard(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('$label${item.quantity}× ${item.name}',
              style: theme.textTheme.titleMedium),
          const SizedBox(height: 4),
          if (mods.isNotEmpty) Text('Mods: ${mods.join(', ')}'),
          Text('Price: \$${(item.priceCents / 100).toStringAsFixed(2)}'),
        ],
      ),
    );
  }
}

int bundleRoleSortKey(String role) {
  switch (role.trim().toLowerCase()) {
    case 'main':
      return 0;
    case 'side':
      return 1;
    case 'drink':
      return 2;
    case 'extra':
      return 3;
    default:
      return 99;
  }
}
