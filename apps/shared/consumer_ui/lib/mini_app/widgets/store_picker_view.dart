import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import 'store_picker_results.dart';
import 'package:consumer_core/consumer_core.dart';

class StorePickerView extends StatelessWidget {
  const StorePickerView({
    super.key,
    required this.searchController,
    required this.searching,
    required this.searchError,
    required this.results,
    required this.recommendedOrders,
    required this.onSelect,
    required this.onSelectRecommended,
    this.signOutLabel,
    this.onSignOut,
    this.signingOut = false,
  });

  final TextEditingController searchController;
  final bool searching;
  final String? searchError;
  final List<StoreChoice> results;
  final List<RecommendedOrder> recommendedOrders;
  final ValueChanged<StoreChoice> onSelect;
  final ValueChanged<RecommendedOrder> onSelectRecommended;
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
                  'Choose a restaurant',
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
            'Type the business name to get started.',
            style: ShadTheme.of(context).textTheme.muted,
          ),
          const SizedBox(height: 16),
          TextField(
            controller: searchController,
            decoration: InputDecoration(
              hintText: 'Search restaurants',
              border: const OutlineInputBorder(),
              prefixIcon: const Icon(Icons.search),
              suffixIcon: searching
                  ? const SizedBox(
                      height: 16,
                      width: 16,
                      child: Padding(
                        padding: EdgeInsets.all(12),
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  : null,
            ),
          ),
          if (searchError != null) ...[
            const SizedBox(height: 12),
            ShadAlert.destructive(
              title: const Text('Search failed'),
              description: Text(searchError!),
            ),
          ],
          const SizedBox(height: 16),
          Expanded(
            child: StorePickerResults(
              recommendedOrders: recommendedOrders,
              searchResults: results,
              onSelectStore: onSelect,
              onSelectRecommended: onSelectRecommended,
            ),
          ),
        ],
      ),
    );
  }
}
