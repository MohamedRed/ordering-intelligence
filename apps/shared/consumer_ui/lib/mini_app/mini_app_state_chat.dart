part of 'mini_app_screen.dart';

mixin MiniAppStateChatState
    on
        State<MiniAppScreen>,
        MiniAppStateFields,
        MiniAppStateCart,
        MiniAppStateGroupOrdersView,
        MiniAppStateMenu {
  final TextEditingController _chatController = TextEditingController();
  final ScrollController _chatScrollController = ScrollController();
  final List<ChatMessage> _chatMessages = [];
  bool _chatBusy = false;
  bool _chatRecording = false;
  AudioRecorder? _audioRecorder;
  String? _seededIntro;
  List<String> _seededCategories = [];
  String _seededSource = 'menu';
  bool _seededContextSent = false;
  bool _seededPrewarmSent = false;
  bool _seededPrewarmInFlight = false;

  @override
  void initState() {
    super.initState();
    _audioRecorder = _platform.createAudioRecorder();
  }

  @override
  void dispose() {
    _audioRecorder?.dispose();
    _chatController.dispose();
    _chatScrollController.dispose();
    super.dispose();
  }

  void _maybeSeedChat() {
    if (_chatMessages.isNotEmpty) return;
    final storeName = _session?.storeName ?? 'this store';
    _chatMessages.add(
      ChatMessage(
        id: _chatId(),
        role: ChatRole.assistant,
        text:
            'Hi! Ask me anything about $storeName or pick a quick option below.',
      ),
    );
    _seededIntro =
        'Hi! Ask me anything about $storeName or pick a quick option below.';
    _seededCategories = [];
    _seededSource = 'session';
    _seededContextSent = false;
    _seededPrewarmSent = false;
    _seededPrewarmInFlight = false;
  }

  String _chatId() => DateTime.now().microsecondsSinceEpoch.toString();

  void _appendAssistantMessage(String text) {
    if (!mounted) return;
    setState(() {
      _chatMessages.add(
        ChatMessage(id: _chatId(), role: ChatRole.assistant, text: text),
      );
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
