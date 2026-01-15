import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import 'chat_audio_player.dart';
import 'chat_option_chips.dart';
import 'chat_option_multi_select.dart';
import 'chat_product_card.dart';
import 'package:consumer_core/consumer_core.dart';

class ChatMessageBubble extends StatelessWidget {
  const ChatMessageBubble({
    super.key,
    required this.message,
    required this.onOptionSelected,
    required this.onOptionsConfirmed,
    required this.onProductSelected,
  });

  final ChatMessage message;
  final void Function(ChatMessage, ChatOption) onOptionSelected;
  final void Function(ChatMessage, List<ChatOption>) onOptionsConfirmed;
  final ValueChanged<ChatProduct> onProductSelected;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final isUser = message.role == ChatRole.user;
    final bubbleColor = isUser
        ? theme.colorScheme.muted
        : theme.colorScheme.primary;
    final textColor = isUser
        ? theme.colorScheme.foreground
        : theme.colorScheme.primaryForeground;

    final hasText = message.text != null && message.text!.trim().isNotEmpty;
    final hasAudio = message.audioBytes != null;
    final hasBubble = hasText || hasAudio;
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Column(
        crossAxisAlignment: isUser
            ? CrossAxisAlignment.end
            : CrossAxisAlignment.start,
        children: [
          if (hasBubble)
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 320),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: bubbleColor,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  crossAxisAlignment: isUser
                      ? CrossAxisAlignment.end
                      : CrossAxisAlignment.start,
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
                  ],
                ),
              ),
            ),
          if (message.products.isNotEmpty) ...[
            if (hasBubble) const SizedBox(height: 8),
            SizedBox(
              height: 96,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: message.products.length,
                separatorBuilder: (_, __) => const SizedBox(width: 10),
                itemBuilder: (context, index) {
                  final product = message.products[index];
                  return SizedBox(
                    width: 240,
                    child: ChatProductCard(
                      product: product,
                      onTap: () => onProductSelected(product),
                    ),
                  );
                },
              ),
            ),
          ],
          if (message.options.isNotEmpty) ...[
            if (hasBubble || message.products.isNotEmpty)
              const SizedBox(height: 8),
            if (message.isMultiSelect)
              ChatOptionMultiSelect(
                options: message.options,
                confirmLabel: message.confirmLabel,
                minSelections: message.minSelections,
                maxSelections: message.maxSelections,
                onConfirm: (selections) =>
                    onOptionsConfirmed(message, selections),
              )
            else
              ChatOptionChips(
                options: message.options,
                onSelected: (option) => onOptionSelected(message, option),
              ),
          ],
        ],
      ),
    );
  }
}
