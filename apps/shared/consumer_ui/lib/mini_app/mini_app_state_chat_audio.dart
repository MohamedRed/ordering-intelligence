part of 'mini_app_screen.dart';

mixin MiniAppStateChatAudio on MiniAppStateChatState, MiniAppStateChatActions {
  Future<void> _toggleRecording() async {
    final recorder = _audioRecorder;
    if (recorder == null) {
      _appendAssistantMessage('Voice notes are not supported on this device.');
      return;
    }
    if (_chatRecording) {
      try {
        final bytes = await recorder.stop();
        if (bytes.isNotEmpty) {
          await _sendChatAudio(bytes);
        }
      } catch (_) {
        _appendAssistantMessage('Unable to capture that recording.');
      }
      if (mounted) setState(() => _chatRecording = false);
      return;
    }
    try {
      await recorder.start();
      if (mounted) setState(() => _chatRecording = true);
    } catch (_) {
      _appendAssistantMessage('Microphone permission was denied.');
    }
  }

  Future<void> _sendChatAudio(Uint8List bytes) async {
    final session = _session;
    if (session == null) return;
    setState(() {
      _chatBusy = true;
      _chatMessages.add(ChatMessage(
        id: _chatId(),
        role: ChatRole.user,
        audioBytes: bytes,
        audioMime: _audioRecorder?.mimeType,
      ));
    });
    _scrollChatToBottom();
    try {
      final response = await _api.sendChatTurn(
        sessionId: session.sessionId,
        audioBytes: bytes,
        audioMime: _audioRecorder?.mimeType,
      );
      _applyChatResponse(response);
    } catch (_) {
      _appendAssistantMessage('Voice message received. Please type for now.');
    } finally {
      if (mounted) setState(() => _chatBusy = false);
    }
  }
}
