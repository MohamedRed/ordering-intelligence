import 'package:consumer_core/consumer_core.dart';
import 'package:flutter/material.dart';

class GasOrderForm extends StatelessWidget {
  const GasOrderForm({
    super.key,
    required this.grades,
    required this.selectedGrade,
    required this.paymentFlow,
    required this.prepayMode,
    required this.amountController,
    required this.litersController,
    required this.preauthController,
    required this.preauthHint,
    required this.currencyCode,
    required this.isSubmitting,
    required this.errorMessage,
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
  final String? preauthHint;
  final String currencyCode;
  final bool isSubmitting;
  final String? errorMessage;
  final ValueChanged<MenuItem> onSelectGrade;
  final ValueChanged<FuelPaymentFlow> onPaymentFlowChanged;
  final ValueChanged<FuelPrepayMode> onPrepayModeChanged;
  final ValueChanged<String> onPreauthChanged;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Fuel grade', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        RadioGroup<MenuItem>(
          groupValue: selectedGrade,
          onChanged: (value) {
            if (value != null) onSelectGrade(value);
          },
          child: Column(
            children: grades
                .map(
                  (grade) => Card(
                    child: RadioListTile<MenuItem>(
                      value: grade,
                      title: Text(grade.name.isEmpty ? grade.id : grade.name),
                      subtitle: grade.priceCents > 0
                          ? Text('€${_formatMoney(grade.priceCents)} / L')
                          : null,
                    ),
                  ),
                )
                .toList(),
          ),
        ),
        const SizedBox(height: 16),
        Text('Payment flow', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        Wrap(
          spacing: 12,
          children: FuelPaymentFlow.values
              .map(
                (flow) => ChoiceChip(
                  label: Text(flow.label),
                  selected: paymentFlow == flow,
                  onSelected: (selected) {
                    if (selected) onPaymentFlowChanged(flow);
                  },
                ),
              )
              .toList(),
        ),
        const SizedBox(height: 12),
        if (paymentFlow == FuelPaymentFlow.prepay) ...[
          Wrap(
            spacing: 12,
            children: FuelPrepayMode.values
                .map(
                  (mode) => ChoiceChip(
                    label: Text(mode.label),
                    selected: prepayMode == mode,
                    onSelected: (selected) {
                      if (selected) onPrepayModeChanged(mode);
                    },
                  ),
                )
                .toList(),
          ),
          const SizedBox(height: 12),
          TextField(
            controller:
                prepayMode == FuelPrepayMode.amount ? amountController : litersController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: prepayMode == FuelPrepayMode.amount
                  ? 'Amount (${currencyCode.toUpperCase()})'
                  : 'Liters',
            ),
          ),
        ] else ...[
          TextField(
            controller: preauthController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: 'Max amount to authorize (${currencyCode.toUpperCase()})',
              helperText: preauthHint,
            ),
            onChanged: onPreauthChanged,
          ),
        ],
        if (errorMessage != null && errorMessage!.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text(
            errorMessage!,
            style: const TextStyle(color: Colors.redAccent),
          ),
        ],
        const SizedBox(height: 20),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: isSubmitting ? null : onSubmit,
            child: Text(isSubmitting ? 'Processing...' : 'Proceed to payment'),
          ),
        ),
      ],
    );
  }

  String _formatMoney(int cents) => (cents / 100).toStringAsFixed(2);
}
