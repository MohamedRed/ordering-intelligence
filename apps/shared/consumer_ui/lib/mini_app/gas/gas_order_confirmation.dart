import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

class GasOrderConfirmation extends StatelessWidget {
  const GasOrderConfirmation({
    super.key,
    required this.order,
    required this.pumpController,
    required this.onSubmitPump,
    required this.onNewOrder,
    required this.isSubmitting,
    required this.errorMessage,
  });

  final Map<String, dynamic> order;
  final TextEditingController pumpController;
  final VoidCallback onSubmitPump;
  final VoidCallback onNewOrder;
  final bool isSubmitting;
  final String? errorMessage;

  @override
  Widget build(BuildContext context) {
    final orderId = (order['id'] ?? '').toString();
    final fuel = order['fuel'] as Map? ?? const {};
    final grade = (fuel['fuelGradeName'] ?? '').toString();
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.local_gas_station, size: 48, color: Colors.green),
            const SizedBox(height: 12),
            Text('Fuel order placed', style: ShadTheme.of(context).textTheme.h2),
            if (orderId.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text('Order #$orderId', style: ShadTheme.of(context).textTheme.muted),
            ],
            if (grade.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text('Fuel grade: $grade'),
            ],
            const SizedBox(height: 16),
            ShadInput(
              controller: pumpController,
              keyboardType: TextInputType.number,
              placeholder: const Text('Pump number (on arrival)'),
            ),
            if (errorMessage != null && errorMessage!.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(errorMessage!, style: TextStyle(color: Colors.red.shade400)),
            ],
            const SizedBox(height: 16),
            ShadButton(
              onPressed: isSubmitting ? null : onSubmitPump,
              child: Text(isSubmitting ? 'Submitting...' : 'Submit pump number'),
            ),
            const SizedBox(height: 12),
            ShadButton.outline(
              onPressed: onNewOrder,
              child: const Text('Start new order'),
            ),
          ],
        ),
      ),
    );
  }
}
