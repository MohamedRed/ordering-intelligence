part of 'mini_app_screen.dart';

mixin MiniAppStateChatActions
    on
        MiniAppStateChatState,
        MiniAppStateFields,
        MiniAppStateMenu,
        MiniAppStateCart,
        MiniAppStateCartSheet,
        MiniAppStateDelivery,
        MiniAppStateChatProductLookup,
        MiniAppStateChatSelection,
        MiniAppStateChatSeed,
        MiniAppStateChatComms {
  void _handleOptionSelected(ChatMessage message, ChatOption option) {
    if (_chatBusy) return;
    final toolCallId = message.toolCallId?.trim();
    if (toolCallId != null && toolCallId.isNotEmpty) {
      _sendChatToolResult(message, [option]);
      return;
    }
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

  void _handleMultiOptionsSelected(
    ChatMessage message,
    List<ChatOption> selections,
  ) {
    if (_chatBusy) return;
    final toolCallId = message.toolCallId?.trim();
    if (toolCallId == null || toolCallId.isEmpty) return;
    _sendChatToolResult(message, selections);
  }

  bool _tryHandleLocalOption(
    ChatOption option,
    String toolName,
    String? payload,
  ) {
    final label = option.label.trim();
    final labelLower = label.toLowerCase();
    if (toolName == 'switch_to_browse') {
      _appendAssistantMessage('Browse is now in chat. Pick a category above.');
      return true;
    }
    if (toolName == 'continue_browsing') {
      _appendUserMessage('Yes');
      final options = _buildCategoryOptions();
      if (options.isEmpty) {
        _appendAssistantMessage(
          'Great. Pick another item or ask me a question.',
        );
      } else {
        setState(() {
          _chatMessages.add(
            ChatMessage(
              id: _chatId(),
              role: ChatRole.assistant,
              text: 'Pick a category to continue.',
              options: options,
            ),
          );
        });
        _scrollChatToBottom();
      }
      return true;
    }
    if (toolName == 'open_cart') {
      _appendUserMessage('No');
      if (_cartItemCount > 0) {
        _openCartSheet();
      } else {
        _appendAssistantMessage('Your cart is empty.');
      }
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
