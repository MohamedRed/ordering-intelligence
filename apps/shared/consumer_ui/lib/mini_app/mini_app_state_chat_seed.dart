part of 'mini_app_screen.dart';

mixin MiniAppStateChatSeed
    on
        State<MiniAppScreen>,
        MiniAppStateFields,
        MiniAppStateMenu,
        MiniAppStateChatState {
  void _seedMenuChatIfNeeded() {
    if (_menu == null || (_chatMessages.isNotEmpty && !_needsStoreIntro)) {
      return;
    }
    final storeName = _session?.storeName ?? 'this store';
    final seededCategories = _seededCategoryLabels();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_chatMessages.isNotEmpty && !_needsStoreIntro) return;
      setState(() {
        _chatMessages.add(
          ChatMessage(
            id: _chatId(),
            role: ChatRole.assistant,
            text: 'Let\'s order from $storeName. Pick a category to start.',
            options: _buildCategoryOptions(),
          ),
        );
        _seededIntro =
            'Let\'s order from $storeName. Pick a category to start.';
        _seededCategories = seededCategories;
        _seededSource = 'menu';
        _seededContextSent = false;
        _seededPrewarmSent = false;
        _seededPrewarmInFlight = false;
        _needsStoreIntro = false;
      });
      _prewarmSeededChat();
    });
  }

  List<ChatOption> _buildCategoryOptions() {
    if (_categories.isEmpty) return const [];
    final visible = _categories
        .where((cat) => cat.trim().isNotEmpty)
        .take(8)
        .toList();
    return visible
        .map(
          (category) =>
              ChatOption(label: category, toolName: 'select_category'),
        )
        .toList();
  }

  List<String> _seededCategoryLabels() {
    if (_categories.isEmpty) return const [];
    return _categories
        .where((cat) => cat.trim().isNotEmpty)
        .map((cat) => cat.trim())
        .take(8)
        .toList();
  }

  Future<void> _prewarmSeededChat() async {
    if (_seededPrewarmSent || _seededPrewarmInFlight) return;
    final session = _session;
    if (session == null) return;
    final intro = _seededIntro;
    if (intro == null || intro.trim().isEmpty) return;
    _seededPrewarmInFlight = true;
    try {
      await _api.prewarmChat(
        sessionId: session.sessionId,
        seededIntro: intro,
        seededCategories: _seededCategories,
        seededSource: _seededSource,
      );
      _seededPrewarmSent = true;
    } catch (_) {
      // Best-effort; first message will still include context if needed.
    } finally {
      _seededPrewarmInFlight = false;
    }
  }
}
