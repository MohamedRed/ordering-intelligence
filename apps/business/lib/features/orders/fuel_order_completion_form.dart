import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

class FuelOrderCompletionForm extends StatelessWidget {
  const FuelOrderCompletionForm({
    super.key,
    required this.litersController,
    required this.amountController,
    required this.isSubmitting,
    required this.errorMessage,
    required this.onSubmit,
  });

  final TextEditingController litersController;
  final TextEditingController amountController;
  final bool isSubmitting;
  final String? errorMessage;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    return ShadCard(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Complete fueling',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          ShadInput(
            controller: litersController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            placeholder: const Text('Final liters'),
          ),
          const SizedBox(height: 8),
          ShadInput(
            controller: amountController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            placeholder: const Text('Final amount (EUR)'),
          ),
          if (errorMessage != null) ...[
            const SizedBox(height: 8),
            Text(errorMessage!, style: TextStyle(color: Colors.red.shade400)),
          ],
          const SizedBox(height: 12),
          ShadButton(
            onPressed: isSubmitting ? null : onSubmit,
            child: Text(isSubmitting ? 'Saving...' : 'Capture and complete'),
          ),
        ],
      ),
    );
  }
}
