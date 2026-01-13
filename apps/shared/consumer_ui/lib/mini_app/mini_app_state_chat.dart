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
  MiniAppSegment _activeSegment = MiniAppSegment.chat;
  bool _chatBusy = false;
  bool _chatRecording = false;
  AudioRecorder? _audioRecorder;

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

  void _setActiveSegment(MiniAppSegment segment) {
    if (segment == _activeSegment) return;
    setState(() => _activeSegment = segment);
  }

  void _maybeSeedChat() {
    if (_chatMessages.isNotEmpty) return;
    final storeName = _session?.storeName ?? 'this store';
    _chatMessages.add(ChatMessage(
      id: _chatId(),
      role: ChatRole.assistant,
      text: 'Hi! Ask me anything about $storeName or what you want to order.',
    ));
  }

  String _chatId() => DateTime.now().microsecondsSinceEpoch.toString();
}
