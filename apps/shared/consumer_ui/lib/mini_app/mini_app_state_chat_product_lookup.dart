part of 'mini_app_screen.dart';

mixin MiniAppStateChatProductLookup
    on MiniAppStateFields, MiniAppStateMenu, MiniAppStateCart {
  ChatProduct? _resolveChatProduct(ChatOption option, String? payload) {
    final menu = _menu;
    if (menu == null) return null;
    final lookup = payload ?? option.label;
    if (lookup.trim().isEmpty) return null;
    for (final item in menu.items) {
      if (item.id == lookup) {
        return _toChatProduct(item);
      }
    }
    for (final item in menu.items) {
      if (item.name.toLowerCase() == lookup.toLowerCase()) {
        return _toChatProduct(item);
      }
    }
    return null;
  }

  ChatProduct _toChatProduct(MenuItem item) {
    return ChatProduct(
      id: item.id,
      name: item.name,
      description: item.description,
      priceLabel: item.priceCents > 0 ? _formatPrice(item.priceCents) : '',
      imageUrl: item.imageUrl,
    );
  }
}
