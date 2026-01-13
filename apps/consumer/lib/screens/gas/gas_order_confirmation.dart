import 'package:flutter/material.dart';

class GasOrderConfirmation extends StatelessWidget {
  const GasOrderConfirmation({
    super.key,
    required this.order,
    required this.pumpController,
    required this.isSubmitting,
    required this.errorMessage,
    required this.onSubmitPump,
    required this.onNewOrder,
  });

  final Map<String, dynamic> order;
  final TextEditingController pumpController;
  final bool isSubmitting;
  final String? errorMessage;
  final VoidCallback onSubmitPump;
  final VoidCallback onNewOrder;

  @override
  Widget build(BuildContext context) {
    final orderId = (order['id'] ?? '').toString();
    final fuel = order['fuel'] as Map? ?? const {};
    final grade = (fuel['fuelGradeName'] ?? fuel['fuelGradeId'] ?? '').toString();
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.local_gas_station, size: 48, color: Colors.green),
          const SizedBox(height: 12),
          Text('Fuel order placed', style: Theme.of(context).textTheme.titleLarge),
          if (orderId.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text('Order #$orderId'),
          ],
          if (grade.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text('Fuel grade: $grade'),
          ],
          const SizedBox(height: 16),
          TextField(
            controller: pumpController,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Pump number (on arrival)',
            ),
          ),
          if (errorMessage != null && errorMessage!.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(errorMessage!, style: const TextStyle(color: Colors.redAccent)),
          ],
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: isSubmitting ? null : onSubmitPump,
              child: Text(isSubmitting ? 'Submitting...' : 'Submit pump number'),
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: onNewOrder,
              child: const Text('Start new order'),
            ),
          ),
        ],
      ),
    );
  }
}
