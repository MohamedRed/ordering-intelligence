import 'package:consumer_core/consumer_core.dart';
import 'package:flutter/material.dart';
import 'chat_context_participant_chip.dart';

class ChatParticipantRow extends StatelessWidget {
  const ChatParticipantRow({
    super.key,
    required this.participants,
    required this.selectedParticipantId,
    required this.onSelected,
  });

  final List<GroupOrderParticipant> participants;
  final String? selectedParticipantId;
  final ValueChanged<GroupOrderParticipant> onSelected;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 52,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: participants.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final participant = participants[index];
          final isActive = participant.participantId == selectedParticipantId;
          return ChatParticipantChip(
            participant: participant,
            active: isActive,
            onTap: () => onSelected(participant),
          );
        },
      ),
    );
  }
}
