import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

class ChatComposer extends StatelessWidget {
  const ChatComposer({
    super.key,
    required this.controller,
    required this.onSend,
    required this.onToggleRecording,
    this.isRecording = false,
    this.isSending = false,
    this.canRecord = true,
    this.placeholder,
  });

  final TextEditingController controller;
  final VoidCallback onSend;
  final VoidCallback onToggleRecording;
  final bool isRecording;
  final bool isSending;
  final bool canRecord;
  final String? placeholder;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.background,
        border: Border(
          top: BorderSide(color: theme.colorScheme.border),
        ),
      ),
      child: Row(
        children: [
          if (canRecord)
            ShadButton.outline(
              size: ShadButtonSize.sm,
              onPressed: isSending ? null : onToggleRecording,
              child: Icon(isRecording ? Icons.stop : Icons.mic, size: 18),
            ),
          if (canRecord) const SizedBox(width: 8),
          Expanded(
            child: ShadInput(
              controller: controller,
              placeholder: Text(placeholder ?? 'Ask for a dish or a store...'),
              enabled: !isSending,
              onSubmitted: (_) => onSend(),
            ),
          ),
          const SizedBox(width: 8),
          ShadButton(
            onPressed: isSending ? null : onSend,
            child: isSending
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.send, size: 18),
          ),
        ],
      ),
    );
  }
}
