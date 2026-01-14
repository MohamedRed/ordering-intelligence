part of 'mini_app_screen.dart';

mixin MiniAppStateChatParticipants
    on MiniAppStateChatState, MiniAppStateFields, MiniAppStateChatComms {
  void _handleParticipantSelected(GroupOrderParticipant participant) {
    final name = _resolveParticipantName(participant);
    setState(() => _groupOrderSelectedParticipantId = participant.participantId);
    if (name.isEmpty) {
      _sendChatText('Show this participant\'s order');
      return;
    }
    _sendChatText('Show $name\'s order');
  }

  String _resolveParticipantName(GroupOrderParticipant participant) {
    final displayName = participant.displayName.trim();
    if (displayName.isNotEmpty) return displayName;
    final contactName = participant.contact.displayName.trim();
    if (contactName.isNotEmpty) return contactName;
    return participant.participantId.trim();
  }
}
