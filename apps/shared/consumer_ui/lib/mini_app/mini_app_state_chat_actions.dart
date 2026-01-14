part of 'mini_app_screen.dart';

mixin MiniAppStateChatActions
    on
        MiniAppStateChatState,
        MiniAppStateFields,
        MiniAppStateMenu,
        MiniAppStateCart,
        MiniAppStateDelivery,
        MiniAppStateChatProductLookup,
        MiniAppStateChatSelection,
        MiniAppStateChatComms {
  void _handleOptionSelected(ChatOption option) {
    final toolName = option.toolName?.trim().toLowerCase() ?? '';
    final payload = option.payload?.trim();
    if (_tryHandleLocalOption(option, toolName, payload)) {
      return;
    }
    if (payload != null && payload.isNotEmpty) {
      _sendChatText(payload);
      return;
    }
    _sendChatText(option.label);
  }

  bool _tryHandleLocalOption(ChatOption option, String toolName, String? payload) {
    final label = option.label.trim();
    final labelLower = label.toLowerCase();
    if (toolName == 'switch_to_browse') {
      _appendAssistantMessage('Browse is now in chat. Pick a category above.');
      return true;
    }
    if (_deliveryEnabled) {
      if (toolName == 'delivery' || labelLower == 'delivery') {
        _toggleDelivery(true);
        _appendUserMessage('Delivery');
        return true;
      }
      if (toolName == 'pickup' || labelLower == 'pickup') {
        _toggleDelivery(false);
        _appendUserMessage('Pickup');
        return true;
      }
    }
    if (toolName == 'select_category' || toolName == 'category') {
      _handleCategorySelected(label, fromOption: true);
      return true;
    }
    if (toolName == 'select_product' || toolName == 'product') {
      final product = _resolveChatProduct(option, payload);
      if (product != null) {
        _handleProductSelected(product);
        return true;
      }
    }
    if (_categories.isNotEmpty) {
      final normalized = _normalizeCategory(option.label);
      if (normalized != null) {
        _handleCategorySelected(normalized, fromOption: true);
        return true;
      }
    }
    final fallbackProduct = _resolveChatProduct(option, payload);
    if (fallbackProduct != null) {
      _handleProductSelected(fallbackProduct);
      return true;
    }
    return false;
  }

}
