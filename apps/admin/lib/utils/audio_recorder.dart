import 'dart:typed_data';

import 'audio_recorder_stub.dart'
    if (dart.library.html) 'audio_recorder_web.dart';

class AudioInputDevice {
  const AudioInputDevice({required this.id, required this.label});

  final String id;
  final String label;
}

abstract class AudioRecorder {
  Future<List<AudioInputDevice>> listInputs();
  Future<void> start({String? deviceId});
  Future<Uint8List> stop();
  bool get isRecording;
  void dispose();
}

AudioRecorder createAudioRecorder() => createAudioRecorderImpl();
