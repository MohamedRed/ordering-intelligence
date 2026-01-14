import 'package:flutter/material.dart';

import 'chat_context_chip.dart';

class ChatFulfillmentRow extends StatelessWidget {
  const ChatFulfillmentRow({
    super.key,
    required this.isDelivery,
    required this.onChanged,
  });

  final bool isDelivery;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        ChatContextChip(
          label: 'Pickup',
          active: !isDelivery,
          onTap: () {
            onChanged(false);
          },
        ),
        const SizedBox(width: 8),
        ChatContextChip(
          label: 'Delivery',
          active: isDelivery,
          onTap: () {
            onChanged(true);
          },
        ),
      ],
    );
  }
}
