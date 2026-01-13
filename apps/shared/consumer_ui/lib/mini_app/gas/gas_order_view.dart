import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import 'gas_order_grade_selector.dart';
import 'gas_order_payment_form.dart';
import 'package:consumer_core/consumer_core.dart';

class GasOrderView extends StatelessWidget {
  const GasOrderView({
    super.key,
    required this.grades,
    required this.selectedGrade,
    required this.paymentFlow,
    required this.prepayMode,
    required this.amountController,
    required this.litersController,
    required this.preauthController,
    required this.isSubmitting,
    required this.errorMessage,
    required this.formatPrice,
    required this.preauthHint,
    required this.onSelectGrade,
    required this.onPaymentFlowChanged,
    required this.onPrepayModeChanged,
    required this.onPreauthChanged,
    required this.onSubmit,
  });

  final List<MenuItem> grades;
  final MenuItem? selectedGrade;
  final FuelPaymentFlow paymentFlow;
  final FuelPrepayMode prepayMode;
  final TextEditingController amountController;
  final TextEditingController litersController;
  final TextEditingController preauthController;
  final bool isSubmitting;
  final String? errorMessage;
  final String Function(int) formatPrice;
  final String? preauthHint;
  final ValueChanged<MenuItem> onSelectGrade;
  final ValueChanged<FuelPaymentFlow> onPaymentFlowChanged;
  final ValueChanged<FuelPrepayMode> onPrepayModeChanged;
  final ValueChanged<String> onPreauthChanged;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      children: [
        GasOrderGradeSelector(
          grades: grades,
          selectedGrade: selectedGrade,
          formatPrice: formatPrice,
          onSelectGrade: onSelectGrade,
        ),
        const SizedBox(height: 16),
        GasOrderPaymentForm(
          paymentFlow: paymentFlow,
          prepayMode: prepayMode,
          amountController: amountController,
          litersController: litersController,
          preauthController: preauthController,
          preauthHint: preauthHint,
          onPaymentFlowChanged: onPaymentFlowChanged,
          onPrepayModeChanged: onPrepayModeChanged,
          onPreauthChanged: onPreauthChanged,
        ),
        if (errorMessage != null && errorMessage!.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text(errorMessage!, style: TextStyle(color: Colors.red.shade400)),
        ],
        const SizedBox(height: 20),
        ShadButton(
          onPressed: isSubmitting ? null : onSubmit,
          child: Text(isSubmitting ? 'Processing...' : 'Proceed to payment'),
        ),
      ],
    );
  }
}
