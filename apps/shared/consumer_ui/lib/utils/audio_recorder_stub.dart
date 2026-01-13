import 'dart:typed_data';

import 'audio_recorder.dart';

class _StubRecorder implements AudioRecorder {
  @override
  bool get isRecording => false;

  @override
  String get mimeType => 'audio/webm';

  @override
  Future<List<AudioInputDevice>> listInputs() async => const [];

  @override
  Future<void> start({String? deviceId}) async {
    throw UnsupportedError('Audio recording is not supported on this platform.');
  }

  @override
  Future<Uint8List> stop() async {
    throw UnsupportedError('Audio recording is not supported on this platform.');
  }

  @override
  void dispose() {}
}

AudioRecorder createAudioRecorderImpl() => _StubRecorder();
