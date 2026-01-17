import 'package:flutter/material.dart';

import '../../models/marketplace_offer.dart';

class MarketplaceOffersList extends StatelessWidget {
  const MarketplaceOffersList({
    super.key,
    required this.offers,
    required this.busy,
    required this.currentUserId,
    required this.onAccept,
    required this.onUpdateStatus,
  });

  final List<MarketplaceOffer> offers;
  final bool busy;
  final String currentUserId;
  final ValueChanged<MarketplaceOffer> onAccept;
  final void Function(MarketplaceOffer offer, String status) onUpdateStatus;

  @override
  Widget build(BuildContext context) {
    if (offers.isEmpty) {
      return const Text('No offers yet.');
    }
    return Column(
      children: offers.map((offer) {
        final assignedToMe = offer.selectedDelivererId.isNotEmpty &&
            offer.selectedDelivererId == currentUserId;
        final expires = offer.expiresAt == null
            ? ''
            : 'Expires ${offer.expiresAt!.toLocal()}';
        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Store ${offer.storeId}',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 4),
                Text('Status: ${offer.status}'),
                if (offer.orderId.isNotEmpty) Text('Order: ${offer.orderId}'),
                Text('Payout: ${offer.payoutCents} ${offer.currency}'),
                if (offer.dropoffAddress.isNotEmpty)
                  Text('Dropoff: ${offer.dropoffAddress}'),
                if (offer.instructions.isNotEmpty)
                  Text('Notes: ${offer.instructions}'),
                if (expires.isNotEmpty) Text(expires),
                const SizedBox(height: 8),
                if (offer.status == 'open')
                  ElevatedButton(
                    onPressed: busy ? null : () => onAccept(offer),
                    child: const Text('Accept offer'),
                  ),
                if (offer.status == 'assigned' && assignedToMe) ...[
                  Wrap(
                    spacing: 8,
                    children: [
                      ElevatedButton(
                        onPressed: busy ? null : () => onUpdateStatus(offer, 'picked_up'),
                        child: const Text('Picked up'),
                      ),
                      ElevatedButton(
                        onPressed: busy ? null : () => onUpdateStatus(offer, 'out_for_delivery'),
                        child: const Text('Out for delivery'),
                      ),
                      ElevatedButton(
                        onPressed: busy ? null : () => onUpdateStatus(offer, 'delivered'),
                        child: const Text('Delivered'),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        );
      }).toList(),
    );
  }
}
