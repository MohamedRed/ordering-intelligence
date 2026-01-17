part of 'mini_app_screen.dart';

mixin MiniAppStateMenu
    on State<MiniAppScreen>, MiniAppStateFields, MiniAppStateDrafts {
  Future<void> _loadMenu(String storeId) async {
    setState(() {
      _loadingMenu = true;
      _menuError = null;
    });
    try {
      final menu = await _api.fetchMenu(storeId);
      if (!mounted) {
        return;
      }
      final categories = menu.items
          .map((item) => item.category.trim())
          .where((category) => category.isNotEmpty)
          .toSet()
          .toList()
        ..sort();
      if (categories.isNotEmpty) {
        categories.insert(0, 'All');
      }
      final active = categories.isNotEmpty ? categories.first : '';
      setState(() {
        _menu = menu;
        _categories = categories;
        _activeCategory = active;
        _loadingMenu = false;
      });
      await _loadDraftIfAvailable();
    } catch (e) {
      if (!mounted) {
        return;
      }
      setState(() {
        _menuError = e.toString();
        _loadingMenu = false;
      });
    }
  }
}
