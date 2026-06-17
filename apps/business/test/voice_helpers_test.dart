import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:business_app/features/voice/voice_helpers.dart';
import 'package:business_app/features/voice/voice_models.dart';
import 'package:business_app/providers/agent_customization_api.dart';

void main() {
  test('voice helper resolves display names and formats durations', () {
    final voices = [
      ElevenLabsVoice(id: 'voice-a', name: 'Host A'),
      ElevenLabsVoice(id: 'voice-b', name: ''),
    ];

    expect(resolveVoiceName(voices, 'voice-a'), 'Host A');
    expect(resolveVoiceName(voices, 'voice-b'), 'voice-b');
    expect(resolveVoiceName(voices, 'missing'), 'missing');
    expect(formatVoiceClock(const Duration(minutes: 2, seconds: 7)), '02:07');
  });

  test('voice helper totals recorded duration and validates create input', () {
    final samples = [
      VoiceSample(
        upload: VoiceSampleUpload(
          bytes: Uint8List.fromList([1]),
          filename: 'a.webm',
          mimeType: 'audio/webm',
        ),
        displayName: 'A',
        duration: const Duration(seconds: 4),
      ),
      VoiceSample(
        upload: VoiceSampleUpload(
          bytes: Uint8List.fromList([2]),
          filename: 'b.webm',
          mimeType: 'audio/webm',
        ),
        displayName: 'B',
        duration: const Duration(seconds: 6),
      ),
    ];

    expect(totalRecordedDuration(samples), const Duration(seconds: 10));
    expect(hasMinimumVoiceSampleDuration(samples), isTrue);
    expect(
      validateVoiceCreateInput(
          name: ' Store voice ', samples: samples, consent: true),
      isNull,
    );
    expect(
      validateVoiceCreateInput(name: '', samples: samples, consent: true),
      'Provide a voice name.',
    );
    expect(
      validateVoiceCreateInput(name: 'x', samples: const [], consent: true),
      'Upload at least one audio sample.',
    );
    expect(
      validateVoiceCreateInput(
        name: 'x',
        samples: samples.take(1).toList(),
        consent: true,
      ),
      'Record at least 10 seconds of audio.',
    );
    expect(
      validateVoiceCreateInput(name: 'x', samples: samples, consent: false),
      'Confirm you have rights to use the audio.',
    );
  });

  test('voice label builder trims rows and skips incomplete labels', () {
    final rows = [
      VoiceLabelRow(label: ' Language ', value: ' English '),
      VoiceLabelRow(label: 'Empty value', value: ''),
      VoiceLabelRow(label: '', value: 'ignored'),
    ];

    addTearDown(() => disposeVoiceLabelRows(rows));

    expect(buildVoiceLabels(rows), {'Language': 'English'});
  });

  test('recorded sample factory preserves upload metadata', () {
    final bytes = Uint8List.fromList([1, 2, 3]);
    final sample = createRecordedVoiceSample(
      index: 3,
      bytes: bytes,
      duration: const Duration(seconds: 12),
    );

    expect(sample.upload.bytes, bytes);
    expect(sample.upload.filename, 'Recording 3.webm');
    expect(sample.upload.mimeType, 'audio/webm');
    expect(sample.displayName, 'Recording 3.mp4');
    expect(sample.duration, const Duration(seconds: 12));
  });
}
