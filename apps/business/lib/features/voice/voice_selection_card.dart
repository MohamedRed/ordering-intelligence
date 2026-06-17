import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../providers/agent_customization_api.dart';

class VoiceSelectionCard extends StatelessWidget {
  const VoiceSelectionCard({
    super.key,
    required this.voices,
    required this.selectedVoiceId,
    required this.selectedVoiceName,
    required this.appliedVoiceId,
    required this.appliedVoiceName,
    required this.voiceLoading,
    required this.voiceApplying,
    required this.storeLoading,
    required this.onVoiceChanged,
    required this.onRefresh,
    required this.onApply,
    required this.onPreview,
  });

  final List<ElevenLabsVoice> voices;
  final String? selectedVoiceId;
  final String? selectedVoiceName;
  final String? appliedVoiceId;
  final String? appliedVoiceName;
  final bool voiceLoading;
  final bool voiceApplying;
  final bool storeLoading;
  final ValueChanged<String> onVoiceChanged;
  final VoidCallback onRefresh;
  final VoidCallback onApply;
  final VoidCallback onPreview;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final dropdownVoiceId = _dropdownVoiceId();
    return ShadCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Voice selection',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          Text(
            "Choose the voice used by your store's agent.",
            style: TextStyle(color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                width: 420,
                child: DropdownButtonFormField<String>(
                  initialValue: dropdownVoiceId,
                  decoration:
                      const InputDecoration(labelText: 'Existing voices'),
                  items: voices
                      .map(
                        (voice) => DropdownMenuItem(
                          value: voice.id,
                          child:
                              Text(voice.name.isEmpty ? voice.id : voice.name),
                        ),
                      )
                      .toList(),
                  onChanged: (value) {
                    if (value != null) onVoiceChanged(value);
                  },
                ),
              ),
              ShadButton.outline(
                onPressed: voiceLoading ? null : onRefresh,
                child: voiceLoading
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Refresh'),
              ),
            ],
          ),
          if ((selectedVoiceId ?? '').isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              'Selected voice: ${selectedVoiceName ?? selectedVoiceId}',
              style: TextStyle(color: cs.onSurfaceVariant),
            ),
          ],
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              ShadButton(
                onPressed: voiceApplying ? null : onApply,
                child: voiceApplying
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Apply voice'),
              ),
              ShadButton.outline(
                onPressed: selectedVoiceId == null ? null : onPreview,
                child: const Text('Preview'),
              ),
              if (storeLoading) const Text('Loading current voice...'),
              if ((appliedVoiceId ?? '').isNotEmpty)
                ShadBadge.secondary(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  child: Text('Applied: ${appliedVoiceName ?? appliedVoiceId}'),
                ),
            ],
          ),
        ],
      ),
    );
  }

  String? _dropdownVoiceId() {
    final selected = selectedVoiceId;
    if (selected == null || selected.isEmpty) return null;
    return voices.any((voice) => voice.id == selected) ? selected : null;
  }
}
