import 'dart:typed_data';

import 'audio_player_stub.dart'
    if (dart.library.html) 'audio_player_web.dart';

Future<void> playAudioBytes(Uint8List bytes, {String mimeType = 'audio/mpeg'}) {
  return playAudioBytesImpl(bytes, mimeType: mimeType);
}
