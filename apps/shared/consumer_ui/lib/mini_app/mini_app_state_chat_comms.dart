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

  Future<void> _sendChatToolResult(
    ChatMessage message,
    List<ChatOption> selections,
  ) async {
    final session = _session;
    if (session == null) return;
    final toolCallId = message.toolCallId;
    if (toolCallId == null || toolCallId.trim().isEmpty) return;
    if (selections.isEmpty) return;
    if (!mounted) return;
    final selectionLabels = selections.map((option) => option.label).toList();
    final selectionPayloads = selections
        .map((option) => option.payload ?? option.label)
        .toList();
    setState(() {
      _chatBusy = true;
      _chatMessages.add(
        ChatMessage(
          id: _chatId(),
          role: ChatRole.user,
          text: selectionLabels.join(', '),
        ),
      );
    });
    _scrollChatToBottom();
    final result = <String, dynamic>{
      'selectionMode':
          message.selectionMode ?? (selections.length > 1 ? 'multi' : 'single'),
      'selections': selections
          .map(
            (option) => {
              'label': option.label,
              if (option.payload != null) 'payload': option.payload,
              if (option.toolName != null) 'toolName': option.toolName,
            },
          )
          .toList(),
      'selectedLabels': selectionLabels,
      'selectedPayloads': selectionPayloads,
    };
    if (selections.length == 1) {
      result['selection'] = result['selections'][0];
    }
    try {
      final response = await _api.sendChatTurn(
        sessionId: session.sessionId,
        toolResult: ChatToolResult(
          toolCallId: toolCallId,
          name: message.toolName ?? '',
          result: result,
        ),
      );
      _applyChatResponse(response);
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
      if (name == 'present_choices' || name == 'present_choice') {
        _appendToolChoiceMessage(tool);
        continue;
      }
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

  void _appendToolChoiceMessage(ChatToolCall tool) {
    final args = tool.arguments;
    final message =
        _toolString(args['message']) ??
        _toolString(args['prompt']) ??
        'Choose an option below.';
    final options = _decodeToolOptions(args['choices'] ?? args['options']);
    if (options.isEmpty) return;
    final selectionMode =
        _toolString(args['selectionMode']) ??
        _toolString(args['selection_mode']);
    final minSelections = _toolInt(
      args['minSelections'] ?? args['min_selections'],
    );
    final maxSelections = _toolInt(
      args['maxSelections'] ?? args['max_selections'],
    );
    final confirmLabel =
        _toolString(args['confirmLabel']) ?? _toolString(args['confirm_label']);
    final resolvedSelectionMode =
        selectionMode ??
        ((maxSelections != null && maxSelections > 1) ||
                (minSelections != null && minSelections > 1)
            ? 'multi'
            : 'single');
    setState(() {
      _chatMessages.add(
        ChatMessage(
          id: _chatId(),
          role: ChatRole.assistant,
          text: message,
          options: options,
          toolCallId: tool.id,
          toolName: tool.name,
          selectionMode: resolvedSelectionMode,
          minSelections: minSelections,
          maxSelections: maxSelections,
          confirmLabel: confirmLabel,
        ),
      );
    });
    _scrollChatToBottom();
  }

  List<ChatOption> _decodeToolOptions(dynamic raw) {
    if (raw is! List) return const [];
    final options = <ChatOption>[];
    for (final entry in raw) {
      if (entry is Map) {
        final label =
            (entry['label'] ?? entry['text'] ?? entry['title'])?.toString() ??
            '';
        if (label.trim().isEmpty) continue;
        options.add(
          ChatOption(
            label: label,
            payload: entry['payload']?.toString(),
            toolName:
                entry['toolName']?.toString() ?? entry['tool_name']?.toString(),
          ),
        );
      } else if (entry is String) {
        if (entry.trim().isEmpty) continue;
        options.add(ChatOption(label: entry));
      }
    }
    return options;
  }

  String? _toolString(dynamic value) {
    if (value == null) return null;
    final text = value.toString().trim();
    return text.isEmpty ? null : text;
  }

  int? _toolInt(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value.toString());
  }
}
