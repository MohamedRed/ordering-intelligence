import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../models/order.dart';

class FuelOrderSummaryCard extends StatelessWidget {
  const FuelOrderSummaryCard({super.key, required this.order});

  final Order order;

  @override
  Widget build(BuildContext context) {
    final fuel = order.fuel;
    if (fuel == null) return const SizedBox.shrink();
    final grade = fuel.fuelGradeName.isNotEmpty
        ? fuel.fuelGradeName
        : fuel.fuelGradeId;
    return ShadCard(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Fuel order', style: Theme.of(context).textTheme.titleMedium),
          if (grade.isNotEmpty) Text('Grade: $grade'),
          Text('Payment: ${fuel.isPreauth ? 'Preauth' : 'Prepay'}'),
          if (fuel.unitPriceCents > 0)
            Text('Unit price: ${_money(order, fuel.unitPriceCents)} / L'),
          if (fuel.requestedLiters > 0)
            Text('Requested: ${_liters(fuel.requestedLiters)} L'),
          if (fuel.requestedAmountCents > 0)
            Text('Requested amount: ${_money(order, fuel.requestedAmountCents)}'),
          if (fuel.preauthAmountCents > 0)
            Text('Authorized: ${_money(order, fuel.preauthAmountCents)}'),
          if (fuel.pumpNumber.isNotEmpty) Text('Pump: ${fuel.pumpNumber}'),
          if (fuel.finalLiters > 0)
            Text('Final liters: ${_liters(fuel.finalLiters)} L'),
          if (fuel.finalAmountCents > 0)
            Text('Final: ${_money(order, fuel.finalAmountCents)}'),
        ],
      ),
    );
  }

  String _money(Order order, int cents) {
    final value = (cents / 100).toStringAsFixed(2);
    return order.isGasOrder ? 'EUR $value' : '\$$value';
  }

  String _liters(double value) => value.toStringAsFixed(2);
}
