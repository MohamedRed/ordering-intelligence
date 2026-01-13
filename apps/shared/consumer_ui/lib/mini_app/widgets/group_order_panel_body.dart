import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import 'group_order_panel_active.dart';
import 'group_order_panel_create.dart';
import 'package:consumer_core/consumer_core.dart';
import '../mini_app_platform.dart';

class GroupOrderPanelBody extends StatelessWidget {
  const GroupOrderPanelBody({
    super.key,
    required this.groupOrder,
    required this.paymentMode,
    required this.paymentMethod,
    required this.busy,
    required this.error,
    required this.codeText,
    required this.primaryActionLabel,
    required this.onPrimaryAction,
    required this.secondaryActionLabel,
    required this.onSecondaryAction,
    required this.shareTargets,
    required this.onShareTarget,
    required this.onPaymentModeChanged,
    required this.onPaymentMethodChanged,
    required this.onCreate,
    required this.collapsed,
  });

  final GroupOrderSession? groupOrder;
  final String paymentMode;
  final String paymentMethod;
  final bool busy;
  final String? error;
  final String? codeText;
  final String? primaryActionLabel;
  final VoidCallback? onPrimaryAction;
  final String? secondaryActionLabel;
  final VoidCallback? onSecondaryAction;
  final List<MiniAppShareTarget> shareTargets;
  final ValueChanged<MiniAppShareTarget>? onShareTarget;
  final ValueChanged<String> onPaymentModeChanged;
  final ValueChanged<String> onPaymentMethodChanged;
  final VoidCallback onCreate;
  final bool collapsed;

  @override
  Widget build(BuildContext context) {
    return AnimatedCrossFade(
      firstChild: const SizedBox.shrink(),
      secondChild: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (groupOrder == null)
            GroupOrderPanelCreate(
              paymentMode: paymentMode,
              paymentMethod: paymentMethod,
              busy: busy,
              onPaymentModeChanged: onPaymentModeChanged,
              onPaymentMethodChanged: onPaymentMethodChanged,
              onCreate: onCreate,
            )
          else
            GroupOrderPanelActive(
              groupOrder: groupOrder!,
              busy: busy,
              codeText: codeText ?? 'Group order active',
              primaryActionLabel: primaryActionLabel,
              onPrimaryAction: onPrimaryAction,
              secondaryActionLabel: secondaryActionLabel,
              onSecondaryAction: secondaryActionLabel == null ? null : onSecondaryAction,
              shareTargets: shareTargets,
              onShareTarget: onShareTarget,
            ),
          if (error != null) ...[
            const SizedBox(height: 12),
            ShadAlert.destructive(
              title: const Text('Group order issue'),
              description: Text(error!),
            ),
          ],
        ],
      ),
      crossFadeState: collapsed ? CrossFadeState.showFirst : CrossFadeState.showSecond,
      duration: const Duration(milliseconds: 200),
    );
  }
}
