import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import 'store_picker_results.dart';
import 'package:consumer_core/consumer_core.dart';

class StorePickerView extends StatelessWidget {
  const StorePickerView({
    super.key,
    required this.recommendedOrders,
    required this.onSelectRecommended,
    required this.onSearchChat,
    this.signOutLabel,
    this.onSignOut,
    this.signingOut = false,
  });

  final List<RecommendedOrder> recommendedOrders;
  final ValueChanged<RecommendedOrder> onSelectRecommended;
  final VoidCallback onSearchChat;
  final String? signOutLabel;
  final VoidCallback? onSignOut;
  final bool signingOut;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Find a store',
                  style: ShadTheme.of(context).textTheme.h2,
                ),
              ),
              if (onSignOut != null && signOutLabel != null)
                ShadButton.outline(
                  size: ShadButtonSize.sm,
                  onPressed: signingOut ? null : onSignOut,
                  child: signingOut
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(signOutLabel!),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Pick a recent order or search in chat.',
            style: ShadTheme.of(context).textTheme.muted,
          ),
          const SizedBox(height: 12),
          ShadButton.outline(
            size: ShadButtonSize.sm,
            onPressed: onSearchChat,
            child: const Text('Search for a store in chat'),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: StorePickerResults(
              recommendedOrders: recommendedOrders,
              onSelectRecommended: onSelectRecommended,
            ),
          ),
        ],
      ),
    );
  }
}
