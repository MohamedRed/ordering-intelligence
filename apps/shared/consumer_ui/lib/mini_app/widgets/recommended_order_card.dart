import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import 'minimal_card.dart';
import 'store_logo.dart';
import 'package:consumer_core/consumer_core.dart';

class RecommendedOrderCard extends StatelessWidget {
  const RecommendedOrderCard({
    super.key,
    required this.order,
    this.onTap,
    this.showStoreName = true,
    this.trailing,
  });

  final RecommendedOrder order;
  final VoidCallback? onTap;
  final bool showStoreName;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final subtitle = _buildSubtitle(context);
    final content = MinimalCard(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: SizedBox(
        height: 80,
        child: Row(
          children: [
            StoreLogo(name: order.storeName, logoUrl: order.logoUrl),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    showStoreName ? order.storeName : order.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: ShadTheme.of(context).textTheme.large,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: ShadTheme.of(context).textTheme.muted,
                  ),
                ],
              ),
            ),
            if (trailing != null) ...[
              const SizedBox(width: 12),
              trailing!,
            ] else if (onTap != null)
              const Icon(Icons.chevron_right),
          ],
        ),
      ),
    );
    if (onTap == null) {
      return content;
    }
    return GestureDetector(onTap: onTap, child: content);
  }

  String _buildSubtitle(BuildContext context) {
    final pieces = <String>[];
    final titleLower = order.title.toLowerCase();
    final hasCountInTitle =
        RegExp(r'\b\d+\b').hasMatch(order.title) &&
        (titleLower.contains('item') || titleLower.contains('article'));
    final orderedAt = DateTime.tryParse(order.orderedAtIso);
    if (order.isGroupOrder) {
      pieces.add('Group order');
      if (order.participantCount > 0) {
        pieces.add('${order.participantCount} people');
      }
    }
    if (orderedAt != null) {
      final dateLabel = MaterialLocalizations.of(
        context,
      ).formatShortDate(orderedAt);
      pieces.add('Ordered $dateLabel');
    } else {
      pieces.add('Ordered recently');
    }
    if (showStoreName) {
      if (order.title.isNotEmpty) {
        pieces.insert(0, order.title);
      }
    }
    if (order.itemCount > 0 && !hasCountInTitle) {
      pieces.add('${order.itemCount} items');
    }
    return pieces.join(' • ');
  }
}
