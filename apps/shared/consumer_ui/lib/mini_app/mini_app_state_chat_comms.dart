part of 'mini_app_screen.dart';

mixin MiniAppStateChatComms
    on
        MiniAppStateChatState,
        MiniAppStateFields,
        MiniAppStateChatProductLookup,
        MiniAppStateChatSelection {
  Future<void> _sendChatText([String? value]) async {
    final session = _session;
    if (session == null) return;
    final text = (value ?? _chatController.text).trim();
    if (text.isEmpty) return;
    setState(() {
      _chatBusy = true;
      _chatMessages.add(
        ChatMessage(id: _chatId(), role: ChatRole.user, text: text),
      );
      _chatController.clear();
    });
    _scrollChatToBottom();
    try {
      final sendSeededContext =
          !_seededContextSent &&
          ((_seededIntro?.trim().isNotEmpty ?? false) ||
              _seededCategories.isNotEmpty);
      final response = await _api.sendChatTurn(
        sessionId: session.sessionId,
        text: text,
        seededIntro: sendSeededContext ? _seededIntro : null,
        seededCategories: sendSeededContext ? _seededCategories : null,
        seededSource: sendSeededContext ? _seededSource : null,
      );
      _applyChatResponse(response);
      if (sendSeededContext) {
        _seededContextSent = true;
      }
    } catch (_) {
      _appendAssistantMessage(
        'Sorry, I had trouble responding. Please try again.',
      );
    } finally {
      if (mounted) setState(() => _chatBusy = false);
    }
  }

  void _applyChatResponse(ChatResponse response) {
    if (response.messages.isNotEmpty) {
      setState(() => _chatMessages.addAll(response.messages));
    }
    _handleToolCalls(response.toolCalls);
    _scrollChatToBottom();
  }

  void _handleToolCalls(List<ChatToolCall> toolCalls) {
    if (toolCalls.isEmpty) return;
    for (final tool in toolCalls) {
      final name = tool.name.trim().toLowerCase();
      if (name == 'select_category' || name == 'category') {
        final category =
            tool.arguments['category']?.toString() ??
            tool.arguments['name']?.toString();
        if (category != null && category.trim().isNotEmpty) {
          _handleCategorySelected(category.trim(), fromOption: true);
        }
      } else if (name == 'select_product' || name == 'product') {
        final value =
            tool.arguments['id']?.toString() ??
            tool.arguments['productId']?.toString() ??
            tool.arguments['name']?.toString();
        if (value != null && value.trim().isNotEmpty) {
          final option = ChatOption(label: value, payload: value);
          final product = _resolveChatProduct(option, value.trim());
          if (product != null) {
            _handleProductSelected(product);
          }
        }
      }
    }
  }
}
