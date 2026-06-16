import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

class DeliverySettingsCard extends StatelessWidget {
  const DeliverySettingsCard({
    super.key,
    required this.deliveryEnabled,
    required this.onDeliveryEnabledChanged,
    required this.fleetMode,
    required this.onFleetModeChanged,
    required this.storeAddressController,
    required this.storeLatController,
    required this.storeLngController,
    required this.marketplaceOfferController,
    required this.showMarketplaceOffer,
  });

  final bool deliveryEnabled;
  final ValueChanged<bool> onDeliveryEnabledChanged;
  final String fleetMode;
  final ValueChanged<String?> onFleetModeChanged;
  final TextEditingController storeAddressController;
  final TextEditingController storeLatController;
  final TextEditingController storeLngController;
  final TextEditingController marketplaceOfferController;
  final bool showMarketplaceOffer;

  @override
  Widget build(BuildContext context) {
    return ShadCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Delivery settings',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Enable delivery'),
            value: deliveryEnabled,
            onChanged: onDeliveryEnabledChanged,
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            initialValue: fleetMode,
            decoration: const InputDecoration(
              labelText: 'Fleet mode',
              border: OutlineInputBorder(),
            ),
            items: const [
              DropdownMenuItem(
                  value: 'owned_fleet', child: Text('Owned fleet')),
              DropdownMenuItem(
                  value: 'third_party', child: Text('Third-party')),
              DropdownMenuItem(value: 'hybrid', child: Text('Hybrid')),
              DropdownMenuItem(
                  value: 'marketplace', child: Text('Marketplace couriers')),
            ],
            onChanged: onFleetModeChanged,
          ),
          const SizedBox(height: 10),
          TextFormField(
            controller: storeAddressController,
            decoration: const InputDecoration(
              labelText: 'Store address (optional)',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  controller: storeLatController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Store lat',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextFormField(
                  controller: storeLngController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Store lng',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Dispatch uses Radar routes. Store lat/lng is required for delivery quotes and assignment ETAs.',
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: Colors.grey[600]),
          ),
          if (showMarketplaceOffer) ...[
            const SizedBox(height: 12),
            TextFormField(
              controller: marketplaceOfferController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Marketplace offer (cents)',
                hintText: 'e.g. 300',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'This is the suggested payout for couriers. They choose whether to accept.',
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: Colors.grey[600]),
            ),
          ],
        ],
      ),
    );
  }
}
