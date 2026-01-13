import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';

import 'chat_audio_source.dart';

class _StubChatAudioSourceHandle implements ChatAudioSourceHandle {
  _StubChatAudioSourceHandle(this._source);

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
  return _StubChatAudioSourceHandle(BytesSource(bytes));
}
