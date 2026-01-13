import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import 'cart_items_section.dart';
import 'payment_method_toggle.dart';
import 'package:consumer_core/consumer_core.dart';

class CartSheetContent extends StatelessWidget {
  const CartSheetContent({
    super.key,
    required this.cart,
    required this.notesController,
    required this.totalCents,
    required this.placingOrder,
    required this.orderError,
    required this.onQuantityChange,
    required this.onPlaceOrder,
    required this.actionLabel,
    required this.formatPrice,
    required this.showPaymentMethod,
    required this.paymentMethod,
    required this.onPaymentMethodChanged,
    this.paymentMethodsSection,
    this.deliverySection,
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
  final Widget? deliverySection;

  @override
  Widget build(BuildContext context) {
    final textTheme = ShadTheme.of(context).textTheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('Your order', style: textTheme.large),
        const SizedBox(height: 12),
        CartItemsSection(
          cart: cart,
          onQuantityChange: onQuantityChange,
          formatPrice: formatPrice,
        ),
        if (deliverySection != null) ...[
          const SizedBox(height: 12),
          deliverySection!,
        ],
        if (showPaymentMethod) ...[
          const SizedBox(height: 12),
          PaymentMethodToggle(
            value: paymentMethod,
            onChanged: onPaymentMethodChanged,
            allowCash: true,
          ),
        ],
        if (paymentMethodsSection != null) ...[
          const SizedBox(height: 12),
          paymentMethodsSection!,
        ],
        const SizedBox(height: 12),
        TextField(
          controller: notesController,
          decoration: const InputDecoration(
            hintText: 'Add a note (optional)',
            border: OutlineInputBorder(),
          ),
          minLines: 1,
          maxLines: 2,
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(child: Text('Total', style: textTheme.large)),
            Text(formatPrice(totalCents), style: textTheme.large),
          ],
        ),
        if (orderError != null) ...[
          const SizedBox(height: 8),
          ShadAlert.destructive(
            title: const Text('Order failed'),
            description: Text(orderError!),
          ),
        ],
        const SizedBox(height: 12),
        ShadButton(
          onPressed: cart.isEmpty || placingOrder ? null : onPlaceOrder,
          child: placingOrder
              ? const SizedBox(
                  height: 16,
                  width: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(actionLabel),
        ),
      ],
    );
  }
}
