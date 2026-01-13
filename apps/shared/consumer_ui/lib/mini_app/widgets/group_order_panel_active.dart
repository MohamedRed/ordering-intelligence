import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import 'group_order_participants_list.dart';
import 'group_order_share_targets.dart';
import 'package:consumer_core/consumer_core.dart';
import '../mini_app_platform.dart';

class GroupOrderPanelActive extends StatelessWidget {
  const GroupOrderPanelActive({
    super.key,
    required this.groupOrder,
    required this.busy,
    required this.codeText,
    required this.primaryActionLabel,
    required this.onPrimaryAction,
    required this.secondaryActionLabel,
    required this.onSecondaryAction,
    required this.shareTargets,
    required this.onShareTarget,
  });

  final GroupOrderSession groupOrder;
  final bool busy;
  final String codeText;
  final String? primaryActionLabel;
  final VoidCallback? onPrimaryAction;
  final String? secondaryActionLabel;
  final VoidCallback? onSecondaryAction;
  final List<MiniAppShareTarget> shareTargets;
  final ValueChanged<MiniAppShareTarget>? onShareTarget;

  @override
  Widget build(BuildContext context) {
    final textTheme = ShadTheme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: Text(codeText, style: textTheme.small)),
            Text(groupOrder.status, style: textTheme.muted),
          ],
        ),
        const SizedBox(height: 8),
        GroupOrderParticipantsList(
          participants: groupOrder.participants,
          host: groupOrder.host,
        ),
        if (shareTargets.isNotEmpty && onShareTarget != null) ...[
          const SizedBox(height: 12),
          GroupOrderShareTargets(
            targets: shareTargets,
            onSelected: onShareTarget!,
            disabled: busy,
          ),
        ],
        const SizedBox(height: 12),
        Row(
          children: [
            if (secondaryActionLabel != null)
              ShadButton.outline(
                onPressed: busy ? null : onSecondaryAction,
                child: Text(secondaryActionLabel!),
              ),
            if (primaryActionLabel != null) ...[
              const SizedBox(width: 8),
              ShadButton(
                onPressed: busy ? null : onPrimaryAction,
                child: Text(primaryActionLabel!),
              ),
            ],
          ],
        ),
      ],
    );
  }
}
