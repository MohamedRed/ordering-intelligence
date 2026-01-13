import 'dart:convert';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';

import 'chat_audio_source.dart';

class _WebChatAudioSourceHandle implements ChatAudioSourceHandle {
  _WebChatAudioSourceHandle(this._source);

  final Source _source;

  @override
  Source get source => _source;

  @override
  Future<void> dispose() async {}
}

Future<ChatAudioSourceHandle> createChatAudioSourceHandleImpl(
  Uint8List bytes, {
  String? mimeType,
}) async {
  final safeMime = (mimeType == null || mimeType.trim().isEmpty)
      ? 'audio/mpeg'
      : mimeType.trim();
  final data = base64Encode(bytes);
  final url = 'data:$safeMime;base64,$data';
  return _WebChatAudioSourceHandle(UrlSource(url));
}
