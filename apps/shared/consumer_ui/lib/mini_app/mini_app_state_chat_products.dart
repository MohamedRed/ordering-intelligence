part of 'mini_app_screen.dart';

mixin MiniAppStateChatProducts
    on
        State<MiniAppScreen>,
        MiniAppStateFields,
        MiniAppStateCart,
        MiniAppStateMenu,
        MiniAppStateChatState {
  List<ChatProduct> _buildChatProducts(String category) {
    final menu = _menu;
    if (menu == null) return const [];
    final normalized = category.trim();
    var items = menu.items.where((item) => item.available).toList();
    if (normalized.isNotEmpty && normalized != 'All') {
      items = items.where((item) => item.category == normalized).toList();
    }
    final visible = items.take(12);
    return visible
        .map((item) => ChatProduct(
              id: item.id,
              name: item.name,
              description: item.description,
              priceLabel: item.priceCents > 0 ? _formatPrice(item.priceCents) : '',
              imageUrl: item.imageUrl,
            ))
        .toList();
  }

  MenuItem? _resolveMenuItem(MenuSnapshot menu, ChatProduct product) {
    if (product.id.isNotEmpty) {
      for (final item in menu.items) {
        if (item.id == product.id) {
          return item;
        }
      }
    }
    for (final item in menu.items) {
      if (item.name.toLowerCase() == product.name.toLowerCase()) {
        return item;
      }
    }
    return null;
  }

  Future<bool> _addMenuItemFromChat(MenuItem item) async {
    if (item.modifierGroups.isEmpty) {
      _addToCart(item, const []);
      return true;
    }
    _appendAssistantMessage('Customize ${item.name} to continue.');
    final selections = await showDialog<List<ModifierSelection>>(
      context: context,
      builder: (_) => ModifierDialog(item: item),
    );
    if (!mounted || selections == null) {
      return false;
    }
    _addToCart(item, selections);
    return true;
  }
}
