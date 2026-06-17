import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../util/audio_recorder.dart';

class AudioInputSelector extends StatelessWidget {
  const AudioInputSelector({
    super.key,
    required this.inputs,
    required this.selectedId,
    required this.onChanged,
    required this.onStart,
  });

  final List<AudioInputDevice> inputs;
  final String? selectedId;
  final ValueChanged<String?> onChanged;
  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final hasInputs = inputs.isNotEmpty;
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: cs.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: cs.outlineVariant),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.mic_none, size: 18),
              const SizedBox(width: 8),
              if (hasInputs)
                DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: selectedId ?? inputs.first.id,
                    items: inputs
                        .map(
                          (device) => DropdownMenuItem(
                            value: device.id,
                            child: SizedBox(
                              width: 160,
                              child: Text(
                                device.label,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: onChanged,
                  ),
                )
              else
                const Text('Default microphone'),
            ],
          ),
        ),
        ShadButton(
          onPressed: onStart,
          child: const Text('Start'),
        ),
      ],
    );
  }
}

class RecordingStopButton extends StatelessWidget {
  const RecordingStopButton({super.key, required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return ShadButton.raw(
      variant: ShadButtonVariant.primary,
      onPressed: onPressed,
      padding: const EdgeInsets.all(18),
      backgroundColor: Colors.black,
      foregroundColor: Colors.white,
      decoration: const ShadDecoration(shape: BoxShape.circle),
      child: const Icon(Icons.stop, size: 20),
    );
  }
}

class TimePill extends StatelessWidget {
  const TimePill({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(text),
    );
  }
}

class StatusDot extends StatelessWidget {
  const StatusDot({super.key, required this.active});

  final bool active;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: 10,
      height: 10,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: active ? Colors.green : cs.outlineVariant,
      ),
    );
  }
}

class WaveformBars extends StatelessWidget {
  const WaveformBars({super.key, required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    const heights = [6.0, 10.0, 8.0, 14.0, 9.0, 12.0, 7.0, 10.0];
    return Row(
      children: [
        for (final height in heights)
          Container(
            width: 3,
            height: height,
            margin: const EdgeInsets.only(right: 3),
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
      ],
    );
  }
}

class TipTile extends StatelessWidget {
  const TipTile({
    super.key,
    required this.icon,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SizedBox(
      width: 250,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 22, color: cs.onSurfaceVariant),
          const SizedBox(height: 6),
          Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 2),
          Text(body, style: TextStyle(color: cs.onSurfaceVariant)),
        ],
      ),
    );
  }
}
