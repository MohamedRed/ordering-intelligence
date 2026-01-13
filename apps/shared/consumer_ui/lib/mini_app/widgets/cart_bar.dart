import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../mini_app_scope.dart';

class CartBar extends StatelessWidget {
  const CartBar({
    super.key,
    required this.itemCount,
    required this.totalLabel,
    required this.onTap,
  });

  final int itemCount;
  final String totalLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final haptics = MiniAppScope.of(context).haptics;
    return GestureDetector(
      onTap: () {
        haptics.impact(style: 'light');
        onTap();
      },
      child: ShadCard(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: Row(
          children: [
            const Icon(Icons.shopping_cart),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '$itemCount item${itemCount == 1 ? '' : 's'} • $totalLabel',
                style: ShadTheme.of(context).textTheme.large,
              ),
            ),
            const Icon(Icons.chevron_right),
          ],
        ),
      ),
    );
  }
}
