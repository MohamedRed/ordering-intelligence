import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import 'chat_context_fulfillment.dart';

class ChatContextPanel extends StatelessWidget {
  const ChatContextPanel({
    super.key,
    required this.expanded,
    required this.onToggleExpanded,
    required this.summaryText,
    required this.deliveryEnabled,
    required this.isDelivery,
    required this.onFulfillmentChanged,
    required this.expandedContent,
    this.embedded = false,
    this.showToggle = true,
    this.showExpandedContentWhenEmbedded = false,
  });

  final bool expanded;
  final VoidCallback onToggleExpanded;
  final String? summaryText;
  final bool deliveryEnabled;
  final bool isDelivery;
  final ValueChanged<bool> onFulfillmentChanged;
  final Widget expandedContent;
  final bool embedded;
  final bool showToggle;
  final bool showExpandedContentWhenEmbedded;

  @override
  Widget build(BuildContext context) {
    final hasSummary = summaryText != null && summaryText!.trim().isNotEmpty;
    final summaryRow = Row(
      children: [
        if (deliveryEnabled) ...[
          ChatFulfillmentRow(
            isDelivery: isDelivery,
            onChanged: onFulfillmentChanged,
          ),
          const SizedBox(width: 12),
        ],
        if (hasSummary)
          Expanded(
            child: Text(
              summaryText!,
              style: ShadTheme.of(context).textTheme.small,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          )
        else if (showToggle)
          const Spacer(),
        if (showToggle) ...[
          const SizedBox(width: 8),
          ShadButton.outline(
            size: ShadButtonSize.sm,
            onPressed: onToggleExpanded,
            child: Text(expanded ? 'Hide' : 'Details'),
          ),
        ],
      ],
    );

    if (embedded) {
      if (!showToggle) {
        if (!showExpandedContentWhenEmbedded) {
          return summaryRow;
        }
        if (!hasSummary && !deliveryEnabled) {
          return expandedContent;
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [summaryRow, const SizedBox(height: 10), expandedContent],
        );
      }
      if (!expanded) {
        return summaryRow;
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [summaryRow, const SizedBox(height: 10), expandedContent],
      );
    }

    if (expanded && showToggle) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _ContextHeader(
            label: 'Context',
            actionLabel: 'Hide',
            actionIcon: Icons.expand_less,
            onAction: onToggleExpanded,
          ),
          const SizedBox(height: 8),
          expandedContent,
        ],
      );
    }

    return ShadCard(padding: const EdgeInsets.all(12), child: summaryRow);
  }
}

class _ContextHeader extends StatelessWidget {
  const _ContextHeader({
    required this.label,
    required this.actionLabel,
    required this.actionIcon,
    required this.onAction,
  });

  final String label;
  final String actionLabel;
  final IconData actionIcon;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(label, style: ShadTheme.of(context).textTheme.large),
        ),
        ShadButton.outline(
          size: ShadButtonSize.sm,
          onPressed: onAction,
          child: Row(
            children: [
              Icon(actionIcon, size: 16),
              const SizedBox(width: 4),
              Text(actionLabel),
            ],
          ),
        ),
      ],
    );
  }
}
