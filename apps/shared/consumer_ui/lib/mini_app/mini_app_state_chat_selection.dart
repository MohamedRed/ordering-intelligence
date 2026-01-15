part of 'mini_app_screen.dart';

mixin MiniAppStateChatSelection
    on
        State<MiniAppScreen>,
        MiniAppStateFields,
        MiniAppStateChatProducts,
        MiniAppStateChatState {
  void _handleCategorySelected(String category, {bool fromOption = false}) {
    final normalized = _normalizeCategory(category);
    if (normalized == null) {
      if (!fromOption) {
        _appendAssistantMessage('That category is not available here yet.');
      }
      return;
    }
    setState(() {
      _activeCategory = normalized;
      _selectedProduct = null;
    });
    _appendUserMessage(normalized);
    _appendProductSuggestions(normalized);
    _collapseContextAfterSelection();
  }

  Future<void> _handleProductSelected(ChatProduct product) async {
    final menu = _menu;
    if (menu == null) {
      _appendAssistantMessage('The menu is still loading. Try again soon.');
      return;
    }
    final item = _resolveMenuItem(menu, product);
    if (item == null) {
      _appendAssistantMessage('I could not find that item on the menu.');
      return;
    }
    setState(() {
      _selectedProduct = product;
      if (item.category.isNotEmpty) {
        _activeCategory = item.category;
      }
    });
    _appendUserMessage(item.name);
    final added = await _addMenuItemFromChat(item);
    if (added) {
      setState(() {
        _chatMessages.add(
          ChatMessage(
            id: _chatId(),
            role: ChatRole.assistant,
            text: 'Added ${item.name}. Anything else?',
            options: const [
              ChatOption(label: 'Yes', toolName: 'continue_browsing'),
              ChatOption(label: 'No', toolName: 'open_cart'),
            ],
          ),
        );
      });
      _scrollChatToBottom();
      _collapseContextAfterSelection();
    }
  }

  void _appendProductSuggestions(String category) {
    final products = _buildChatProducts(category);
    if (products.isEmpty) {
      _appendAssistantMessage('No items found for $category.');
      return;
    }
    setState(() {
      _chatMessages.add(
        ChatMessage(
          id: _chatId(),
          role: ChatRole.assistant,
          text: 'Choose a product from $category.',
          products: products,
        ),
      );
    });
    _scrollChatToBottom();
  }

  String? _normalizeCategory(String input) {
    final trimmed = input.trim();
    if (trimmed.isEmpty) return null;
    for (final category in _categories) {
      if (category.toLowerCase() == trimmed.toLowerCase()) {
        return category;
      }
    }
    return null;
  }

  void _appendUserMessage(String text) {
    setState(() {
      _chatMessages.add(
        ChatMessage(id: _chatId(), role: ChatRole.user, text: text),
      );
    });
    _scrollChatToBottom();
  }
}
