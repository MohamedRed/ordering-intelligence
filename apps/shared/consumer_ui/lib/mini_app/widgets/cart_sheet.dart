import 'package:flutter/material.dart';

import 'cart_sheet_content.dart';
import 'package:consumer_core/consumer_core.dart';

class CartSheet extends StatelessWidget {
  const CartSheet({
    super.key,
    required this.cart,
    required this.notesController,
    required this.totalCents,
    required this.placingOrder,
    required this.orderError,
    required this.onQuantityChange,
    required this.onPlaceOrder,
    this.actionLabel = 'Place order',
    required this.formatPrice,
    required this.showPaymentMethod,
    required this.paymentMethod,
    required this.onPaymentMethodChanged,
    this.paymentMethodsSection,
  });

  final List<CartItem> cart;
  final TextEditingController notesController;
  final int totalCents;
  final bool placingOrder;
  final String? orderError;
  final void Function(CartItem item, int delta) onQuantityChange;
  final VoidCallback? onPlaceOrder;
  final String actionLabel;
  final String Function(int) formatPrice;
  final bool showPaymentMethod;
  final String paymentMethod;
  final ValueChanged<String> onPaymentMethodChanged;
  final Widget? paymentMethodsSection;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: CartSheetContent(
        cart: cart,
        notesController: notesController,
        totalCents: totalCents,
        placingOrder: placingOrder,
        orderError: orderError,
        onQuantityChange: onQuantityChange,
        onPlaceOrder: onPlaceOrder,
        actionLabel: actionLabel,
        formatPrice: formatPrice,
        showPaymentMethod: showPaymentMethod,
        paymentMethod: paymentMethod,
        onPaymentMethodChanged: onPaymentMethodChanged,
        paymentMethodsSection: paymentMethodsSection,
      ),
    );
  }
}
