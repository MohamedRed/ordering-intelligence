import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../util/audio_recorder.dart';
import 'voice_dashed_border.dart';
import 'voice_helpers.dart';
import 'voice_models.dart';
import 'voice_recorder_widgets.dart';

class VoiceUploadStep extends StatelessWidget {
  const VoiceUploadStep({
    super.key,
    required this.voiceReady,
    required this.recording,
    required this.recordingElapsed,
    required this.audioInputs,
    required this.selectedAudioInputId,
    required this.samples,
    required this.removeNoise,
    required this.onBack,
    required this.onAudioInputChanged,
    required this.onStartRecording,
    required this.onStopRecording,
    required this.onPlaySample,
    required this.onRemoveSample,
    required this.onRemoveNoiseChanged,
    required this.onNext,
  });

  final bool voiceReady;
  final bool recording;
  final Duration recordingElapsed;
  final List<AudioInputDevice> audioInputs;
  final String? selectedAudioInputId;
  final List<VoiceSample> samples;
  final bool removeNoise;
  final VoidCallback onBack;
  final ValueChanged<String?> onAudioInputChanged;
  final VoidCallback onStartRecording;
  final VoidCallback onStopRecording;
  final ValueChanged<VoiceSample> onPlaySample;
  final ValueChanged<int> onRemoveSample;
  final ValueChanged<bool> onRemoveNoiseChanged;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      key: const ValueKey('voice-upload'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _VoiceRecordingTips(),
        const SizedBox(height: 16),
        DashedBorder(
          color: cs.outlineVariant,
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: ShadButton.outline(
                    onPressed: onBack,
                    child: const Text('Back'),
                  ),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  height: 160,
                  child: Center(
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 200),
                      child: recording
                          ? RecordingStopButton(onPressed: onStopRecording)
                          : AudioInputSelector(
                              inputs: audioInputs,
                              selectedId: selectedAudioInputId,
                              onChanged: onAudioInputChanged,
                              onStart: onStartRecording,
                            ),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    WaveformBars(
                      color: cs.onSurfaceVariant.withValues(alpha: 0.6),
                    ),
                    const Spacer(),
                    TimePill(
                      text: '${formatVoiceClock(recordingElapsed)}  /  00:30',
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        for (final entry in samples.asMap().entries)
          _VoiceSampleRow(
            index: entry.key,
            sample: entry.value,
            onPlay: onPlaySample,
            onRemove: onRemoveSample,
          ),
        const SizedBox(height: 4),
        Row(
          children: [
            ShadCheckbox(
              value: removeNoise,
              onChanged: onRemoveNoiseChanged,
            ),
            const SizedBox(width: 8),
            const Flexible(
              child: Text('Remove background noise from audio recordings'),
            ),
          ],
        ),
        if (voiceReady) ...[
          const SizedBox(height: 8),
          _VoiceReadyMessage(color: cs.onSurfaceVariant),
        ],
        const SizedBox(height: 12),
        Row(
          children: [
            StatusDot(active: voiceReady),
            const SizedBox(width: 8),
            const Flexible(child: Text('10 seconds of audio required')),
            const Spacer(),
            ShadButton(
              onPressed: voiceReady ? onNext : null,
              child: const Text('Next'),
            ),
          ],
        ),
      ],
    );
  }
}

class _VoiceRecordingTips extends StatelessWidget {
  const _VoiceRecordingTips();

  @override
  Widget build(BuildContext context) {
    return const Wrap(
      spacing: 16,
      runSpacing: 16,
      children: [
        TipTile(
          icon: Icons.headset_off,
          title: 'Avoid noisy environments',
          body: 'Background sounds interfere with recording quality results.',
        ),
        TipTile(
          icon: Icons.thumb_up_alt_outlined,
          title: 'Check microphone quality',
          body: 'Try external units or headphone mics for better capture.',
        ),
        TipTile(
          icon: Icons.mic_none,
          title: 'Use consistent equipment',
          body: "Don't change recording equipment between samples.",
        ),
      ],
    );
  }
}

class _VoiceSampleRow extends StatelessWidget {
  const _VoiceSampleRow({
    required this.index,
    required this.sample,
    required this.onPlay,
    required this.onRemove,
  });

  final int index;
  final VoiceSample sample;
  final ValueChanged<VoiceSample> onPlay;
  final ValueChanged<int> onRemove;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  sample.displayName,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                Text(
                  sample.duration != null
                      ? formatVoiceClock(sample.duration!)
                      : '',
                  style: TextStyle(color: cs.onSurfaceVariant),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: () => onPlay(sample),
            icon: const Icon(Icons.play_arrow),
          ),
          IconButton(
            onPressed: () => onRemove(index),
            icon: const Icon(Icons.delete_outline),
          ),
        ],
      ),
    );
  }
}

class _VoiceReadyMessage extends StatelessWidget {
  const _VoiceReadyMessage({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Icon(Icons.check_circle, color: Colors.green, size: 18),
        const SizedBox(width: 8),
        Flexible(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Ready',
                  style: TextStyle(fontWeight: FontWeight.w600)),
              Text(
                'Continue to add recordings for a better clone',
                style: TextStyle(color: color),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
