import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import 'toggle_option_row.dart';

class DeliveryOptionsSection extends StatelessWidget {
  const DeliveryOptionsSection({
    super.key,
    required this.enabled,
    required this.isDelivery,
    required this.onToggle,
    required this.addressController,
    required this.instructionsController,
    required this.onAddressChanged,
    this.etaMinutes,
    this.prewarming = false,
    this.error,
    this.fleetModeLabel,
  });

  final bool enabled;
  final bool isDelivery;
  final ValueChanged<bool> onToggle;
  final TextEditingController addressController;
  final TextEditingController instructionsController;
  final ValueChanged<String> onAddressChanged;
  final int? etaMinutes;
  final bool prewarming;
  final String? error;
  final String? fleetModeLabel;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    if (!enabled) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: theme.colorScheme.muted,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                'Pickup only',
                style: theme.textTheme.small?.copyWith(
                  color: theme.colorScheme.mutedForeground,
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ToggleOptionRow(
          title: 'Delivery',
          value: isDelivery,
          offLabel: 'Pickup',
          onLabel: fleetModeLabel ?? 'Delivery',
          onChanged: onToggle,
        ),
        if (isDelivery) ...[
          const SizedBox(height: 10),
          TextField(
            controller: addressController,
            decoration: const InputDecoration(
              hintText: 'Delivery address',
              border: OutlineInputBorder(),
            ),
            minLines: 1,
            maxLines: 2,
            onChanged: onAddressChanged,
          ),
          const SizedBox(height: 8),
          TextField(
            controller: instructionsController,
            decoration: const InputDecoration(
              hintText: 'Delivery instructions (optional)',
              border: OutlineInputBorder(),
            ),
            minLines: 1,
            maxLines: 2,
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              if (prewarming)
                const SizedBox(
                  height: 16,
                  width: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              if (prewarming) const SizedBox(width: 8),
              if (etaMinutes != null && etaMinutes! > 0)
                Text(
                  'Estimated arrival: ~${etaMinutes!} min',
                  style: theme.textTheme.small,
                ),
              if ((etaMinutes == null || etaMinutes! <= 0) && !prewarming)
                Text(
                  'We will estimate arrival after we find couriers.',
                  style: theme.textTheme.muted,
                ),
            ],
          ),
          if (error != null && error!.isNotEmpty) ...[
            const SizedBox(height: 8),
            ShadAlert.destructive(
              title: const Text('Delivery check failed'),
              description: Text(error!),
            ),
          ],
        ],
      ],
    );
  }
}
