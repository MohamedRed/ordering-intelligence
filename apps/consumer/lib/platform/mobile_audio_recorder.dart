import 'dart:io';
import 'dart:typed_data';

import 'package:consumer_ui/consumer_ui.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart' as record;

class MobileAudioRecorder implements AudioRecorder {
  MobileAudioRecorder();

  final record.AudioRecorder _recorder = record.AudioRecorder();
  bool _recording = false;
  String? _lastPath;
  String _mimeType = 'audio/m4a';

  @override
  String get mimeType => _mimeType;

  @override
  bool get isRecording => _recording;

  @override
  Future<List<AudioInputDevice>> listInputs() async {
    return const [AudioInputDevice(id: 'default', label: 'Microphone')];
  }

  @override
  Future<void> start({String? deviceId}) async {
    if (_recording) return;
    final hasPermission = await _recorder.hasPermission();
    if (!hasPermission) {
      throw UnsupportedError('Microphone permission denied.');
    }
    final dir = await getTemporaryDirectory();
    final path = '${dir.path}/voice_${DateTime.now().millisecondsSinceEpoch}.m4a';
    const config = record.RecordConfig(
      encoder: record.AudioEncoder.aacLc,
      bitRate: 128000,
      sampleRate: 44100,
    );
    await _recorder.start(config, path: path);
    _lastPath = path;
    _mimeType = 'audio/m4a';
    _recording = true;
  }

  @override
  Future<Uint8List> stop() async {
    if (!_recording) return Uint8List(0);
    final path = await _recorder.stop();
    _recording = false;
    final target = path ?? _lastPath;
    if (target == null || target.isEmpty) return Uint8List(0);
    final file = File(target);
    if (!await file.exists()) return Uint8List(0);
    final bytes = await file.readAsBytes();
    try {
      await file.delete();
    } catch (_) {}
    return bytes;
  }

  @override
  void dispose() {
    _recorder.dispose();
  }
}
