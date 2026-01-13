import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';

import 'chat_audio_source_stub.dart'
    if (dart.library.html) 'chat_audio_source_web.dart'
    if (dart.library.io) 'chat_audio_source_io.dart';

abstract class ChatAudioSourceHandle {
  Source get source;
  Future<void> dispose();
}

Future<ChatAudioSourceHandle> createChatAudioSourceHandle(
  Uint8List bytes, {
  String? mimeType,
}) {
  return createChatAudioSourceHandleImpl(bytes, mimeType: mimeType);
}
