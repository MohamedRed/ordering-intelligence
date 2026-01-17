import 'package:flutter/material.dart';

import '../../models/delivery_partner_stripe_status.dart';

class MarketplaceStripeCard extends StatelessWidget {
  const MarketplaceStripeCard({
    super.key,
    required this.status,
    required this.busy,
    required this.onStart,
    required this.onRefresh,
  });

  final DeliveryPartnerStripeStatus? status;
  final bool busy;
  final VoidCallback onStart;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    final ready = status != null && status!.payoutsEnabled && status!.detailsSubmitted;
    final missingCount = status == null
        ? 0
        : status!.currentlyDue.length + status!.pendingVerification.length + status!.pastDue.length;
    final title = ready ? 'Payouts enabled' : 'Complete payout setup';
    final subtitle = status == null
        ? 'Connect a Stripe Express account to receive payouts.'
        : ready
            ? 'You can receive payouts for completed deliveries.'
            : 'Stripe needs more details to enable payouts.';
    final statusLine = status == null
        ? 'Status: not started'
        : 'Status: ${status!.status.isEmpty ? 'pending' : status!.status}';
    final actionLabel = ready ? 'Update details' : 'Start setup';

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 6),
            Text(subtitle),
            const SizedBox(height: 6),
            Text(statusLine),
            if (missingCount > 0) Text('Requirements due: $missingCount'),
            const SizedBox(height: 12),
            Row(
              children: [
                ElevatedButton(
                  onPressed: busy ? null : onStart,
                  child: Text(actionLabel),
                ),
                const SizedBox(width: 12),
                TextButton(
                  onPressed: busy ? null : onRefresh,
                  child: const Text('Refresh status'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
