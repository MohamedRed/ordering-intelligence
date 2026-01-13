import 'package:flutter/material.dart';

import 'toggle_option_row.dart';

class PaymentMethodToggle extends StatelessWidget {
  const PaymentMethodToggle({
    super.key,
    required this.value,
    required this.onChanged,
    this.allowCash = true,
  });

  final String value;
  final ValueChanged<String> onChanged;
  final bool allowCash;

  @override
  Widget build(BuildContext context) {
    if (!allowCash) {
      return ToggleOptionRow(
        title: 'Payment method',
        value: true,
        onLabel: 'Card',
        offLabel: 'Card',
        onChanged: (_) => onChanged('card'),
      );
    }
    final isCard = value == 'card';
    return ToggleOptionRow(
      title: 'Payment method',
      value: isCard,
      offLabel: 'Cash',
      onLabel: 'Card',
      onChanged: (next) => onChanged(next ? 'card' : 'cash'),
    );
  }
}
