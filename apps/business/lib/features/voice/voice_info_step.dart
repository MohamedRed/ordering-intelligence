import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import 'voice_models.dart';

class VoiceInfoStep extends StatelessWidget {
  const VoiceInfoStep({
    super.key,
    required this.voiceId,
    required this.saving,
    required this.nameController,
    required this.descriptionController,
    required this.labels,
    required this.consent,
    required this.onPreview,
    required this.onAddLabel,
    required this.onRemoveLabel,
    required this.onConsentChanged,
    required this.onBack,
    required this.onSave,
  });

  final String? voiceId;
  final bool saving;
  final TextEditingController nameController;
  final TextEditingController descriptionController;
  final List<VoiceLabelRow> labels;
  final bool consent;
  final VoidCallback onPreview;
  final VoidCallback onAddLabel;
  final ValueChanged<int> onRemoveLabel;
  final ValueChanged<bool?> onConsentChanged;
  final VoidCallback onBack;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      key: const ValueKey('voice-info'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.graphic_eq),
            ),
            const SizedBox(width: 12),
            ShadButton.outline(
              onPressed: voiceId == null ? null : onPreview,
              child: const Text('Preview voice'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        ShadInputFormField(
          controller: nameController,
          label: const Text('Name'),
          placeholder: const Text('e.g. old British man'),
        ),
        const SizedBox(height: 12),
        const _LabelHeader(),
        const SizedBox(height: 6),
        for (final entry in labels.asMap().entries)
          _VoiceLabelEditor(
            index: entry.key,
            row: entry.value,
            onRemove: onRemoveLabel,
          ),
        ShadButton.outline(
          onPressed: onAddLabel,
          child: const Text('Add label'),
        ),
        const SizedBox(height: 12),
        ShadInputFormField(
          controller: descriptionController,
          label: const Text('Description'),
          maxLines: 3,
        ),
        const SizedBox(height: 12),
        CheckboxListTile(
          value: consent,
          onChanged: onConsentChanged,
          title: const Text(
            'I confirm I have rights to use these audio samples and accept ElevenLabs policies.',
          ),
          contentPadding: EdgeInsets.zero,
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            ShadButton.outline(
              onPressed: onBack,
              child: const Text('Back'),
            ),
            const Spacer(),
            ShadButton(
              onPressed: saving ? null : onSave,
              child: saving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Save voice'),
            ),
          ],
        ),
      ],
    );
  }
}

class _LabelHeader extends StatelessWidget {
  const _LabelHeader();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 560) return const SizedBox.shrink();
        return const Row(
          children: [
            Expanded(
              child:
                  Text('Label', style: TextStyle(fontWeight: FontWeight.w600)),
            ),
            SizedBox(width: 10),
            Expanded(
              child:
                  Text('Value', style: TextStyle(fontWeight: FontWeight.w600)),
            ),
            SizedBox(width: 48),
          ],
        );
      },
    );
  }
}

class _VoiceLabelEditor extends StatelessWidget {
  const _VoiceLabelEditor({
    required this.index,
    required this.row,
    required this.onRemove,
  });

  final int index;
  final VoiceLabelRow row;
  final ValueChanged<int> onRemove;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final fields = [
            TextFormField(
              controller: row.labelCtrl,
              decoration: const InputDecoration(
                labelText: 'Label',
                suffixIcon: Icon(Icons.expand_more),
              ),
            ),
            TextFormField(
              controller: row.valueCtrl,
              decoration: const InputDecoration(
                labelText: 'Value',
                suffixIcon: Icon(Icons.expand_more),
              ),
            ),
          ];
          if (constraints.maxWidth < 560) {
            return Column(
              children: [
                fields[0],
                const SizedBox(height: 8),
                fields[1],
                Align(
                  alignment: Alignment.centerRight,
                  child: IconButton(
                    onPressed: () => onRemove(index),
                    icon: const Icon(Icons.close),
                  ),
                ),
              ],
            );
          }
          return Row(
            children: [
              Expanded(child: fields[0]),
              const SizedBox(width: 10),
              Expanded(child: fields[1]),
              IconButton(
                onPressed: () => onRemove(index),
                icon: const Icon(Icons.close),
              ),
            ],
          );
        },
      ),
    );
  }
}
