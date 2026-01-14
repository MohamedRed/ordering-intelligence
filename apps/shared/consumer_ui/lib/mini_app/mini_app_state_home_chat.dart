part of 'mini_app_screen.dart';

mixin MiniAppStateHomeChat
    on
        State<MiniAppScreen>,
        MiniAppStateFields,
        MiniAppStateSearch,
        MiniAppStateChatState {
  void _seedHomeChatIfNeeded() {
    if (_storeSearchSeeded || !_recommendedOrdersLoaded) {
      return;
    }
    final session = _session;
    if (session == null || session.storeId.isNotEmpty || _storeSearchMode) {
      return;
    }
    if (_chatMessages.isNotEmpty) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _storeSearchSeeded) return;
      final current = _session;
      if (current == null || current.storeId.isNotEmpty || _storeSearchMode) {
        return;
      }
      if (_chatMessages.isNotEmpty) return;
      final singleOrders = _singleRecentOrders();
      final groupOrders = _groupRecentOrders();
      final hasRecent = singleOrders.isNotEmpty || groupOrders.isNotEmpty;
      setState(() {
        _storeSearchSeeded = true;
        _chatMessages.add(
          ChatMessage(
            id: _chatId(),
            role: ChatRole.assistant,
            text: hasRecent
                ? 'Pick a recent order or start a new one.'
                : 'No recent orders yet. Start a new one below.',
            options: _buildHomeStartOptions(),
          ),
        );
        if (singleOrders.isNotEmpty) {
          _chatMessages.add(
            ChatMessage(
              id: _chatId(),
              role: ChatRole.assistant,
              text: 'Recent single orders',
              options: _buildRecentOrderOptions(
                singleOrders,
                payloadPrefix: 'recent_single',
              ),
            ),
          );
        }
        if (groupOrders.isNotEmpty) {
          _chatMessages.add(
            ChatMessage(
              id: _chatId(),
              role: ChatRole.assistant,
              text: 'Recent group orders',
              options: _buildRecentOrderOptions(
                groupOrders,
                payloadPrefix: 'recent_group',
              ),
            ),
          );
        }
      });
      _scrollChatToBottom();
    });
  }

  bool _selectRecommendedFromPayload(String? payload) {
    final normalized = payload?.trim();
    if (normalized == null || normalized.isEmpty) return false;
    final parts = normalized.split(':');
    if (parts.length != 2) return false;
    final index = int.tryParse(parts[1]);
    if (index == null) return false;
    final list = parts[0] == 'recent_group'
        ? _groupRecentOrders()
        : parts[0] == 'recent_single'
        ? _singleRecentOrders()
        : const <RecommendedOrder>[];
    if (index < 0 || index >= list.length) return false;
    _selectRecommendedOrder(list[index]);
    return true;
  }

  List<ChatOption> _buildHomeStartOptions() {
    return const [
      ChatOption(label: 'New single order', toolName: 'start_single_order'),
      ChatOption(label: 'New group order', toolName: 'start_group_order'),
    ];
  }

  List<ChatOption> _buildRecentOrderOptions(
    List<RecommendedOrder> orders, {
    required String payloadPrefix,
  }) {
    final visible = orders.take(6).toList();
    return List.generate(visible.length, (index) {
      final order = visible[index];
      return ChatOption(
        label: _recentOrderLabel(order),
        payload: '$payloadPrefix:$index',
        toolName: 'select_recent_order',
      );
    });
  }

  List<RecommendedOrder> _singleRecentOrders() {
    return _recommendedOrders.where((order) => !order.isGroupOrder).toList();
  }

  List<RecommendedOrder> _groupRecentOrders() {
    return _recommendedOrders.where((order) => order.isGroupOrder).toList();
  }

  String _recentOrderLabel(RecommendedOrder order) {
    final storeName = order.storeName.trim();
    final title = order.title.trim();
    if (storeName.isEmpty && title.isEmpty) {
      return 'Recent order';
    }
    if (title.isEmpty || title.toLowerCase() == storeName.toLowerCase()) {
      return storeName.isEmpty ? title : storeName;
    }
    if (storeName.isEmpty) return title;
    return '$storeName · $title';
  }
}
