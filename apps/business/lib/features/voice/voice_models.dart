import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../providers/agent_customization_api.dart';

class VoiceSample {
  VoiceSample({
    required this.upload,
    required this.displayName,
    this.duration,
  });

  final VoiceSampleUpload upload;
  final String displayName;
  final Duration? duration;
}

class VoiceLabelRow {
  VoiceLabelRow({String label = '', String value = ''})
      : labelCtrl = TextEditingController(text: label),
        valueCtrl = TextEditingController(text: value);

  final TextEditingController labelCtrl;
  final TextEditingController valueCtrl;

  void dispose() {
    labelCtrl.dispose();
    valueCtrl.dispose();
  }
}

VoiceSample createRecordedVoiceSample({
  required int index,
  required Uint8List bytes,
  required Duration duration,
}) {
  return VoiceSample(
    upload: VoiceSampleUpload(
      bytes: bytes,
      filename: 'Recording $index.webm',
      mimeType: 'audio/webm',
    ),
    displayName: 'Recording $index.mp4',
    duration: duration,
  );
}

void disposeVoiceLabelRows(Iterable<VoiceLabelRow> rows) {
  for (final row in rows) {
    row.dispose();
  }
}
