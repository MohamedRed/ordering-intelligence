import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import 'store_logo.dart';
import 'package:consumer_core/consumer_core.dart';

class StoreChoiceCard extends StatelessWidget {
  const StoreChoiceCard({
    super.key,
    required this.store,
    required this.onTap,
  });

  final StoreChoice store;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final label = _businessTypeLabel(store.businessType, store.storeId);
    return GestureDetector(
      onTap: onTap,
      child: ShadCard(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: SizedBox(
          height: 76,
          child: Row(
            children: [
              StoreLogo(name: store.name, logoUrl: store.logoUrl),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      store.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: ShadTheme.of(context).textTheme.large,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: ShadTheme.of(context).textTheme.muted,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _businessTypeLabel(String businessType, String fallback) {
    final type = businessType.trim().toLowerCase();
    if (type.isEmpty) return fallback;
    switch (type) {
      case 'auto_parts':
        return 'Auto Parts';
      case 'gas_station':
        return 'Gas Station';
      case 'fast_food':
        return 'Fast Food';
      default:
        return businessType;
    }
  }
}