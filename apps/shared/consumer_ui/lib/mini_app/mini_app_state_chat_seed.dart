part of 'mini_app_screen.dart';

mixin MiniAppStateChatSeed
    on State<MiniAppScreen>, MiniAppStateFields, MiniAppStateMenu, MiniAppStateChatState {
  void _seedMenuChatIfNeeded() {
    if (_menu == null || _chatMessages.isNotEmpty) {
      return;
    }
    final storeName = _session?.storeName ?? 'this store';
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _chatMessages.isNotEmpty) return;
      setState(() {
        _chatMessages.add(ChatMessage(
          id: _chatId(),
          role: ChatRole.assistant,
          text: 'Let\'s order from $storeName. Pick a category to start.',
          options: _buildCategoryOptions(),
        ));
      });
    });
  }

  List<ChatOption> _buildCategoryOptions() {
    if (_categories.isEmpty) return const [];
    final visible = _categories.where((cat) => cat.trim().isNotEmpty).take(8).toList();
    return visible
        .map((category) => ChatOption(label: category, toolName: 'select_category'))
        .toList();
  }
}
