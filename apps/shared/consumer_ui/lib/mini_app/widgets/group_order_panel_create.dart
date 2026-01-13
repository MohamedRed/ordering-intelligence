import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../mini_app_scope.dart';
import 'toggle_option_row.dart';

class GroupOrderPanelCreate extends StatelessWidget {
  const GroupOrderPanelCreate({
    super.key,
    required this.paymentMode,
    required this.paymentMethod,
    required this.busy,
    required this.onPaymentModeChanged,
    required this.onPaymentMethodChanged,
    required this.onCreate,
  });

  final String paymentMode;
  final String paymentMethod;
  final bool busy;
  final ValueChanged<String> onPaymentModeChanged;
  final ValueChanged<String> onPaymentMethodChanged;
  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    final isSplit = paymentMode == 'split_by_participant';
    final isCard = paymentMethod == 'card';
    final haptics = MiniAppScope.of(context).haptics;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ToggleOptionRow(
          title: 'Split payment',
          value: isSplit,
          offLabel: 'One payer',
          onLabel: 'Split pay',
          onChanged: (next) {
            onPaymentModeChanged(next ? 'split_by_participant' : 'single_payer');
          },
        ),
        const SizedBox(height: 10),
        ToggleOptionRow(
          title: 'Payment method',
          value: isCard,
          offLabel: 'Cash',
          onLabel: 'Card',
          onChanged: (next) {
            onPaymentMethodChanged(next ? 'card' : 'cash');
          },
        ),
        const SizedBox(height: 12),
        ShadButton(
          onPressed: busy
              ? null
              : () {
                  haptics.impact();
                  onCreate();
                },
          child: busy
              ? const SizedBox(
                  height: 16,
                  width: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Start group order'),
        ),
      ],
    );
  }
}
