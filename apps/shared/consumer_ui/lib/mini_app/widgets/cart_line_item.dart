import 'package:consumer_core/consumer_core.dart';
import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../mini_app_scope.dart';
import 'menu_item_image.dart';

class CartLineItem extends StatelessWidget {
  const CartLineItem({
    super.key,
    required this.item,
    required this.onQuantityChange,
    required this.formatPrice,
  });

  final CartItem item;
  final void Function(CartItem item, int delta) onQuantityChange;
  final String Function(int) formatPrice;

  @override
  Widget build(BuildContext context) {
    final textTheme = ShadTheme.of(context).textTheme;
    final haptics = MiniAppScope.of(context).haptics;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        MenuItemImage(url: item.item.imageUrl, size: 44),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(child: Text(item.item.name, style: textTheme.small)),
                  Text(formatPrice(item.lineTotalCents), style: textTheme.small),
                ],
              ),
              if (item.selections.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    item.selections.map((sel) => sel.name).join(', '),
                    style: textTheme.muted,
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              onPressed: () {
                haptics.selection();
                onQuantityChange(item, -1);
              },
              icon: const Icon(Icons.remove),
            ),
            SizedBox(
              width: 24,
              child: Text(
                '${item.quantity}',
                textAlign: TextAlign.center,
              ),
            ),
            IconButton(
              onPressed: () {
                haptics.selection();
                onQuantityChange(item, 1);
              },
              icon: const Icon(Icons.add),
            ),
          ],
        ),
      ],
    );
  }
}
