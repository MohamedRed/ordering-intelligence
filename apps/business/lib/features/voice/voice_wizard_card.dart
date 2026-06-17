import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../util/audio_recorder.dart';
import 'voice_finish_step.dart';
import 'voice_info_step.dart';
import 'voice_models.dart';
import 'voice_step_item.dart';
import 'voice_upload_step.dart';

class VoiceWizardCard extends StatelessWidget {
  const VoiceWizardCard({
    super.key,
    required this.step,
    required this.voiceReady,
    required this.voiceId,
    required this.voiceSaving,
    required this.voiceNameController,
    required this.voiceDescriptionController,
    required this.voiceLabels,
    required this.voiceConsent,
    required this.voiceRemoveNoise,
    required this.recording,
    required this.recordingElapsed,
    required this.audioInputs,
    required this.selectedAudioInputId,
    required this.samples,
    required this.onStepChanged,
    required this.onPreviewVoice,
    required this.onCreateVoice,
    required this.onAddLabel,
    required this.onRemoveLabel,
    required this.onConsentChanged,
    required this.onRemoveNoiseChanged,
    required this.onAudioInputChanged,
    required this.onStartRecording,
    required this.onStopRecording,
    required this.onPlaySample,
    required this.onRemoveSample,
  });

  final int step;
  final bool voiceReady;
  final String? voiceId;
  final bool voiceSaving;
  final TextEditingController voiceNameController;
  final TextEditingController voiceDescriptionController;
  final List<VoiceLabelRow> voiceLabels;
  final bool voiceConsent;
  final bool voiceRemoveNoise;
  final bool recording;
  final Duration recordingElapsed;
  final List<AudioInputDevice> audioInputs;
  final String? selectedAudioInputId;
  final List<VoiceSample> samples;
  final ValueChanged<int> onStepChanged;
  final VoidCallback onPreviewVoice;
  final VoidCallback onCreateVoice;
  final VoidCallback onAddLabel;
  final ValueChanged<int> onRemoveLabel;
  final ValueChanged<bool?> onConsentChanged;
  final ValueChanged<bool> onRemoveNoiseChanged;
  final ValueChanged<String?> onAudioInputChanged;
  final VoidCallback onStartRecording;
  final VoidCallback onStopRecording;
  final ValueChanged<VoiceSample> onPlaySample;
  final ValueChanged<int> onRemoveSample;

  @override
  Widget build(BuildContext context) {
    return ShadCard(
      padding: const EdgeInsets.all(18),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final sidebar = _VoiceWizardSidebar(step: step);
          final body = AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            child: _stepBody(),
          );
          if (constraints.maxWidth < 760) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                sidebar,
                const SizedBox(height: 18),
                body,
              ],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(width: 220, child: sidebar),
              const SizedBox(width: 18),
              Expanded(child: body),
            ],
          );
        },
      ),
    );
  }

  Widget _stepBody() {
    if (step == 0) {
      return VoiceUploadStep(
        voiceReady: voiceReady,
        recording: recording,
        recordingElapsed: recordingElapsed,
        audioInputs: audioInputs,
        selectedAudioInputId: selectedAudioInputId,
        samples: samples,
        removeNoise: voiceRemoveNoise,
        onBack: () => onStepChanged(0),
        onAudioInputChanged: onAudioInputChanged,
        onStartRecording: onStartRecording,
        onStopRecording: onStopRecording,
        onPlaySample: onPlaySample,
        onRemoveSample: onRemoveSample,
        onRemoveNoiseChanged: onRemoveNoiseChanged,
        onNext: () => onStepChanged(1),
      );
    }
    if (step == 1) {
      return VoiceInfoStep(
        voiceId: voiceId,
        saving: voiceSaving,
        nameController: voiceNameController,
        descriptionController: voiceDescriptionController,
        labels: voiceLabels,
        consent: voiceConsent,
        onPreview: onPreviewVoice,
        onAddLabel: onAddLabel,
        onRemoveLabel: onRemoveLabel,
        onConsentChanged: onConsentChanged,
        onBack: () => onStepChanged(0),
        onSave: onCreateVoice,
      );
    }
    return VoiceFinishStep(onSkip: () => onStepChanged(0));
  }
}

class _VoiceWizardSidebar extends StatelessWidget {
  const _VoiceWizardSidebar({required this.step});

  final int step;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.flash_on_outlined, size: 28),
        const SizedBox(height: 12),
        const Text(
          'Instant Voice Clone',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 16),
        Wrap(
          direction: Axis.vertical,
          spacing: 8,
          children: [
            VoiceStepItem(
              label: 'Upload Audio',
              active: step == 0,
              done: step > 0,
            ),
            VoiceStepItem(
              label: 'Voice Information',
              active: step == 1,
              done: step > 1,
            ),
            VoiceStepItem(
              label: 'Finish up',
              active: step == 2,
              done: step > 2,
            ),
          ],
        ),
      ],
    );
  }
}
