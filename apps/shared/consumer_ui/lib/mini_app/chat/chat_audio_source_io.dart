import 'dart:io';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:path_provider/path_provider.dart';

import 'chat_audio_source.dart';

class _IoChatAudioSourceHandle implements ChatAudioSourceHandle {
  _IoChatAudioSourceHandle(this._file);

  final File _file;

  @override
  Source get source => DeviceFileSource(_file.path);

  @override
  Future<void> dispose() async {
    try {
      if (await _file.exists()) {
        await _file.delete();
      }
    } catch (_) {}
  }
}

Future<ChatAudioSourceHandle> createChatAudioSourceHandleImpl(
  Uint8List bytes, {
  String? mimeType,
}) async {
  final dir = await getTemporaryDirectory();
  final extension = _extensionForMime(mimeType);
  final file = File(
    '${dir.path}/chat-audio-${DateTime.now().microsecondsSinceEpoch}$extension',
  );
  await file.writeAsBytes(bytes, flush: true);
  return _IoChatAudioSourceHandle(file);
}

String _extensionForMime(String? mimeType) {
  final normalized = mimeType?.toLowerCase().trim() ?? '';
  if (normalized.contains('webm')) return '.webm';
  if (normalized.contains('m4a')) return '.m4a';
  if (normalized.contains('mp4')) return '.mp4';
  if (normalized.contains('mpeg') || normalized.contains('mp3')) {
    return '.mp3';
  }
  if (normalized.contains('wav')) return '.wav';
  if (normalized.contains('ogg')) return '.ogg';
  return '.m4a';
}
