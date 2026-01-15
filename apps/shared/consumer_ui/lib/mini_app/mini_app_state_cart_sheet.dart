part of 'mini_app_screen.dart';

mixin MiniAppStateCartSheet
    on
        State<MiniAppScreen>,
        MiniAppStateFields,
        MiniAppStateOrder,
        MiniAppStateGroupOrdersItems,
        MiniAppStateCart,
        MiniAppStateDelivery,
        MiniAppStatePayments {
  void _openCartSheet() {
    setState(() => _orderError = null);
    final isGroupOrder = _groupOrder != null;
    final groupOrderOpen = _groupOrder?.status == 'open';
    final actionLabel = isGroupOrder ? 'Add to group order' : 'Place order';
    final actionHandler = isGroupOrder
        ? (groupOrderOpen ? _submitGroupOrderItems : null)
        : _placeOrder;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            _cartSheetSetState = (callback) {
              if (!context.mounted) return;
              setModalState(callback);
            };
            return SafeArea(
              child: CartSheet(
                cart: _cart,
                notesController: _notesController,
                totalCents: _cartTotalCents,
                placingOrder: _placingOrder,
                orderError: _orderError,
                onQuantityChange: _updateCartQuantity,
                onPlaceOrder: actionHandler,
                actionLabel: actionLabel,
                formatPrice: _formatPrice,
                showPaymentMethod: !isGroupOrder,
                paymentMethod: _orderPaymentMethod,
                onPaymentMethodChanged: (method) {
                  setState(() => _orderPaymentMethod = method);
                  _cartSheetSetState?.call(() {});
                },
                paymentMethodsSection: _buildPaymentMethodsPanel(),
                deliverySection: isGroupOrder ? null : _buildDeliverySection(),
              ),
            );
          },
        );
      },
    ).whenComplete(() => _cartSheetSetState = null);
  }
}
