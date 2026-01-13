import 'package:flutter/material.dart';

import 'package:consumer_core/consumer_core.dart';

class AccountLinkChips extends StatelessWidget {
  const AccountLinkChips({
    super.key,
    required this.identities,
    required this.linking,
    required this.onUnlink,
  });

  final List<CustomerProfileIdentity> identities;
  final bool linking;
  final ValueChanged<CustomerProfileIdentity> onUnlink;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: identities
          .map((identity) => InputChip(
                label: Text(_labelFor(identity.channel)),
                onDeleted: linking ? null : () => onUnlink(identity),
              ))
          .toList(),
    );
  }

  String _labelFor(String channel) {
    switch (channel.toLowerCase()) {
      case 'discord':
        return 'Discord';
      case 'snapchat':
        return 'Snapchat';
      default:
        return 'Telegram';
    }
  }
}