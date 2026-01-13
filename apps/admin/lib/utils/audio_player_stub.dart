import 'dart:typed_data';

Future<void> playAudioBytesImpl(Uint8List bytes, {String mimeType = 'audio/mpeg'}) async {
  // No-op on non-web platforms for now.
}
