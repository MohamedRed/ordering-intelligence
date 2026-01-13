import 'dart:typed_data';

class FlyerAttachment {
  FlyerAttachment({
    required this.name,
    this.bytes,
    this.mime,
  });

  final String name;
  final Uint8List? bytes;
  final String? mime;
  String? uploadedUrl;
  String? uploadedKey;
  bool uploading = false;
  String? error;
}
