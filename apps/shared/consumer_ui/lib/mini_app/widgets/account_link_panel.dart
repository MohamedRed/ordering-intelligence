import 'package:flutter/material.dart';

import 'account_link_chips.dart';
import 'package:consumer_core/consumer_core.dart';
class AccountLinkPanel extends StatelessWidget {
  const AccountLinkPanel({
    super.key,
    required this.profile,
    required this.loading,
    required this.error,
    required this.onRetry,
    required this.onLink,
    required this.onUnlink,
    required this.linking,
  });
  final CustomerProfile? profile;
  final bool loading;
  final String? error;
  final VoidCallback onRetry;
  final VoidCallback onLink;
  final ValueChanged<CustomerProfileIdentity> onUnlink;
  final bool linking;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.dividerColor.withValues(alpha: 0.2)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text('Linked accounts',
                    style:
                        TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
              ),
              TextButton.icon(
                onPressed: linking ? null : onLink,
                icon: const Icon(Icons.add_link, size: 18),
                label: const Text('Link'),
              ),
            ],
          ),
          if (loading)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: LinearProgressIndicator(minHeight: 2),
            )
          else if (error != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Unable to load linked accounts.',
                      style: TextStyle(fontSize: 13),
                    ),
                  ),
                  TextButton(
                    onPressed: onRetry,
                    child: const Text('Retry'),
                  ),
                ],
              ),
            )
          else if (profile == null || profile!.linkedChannels.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text(
                'Link another app to sync your order history.',
                style: TextStyle(fontSize: 13),
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: AccountLinkChips(
                identities: profile!.linkedChannels,
                linking: linking,
                onUnlink: onUnlink,
              ),
            ),
        ],
      ),
    );
  }
}
