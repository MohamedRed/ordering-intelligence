import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import 'cart_line_item.dart';
import 'package:consumer_core/consumer_core.dart';

class CartItemsSection extends StatelessWidget {
  const CartItemsSection({
    super.key,
    required this.cart,
    required this.onQuantityChange,
    required this.formatPrice,
  });

  final List<CartItem> cart;
  final void Function(CartItem item, int delta) onQuantityChange;
  final String Function(int) formatPrice;

  @override
  Widget build(BuildContext context) {
    final textTheme = ShadTheme.of(context).textTheme;
    if (cart.isEmpty) {
      return Text('Your cart is empty.', style: textTheme.muted);
    }
    return SizedBox(
      height: 260,
      child: ListView.separated(
        itemCount: cart.length,
        separatorBuilder: (context, _) => const Divider(),
        itemBuilder: (context, index) {
          final item = cart[index];
          return CartLineItem(
            item: item,
            onQuantityChange: onQuantityChange,
            formatPrice: formatPrice,
          );
        },
      ),
    );
  }
}