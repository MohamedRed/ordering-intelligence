import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:consumer_core/consumer_core.dart';

import '../widgets/segmented_control.dart';

class GasOrderPaymentForm extends StatelessWidget {
  const GasOrderPaymentForm({
    super.key,
    required this.paymentFlow,
    required this.prepayMode,
    required this.amountController,
    required this.litersController,
    required this.preauthController,
    required this.preauthHint,
    required this.onPaymentFlowChanged,
    required this.onPrepayModeChanged,
    required this.onPreauthChanged,
  });

  final FuelPaymentFlow paymentFlow;
  final FuelPrepayMode prepayMode;
  final TextEditingController amountController;
  final TextEditingController litersController;
  final TextEditingController preauthController;
  final String? preauthHint;
  final ValueChanged<FuelPaymentFlow> onPaymentFlowChanged;
  final ValueChanged<FuelPrepayMode> onPrepayModeChanged;
  final ValueChanged<String> onPreauthChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Payment flow', style: ShadTheme.of(context).textTheme.h4),
        const SizedBox(height: 8),
        SegmentedControl<FuelPaymentFlow>(
          value: paymentFlow,
          options: [
            SegmentedOption(
              value: FuelPaymentFlow.prepay,
              label: FuelPaymentFlow.prepay.label,
            ),
            SegmentedOption(
              value: FuelPaymentFlow.preauth,
              label: FuelPaymentFlow.preauth.label,
            ),
          ],
          onChanged: onPaymentFlowChanged,
        ),
        const SizedBox(height: 12),
        if (paymentFlow == FuelPaymentFlow.prepay) ...[
          SegmentedControl<FuelPrepayMode>(
            value: prepayMode,
            options: [
              SegmentedOption(
                value: FuelPrepayMode.amount,
                label: FuelPrepayMode.amount.label,
              ),
              SegmentedOption(
                value: FuelPrepayMode.liters,
                label: FuelPrepayMode.liters.label,
              ),
            ],
            onChanged: onPrepayModeChanged,
          ),
          const SizedBox(height: 12),
          ShadInput(
            controller: prepayMode == FuelPrepayMode.amount
                ? amountController
                : litersController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            placeholder: Text(
              prepayMode == FuelPrepayMode.amount ? 'Amount (EUR)' : 'Liters',
            ),
          ),
        ] else ...[
          ShadInput(
            controller: preauthController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            placeholder: Text(
              preauthHint?.isNotEmpty == true
                  ? preauthHint!
                  : 'Max amount to authorize (EUR)',
            ),
            onChanged: onPreauthChanged,
          ),
        ],
      ],
    );
  }
}
