import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import 'chat_message_bubble.dart';
import 'package:consumer_core/consumer_core.dart';

class ChatMessageList extends StatefulWidget {
  const ChatMessageList({
    super.key,
    required this.messages,
    required this.onOptionSelected,
    required this.onOptionsConfirmed,
    required this.onProductSelected,
    this.controller,
    this.isLoading = false,
    this.summaryText,
  });

  final List<ChatMessage> messages;
  final void Function(ChatMessage, ChatOption) onOptionSelected;
  final void Function(ChatMessage, List<ChatOption>) onOptionsConfirmed;
  final ValueChanged<ChatProduct> onProductSelected;
  final ScrollController? controller;
  final bool isLoading;
  final String? summaryText;

  @override
  State<ChatMessageList> createState() => _ChatMessageListState();
}

class _ChatMessageListState extends State<ChatMessageList> {
  static const int _collapsedCount = 6;
  bool _showAll = false;

  @override
  void didUpdateWidget(ChatMessageList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.messages.length < oldWidget.messages.length) {
      _showAll = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    if (widget.messages.isEmpty) {
      return Center(
        child: Text(
          'Start with a category or ask a question.',
          style: theme.textTheme.muted,
          textAlign: TextAlign.center,
        ),
      );
    }
    final totalMessages = widget.messages.length;
    final visibleMessages = _showAll || totalMessages <= _collapsedCount
        ? widget.messages
        : widget.messages.sublist(totalMessages - _collapsedCount);
    final hiddenCount = totalMessages - visibleMessages.length;
    final items = <_ChatListItem>[];
    if (hiddenCount > 0) {
      final summary = widget.summaryText?.trim();
      if (summary != null && summary.isNotEmpty) {
        items.add(_ChatSummaryItem(summary));
      }
      items.add(_ChatHistoryToggleItem(hiddenCount: hiddenCount));
    }
    for (final message in visibleMessages) {
      items.add(_ChatMessageItem(message));
    }
    if (widget.isLoading) {
      items.add(const _ChatLoadingItem());
    }
    return ListView.builder(
      controller: widget.controller,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
      itemCount: items.length,
      itemBuilder: (context, index) {
        final item = items[index];
        final gap = _gapAfter(items, index);
        final content = _buildItem(context, item);
        if (gap <= 0 || index == items.length - 1) {
          return content;
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            content,
            SizedBox(height: gap),
          ],
        );
      },
    );
  }

  double _gapAfter(List<_ChatListItem> items, int index) {
    if (index >= items.length - 1) return 0;
    final current = items[index];
    final next = items[index + 1];
    if (current is _ChatMessageItem && next is _ChatMessageItem) {
      return current.message.role == next.message.role ? 8 : 18;
    }
    if (current is _ChatSummaryItem && next is _ChatHistoryToggleItem) {
      return 8;
    }
    return 12;
  }

  Widget _buildItem(BuildContext context, _ChatListItem item) {
    final theme = ShadTheme.of(context);
    if (item is _ChatMessageItem) {
      return ChatMessageBubble(
        message: item.message,
        onOptionSelected: widget.onOptionSelected,
        onOptionsConfirmed: widget.onOptionsConfirmed,
        onProductSelected: widget.onProductSelected,
      );
    }
    if (item is _ChatHistoryToggleItem) {
      return Align(
        alignment: Alignment.centerLeft,
        child: ShadButton.outline(
          size: ShadButtonSize.sm,
          onPressed: () => setState(() => _showAll = true),
          child: Text('Show previous ${item.hiddenCount}'),
        ),
      );
    }
    if (item is _ChatSummaryItem) {
      return ShadCard(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.summarize, size: 18, color: theme.colorScheme.primary),
            const SizedBox(width: 8),
            Expanded(child: Text(item.text, style: theme.textTheme.small)),
          ],
        ),
      );
    }
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: theme.colorScheme.muted,
          borderRadius: BorderRadius.circular(14),
        ),
        child: const SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      ),
    );
  }
}

sealed class _ChatListItem {
  const _ChatListItem();
}

class _ChatMessageItem extends _ChatListItem {
  const _ChatMessageItem(this.message);

  final ChatMessage message;
}

class _ChatSummaryItem extends _ChatListItem {
  const _ChatSummaryItem(this.text);

  final String text;
}

class _ChatHistoryToggleItem extends _ChatListItem {
  const _ChatHistoryToggleItem({required this.hiddenCount});

  final int hiddenCount;
}

class _ChatLoadingItem extends _ChatListItem {
  const _ChatLoadingItem();
}
