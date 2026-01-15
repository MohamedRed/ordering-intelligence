part of 'mini_app_screen.dart';

mixin MiniAppStateStoreSearchChat
    on
        State<MiniAppScreen>,
        MiniAppStateFields,
        MiniAppStateSearch,
        MiniAppStateStore,
        MiniAppStateChatState,
        MiniAppStateHomeChat {
  void _enterStoreSearchMode({bool startGroupOrder = false}) {
    setState(() {
      _storeSearchMode = true;
      _storeSearchSeeded = false;
      _pendingStartGroupOrder = startGroupOrder;
      _needsHomePrompt = false;
      _searchResults = [];
      _searchError = null;
      _searching = false;
      _searchController.clear();
    });
    _seedStoreSearchChat();
  }

  void _seedStoreSearchChat() {
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
    final hint = results.length > visible.length
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

  void _selectStoreFromSearchSuggestion(StoreChoice store) {
    _selectStore(store);
  }

  void _handleStoreSearchOptionSelected(
    ChatMessage message,
    ChatOption option,
  ) {
    final toolName = option.toolName?.trim().toLowerCase() ?? '';
    if (toolName == 'start_single_order') {
      _enterStoreSearchMode(startGroupOrder: false);
      return;
    }
    if (toolName == 'start_group_order') {
      _enterStoreSearchMode(startGroupOrder: true);
      return;
    }
    if (toolName == 'select_recent_order') {
      if (_selectRecommendedFromPayload(option.payload)) {
        return;
      }
    }
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
