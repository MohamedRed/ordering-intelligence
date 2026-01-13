import 'package:consumer_core/consumer_core.dart';
import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../mini_app_scope.dart';
import '../mini_app_platform.dart';
import 'group_order_panel_body.dart';
import 'minimal_card.dart';

class GroupOrderPanel extends StatelessWidget {
  const GroupOrderPanel({
    super.key,
    required this.groupOrder,
    required this.paymentMode,
    required this.paymentMethod,
    required this.busy,
    required this.error,
    required this.codeText,
    required this.collapsed,
    required this.onToggle,
    required this.onPaymentModeChanged,
    required this.onPaymentMethodChanged,
    required this.onCreate,
    required this.primaryActionLabel,
    required this.onPrimaryAction,
    required this.secondaryActionLabel,
    required this.onSecondaryAction,
    required this.shareTargets,
    required this.onShareTarget,
  });

  final GroupOrderSession? groupOrder;
  final String paymentMode;
  final String paymentMethod;
  final bool busy;
  final String? error;
  final String? codeText;
  final bool collapsed;
  final VoidCallback onToggle;
  final ValueChanged<String> onPaymentModeChanged;
  final ValueChanged<String> onPaymentMethodChanged;
  final VoidCallback onCreate;
  final String? primaryActionLabel;
  final VoidCallback? onPrimaryAction;
  final String? secondaryActionLabel;
  final VoidCallback? onSecondaryAction;
  final List<MiniAppShareTarget> shareTargets;
  final ValueChanged<MiniAppShareTarget>? onShareTarget;

  @override
  Widget build(BuildContext context) {
    final textTheme = ShadTheme.of(context).textTheme;
    final haptics = MiniAppScope.of(context).haptics;
    return MinimalCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {
              haptics.selection();
              onToggle();
            },
            child: Row(
              children: [
                Expanded(child: Text('Group order', style: textTheme.large)),
                Icon(
                  collapsed ? Icons.expand_more : Icons.expand_less,
                ),
              ],
            ),
          ),
          GroupOrderPanelBody(
            groupOrder: groupOrder,
            paymentMode: paymentMode,
            paymentMethod: paymentMethod,
            busy: busy,
            error: error,
            codeText: codeText,
            primaryActionLabel: primaryActionLabel,
            onPrimaryAction: onPrimaryAction,
            secondaryActionLabel: secondaryActionLabel,
            onSecondaryAction: onSecondaryAction,
            shareTargets: shareTargets,
            onShareTarget: onShareTarget,
            onPaymentModeChanged: onPaymentModeChanged,
            onPaymentMethodChanged: onPaymentMethodChanged,
            onCreate: onCreate,
            collapsed: collapsed,
          ),
        ],
      ),
    );
  }
}
