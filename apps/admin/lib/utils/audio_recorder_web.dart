// ignore_for_file: avoid_web_libraries_in_flutter
import 'dart:async';
import 'dart:html' as html;
import 'dart:typed_data';

import 'audio_recorder.dart';

class _WebRecorder implements AudioRecorder {
  html.MediaRecorder? _recorder;
  html.MediaStream? _stream;
  final List<html.Blob> _chunks = [];
  bool _recording = false;
  static const _dataAvailableEvent =
      html.EventStreamProvider<html.BlobEvent>('dataavailable');
  static const _stopEvent = html.EventStreamProvider<html.Event>('stop');

  @override
  bool get isRecording => _recording;

  @override
  Future<List<AudioInputDevice>> listInputs() async {
    final devices = await html.window.navigator.mediaDevices?.enumerateDevices();
    if (devices == null) return const [];
    final inputs = devices
        .where((d) => d.kind == 'audioinput')
        .map((d) => AudioInputDevice(
              id: d.deviceId ?? '',
              label: (d.label ?? '').isNotEmpty ? d.label! : 'Default microphone',
            ))
        .toList();
    if (inputs.isEmpty) {
      return const [AudioInputDevice(id: '', label: 'Default microphone')];
    }
    return inputs;
  }

  @override
  Future<void> start({String? deviceId}) async {
    if (_recording) return;
    final constraints = deviceId != null && deviceId.isNotEmpty
        ? {
            'audio': {
              'deviceId': {'exact': deviceId}
            }
          }
        : {
            'audio': true
          };
    _stream = await html.window.navigator.mediaDevices!
        .getUserMedia(constraints as Map<String, dynamic>);
    _chunks.clear();
    _recorder = html.MediaRecorder(_stream!);
    _dataAvailableEvent.forTarget(_recorder!).listen((event) {
      final data = event.data;
      if (data != null) {
        _chunks.add(data);
      }
    });
    _recorder!.start();
    _recording = true;
  }

  @override
  Future<Uint8List> stop() async {
    if (!_recording || _recorder == null) {
      return Uint8List(0);
    }
    final recorder = _recorder!;
    final completer = Completer<Uint8List>();

    late StreamSubscription<html.Event> sub;
    sub = _stopEvent.forTarget(recorder).listen((_) async {
      sub.cancel();
      final blob = html.Blob(_chunks, 'audio/webm');
      final reader = html.FileReader();
      reader.readAsArrayBuffer(blob);
      await reader.onLoadEnd.first;
      final buffer = reader.result as ByteBuffer;
      final bytes = Uint8List.view(buffer);
      completer.complete(bytes);
      _chunks.clear();
      _recording = false;
      _recorder = null;
      _stream?.getTracks().forEach((t) => t.stop());
      _stream = null;
    });

    recorder.stop();
    return completer.future;
  }

  @override
  void dispose() {
    _recorder?.stop();
    _recorder = null;
    _stream?.getTracks().forEach((t) => t.stop());
    _stream = null;
    _chunks.clear();
    _recording = false;
  }
}

AudioRecorder createAudioRecorderImpl() => _WebRecorder();
