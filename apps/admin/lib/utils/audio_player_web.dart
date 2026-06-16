// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:html' as html;
import 'dart:typed_data';

Future<void> playAudioBytesImpl(Uint8List bytes,
    {String mimeType = 'audio/mpeg'}) async {
  final url = html.Url.createObjectUrlFromBlob(html.Blob([bytes], mimeType));
  final audio = html.AudioElement(url)..autoplay = true;
  await audio.play();
  audio.onEnded.first.then((_) => html.Url.revokeObjectUrl(url));
}
