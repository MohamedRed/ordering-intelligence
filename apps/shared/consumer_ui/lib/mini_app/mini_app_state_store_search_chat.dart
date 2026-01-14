part of 'mini_app_screen.dart';

mixin MiniAppStateStoreSearchChat
    on
        State<MiniAppScreen>,
        MiniAppStateFields,
        MiniAppStateSearch,
        MiniAppStateStore,
        MiniAppStateChatState {
  void _enterStoreSearchMode() {
    setState(() {
      _storeSearchMode = true;
      _searchResults = [];
      _searchError = null;
      _searching = false;
      _searchController.clear();
      _chatMessages.clear();
    });
    _seedStoreSearchChat();
  }

  void _exitStoreSearchMode() {
    setState(() {
      _storeSearchMode = false;
      _searchResults = [];
      _searchError = null;
      _searching = false;
      _searchController.clear();
      _chatMessages.clear();
    });
  }

  void _seedStoreSearchChat() {
    if (_chatMessages.isNotEmpty) return;
    setState(() {
      _chatMessages.add(
        ChatMessage(
          id: _chatId(),
          role: ChatRole.assistant,
          text: 'Tell me the store name and I will search it for you.',
        ),
      );
    });
    _scrollChatToBottom();
  }

  Future<void> _sendStoreSearchMessage([String? value]) async {
    final query = (value ?? _searchController.text).trim();
    if (query.isEmpty) return;
    setState(() {
      _searching = true;
      _searchError = null;
      _chatMessages.add(
        ChatMessage(id: _chatId(), role: ChatRole.user, text: query),
      );
      _searchController.clear();
    });
    _scrollChatToBottom();
    final results = await _searchStoresFromChat(query);
    if (!mounted) return;
    if (_searchError != null) {
      _appendAssistantMessage('Search failed. Please try again.');
      return;
    }
    if (results.isEmpty) {
      _appendAssistantMessage('No stores found. Try another name.');
      return;
    }
    final visible = results.take(6).toList();
    final hint =
        results.length > visible.length
            ? 'Select a store (showing top ${visible.length}).'
            : 'Select a store from the results.';
    setState(() {
      _chatMessages.add(
        ChatMessage(
          id: _chatId(),
          role: ChatRole.assistant,
          text: hint,
          options: visible
              .map(
                (store) => ChatOption(
                  label: store.name,
                  payload: store.storeId,
                  toolName: 'select_store',
                ),
              )
              .toList(),
        ),
      );
    });
    _scrollChatToBottom();
  }

  void _handleStoreSearchOptionSelected(ChatMessage message, ChatOption option) {
    final payload = option.payload?.trim();
    StoreChoice? store;
    for (final result in _searchResults) {
      final matchesId =
          payload != null && payload.isNotEmpty && result.storeId == payload;
      if (matchesId || result.name == option.label) {
        store = result;
        break;
      }
    }
    if (store == null) {
      _appendAssistantMessage('That store is no longer available. Try again.');
      return;
    }
    _exitStoreSearchMode();
    _selectStore(store);
  }

  void _handleStoreSearchOptionsConfirmed(
    ChatMessage message,
    List<ChatOption> selections,
  ) {
    if (selections.isEmpty) return;
    _handleStoreSearchOptionSelected(message, selections.first);
  }
}
