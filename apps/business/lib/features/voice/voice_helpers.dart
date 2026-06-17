import '../../providers/agent_customization_api.dart';
import 'voice_models.dart';

const voiceMinimumSampleDuration = Duration(seconds: 10);

String resolveVoiceName(List<ElevenLabsVoice> voices, String voiceId) {
  final match = voices
      .where((voice) => voice.id == voiceId)
      .map((voice) => voice.name)
      .where((name) => name.isNotEmpty)
      .toList();
  if (match.isNotEmpty) return match.first;
  return voiceId;
}

Duration totalRecordedDuration(List<VoiceSample> samples) {
  var total = Duration.zero;
  for (final sample in samples) {
    total += sample.duration ?? Duration.zero;
  }
  return total;
}

bool hasMinimumVoiceSampleDuration(List<VoiceSample> samples) {
  return totalRecordedDuration(samples) >= voiceMinimumSampleDuration;
}

String formatVoiceClock(Duration duration) {
  final minutes = duration.inMinutes;
  final seconds = duration.inSeconds % 60;
  return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
}

Map<String, dynamic> buildVoiceLabels(Iterable<VoiceLabelRow> rows) {
  final labels = <String, dynamic>{};
  for (final row in rows) {
    final label = row.labelCtrl.text.trim();
    final value = row.valueCtrl.text.trim();
    if (label.isNotEmpty && value.isNotEmpty) {
      labels[label] = value;
    }
  }
  return labels;
}

String? validateVoiceCreateInput({
  required String name,
  required List<VoiceSample> samples,
  required bool consent,
}) {
  if (name.trim().isEmpty) return 'Provide a voice name.';
  if (samples.isEmpty) return 'Upload at least one audio sample.';
  if (!hasMinimumVoiceSampleDuration(samples)) {
    return 'Record at least 10 seconds of audio.';
  }
  if (!consent) return 'Confirm you have rights to use the audio.';
  return null;
}
