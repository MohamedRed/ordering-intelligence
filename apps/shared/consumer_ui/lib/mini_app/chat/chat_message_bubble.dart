import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import 'chat_audio_player.dart';
import 'chat_option_chips.dart';
import 'chat_product_card.dart';
import 'package:consumer_core/consumer_core.dart';

class ChatMessageBubble extends StatelessWidget {
  const ChatMessageBubble({
    super.key,
    required this.message,
    required this.onOptionSelected,
  });

  final ChatMessage message;
  final ValueChanged<ChatOption> onOptionSelected;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final isUser = message.role == ChatRole.user;
    final bubbleColor =
        isUser ? theme.colorScheme.primary : theme.colorScheme.muted;
    final textColor =
        isUser ? theme.colorScheme.primaryForeground : theme.colorScheme.foreground;

    final hasText = message.text != null && message.text!.trim().isNotEmpty;
    final hasAudio = message.audioBytes != null;
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 320),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: bubbleColor,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            crossAxisAlignment:
                isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
            children: [
              if (hasText)
                Text(
                  message.text!,
                  style: theme.textTheme.small.copyWith(color: textColor),
                ),
              if (hasAudio) ...[
                if (hasText) const SizedBox(height: 6),
                ChatAudioPlayer(
                  bytes: message.audioBytes!,
                  mimeType: message.audioMime,
                  foregroundColor: textColor,
                  showLabel: !hasText,
                ),
              ],
              if (message.products.isNotEmpty) ...[
                const SizedBox(height: 8),
                Column(
                  children: message.products
                      .map((product) => Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: ChatProductCard(product: product),
                          ))
                      .toList(),
                ),
              ],
              if (message.options.isNotEmpty) ...[
                const SizedBox(height: 8),
                ChatOptionChips(
                  options: message.options,
                  onSelected: onOptionSelected,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
