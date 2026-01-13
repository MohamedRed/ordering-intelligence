part of 'mini_app_screen.dart';

mixin MiniAppStateChatActions on MiniAppStateChatState {
  void _handleOptionSelected(ChatOption option) {
    final toolName = option.toolName?.trim() ?? '';
    if (toolName == 'switch_to_browse') {
      _setActiveSegment(MiniAppSegment.browse);
      return;
    }
    final payload = option.payload?.trim();
    if (payload != null && payload.isNotEmpty) {
      _sendChatText(payload);
      return;
    }
    _sendChatText(option.label);
  }

  Future<void> _sendChatText([String? value]) async {
    final session = _session;
    if (session == null) return;
    final text = (value ?? _chatController.text).trim();
    if (text.isEmpty) return;
    setState(() {
      _chatBusy = true;
      _chatMessages.add(ChatMessage(id: _chatId(), role: ChatRole.user, text: text));
      _chatController.clear();
    });
    _scrollChatToBottom();
    try {
      final response =
          await _api.sendChatTurn(sessionId: session.sessionId, text: text);
      _applyChatResponse(response);
    } catch (_) {
      _appendAssistantMessage('Sorry, I had trouble responding. Please try again.');
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
    for (final tool in toolCalls) {
      if (tool.name == 'switch_to_browse') {
        _setActiveSegment(MiniAppSegment.browse);
      }
    }
  }

  void _appendAssistantMessage(String text) {
    if (!mounted) return;
    setState(() {
      _chatMessages.add(ChatMessage(
        id: _chatId(),
        role: ChatRole.assistant,
        text: text,
      ));
    });
    _scrollChatToBottom();
  }

  void _scrollChatToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_chatScrollController.hasClients) return;
      _chatScrollController.animateTo(
        _chatScrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    });
  }
}
