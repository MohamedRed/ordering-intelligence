import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

class VoiceFinishStep extends StatelessWidget {
  const VoiceFinishStep({super.key, required this.onSkip});

  final VoidCallback onSkip;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      key: const ValueKey('voice-finish'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Try out your new clone',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 4),
        Text(
          'Your voice is now ready to be used throughout the product.',
          style: TextStyle(color: cs.onSurfaceVariant),
        ),
        const SizedBox(height: 16),
        const _FinishCard(
          title: 'Generate speech',
          body: 'Take your new clone for a test drive with Text to Speech.',
          color: Color(0xFFDCE6FF),
        ),
        const SizedBox(height: 12),
        const _FinishCard(
          title: 'Speak with yourself',
          body: 'Speak with your own clone by creating an ElevenLabs Agent.',
          color: Color(0xFFDCF5FF),
        ),
        const SizedBox(height: 12),
        const _FinishCard(
          title: 'Narrate a story',
          body: 'Create a story narrated by you using Studio.',
          color: Color(0xFFDFF6E8),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            const Spacer(),
            ShadButton(
              onPressed: onSkip,
              child: const Text('Skip'),
            ),
          ],
        ),
      ],
    );
  }
}

class _FinishCard extends StatelessWidget {
  const _FinishCard({
    required this.title,
    required this.body,
    required this.color,
  });

  final String title;
  final String body;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.play_arrow),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 2),
                Text(body, style: TextStyle(color: cs.onSurfaceVariant)),
              ],
            ),
          ),
          const Icon(Icons.chevron_right),
        ],
      ),
    );
  }
}
