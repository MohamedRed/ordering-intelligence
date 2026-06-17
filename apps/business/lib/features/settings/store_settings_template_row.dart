import 'package:flutter/material.dart';

class TemplateRow {
  TemplateRow({required String id, String label = '', String body = ''})
      : id = TextEditingController(text: id),
        label = TextEditingController(text: label),
        body = TextEditingController(text: body);

  final TextEditingController id;
  final TextEditingController label;
  final TextEditingController body;

  void dispose() {
    id.dispose();
    label.dispose();
    body.dispose();
  }
}

TemplateRow newTemplateRow(DateTime now) {
  return TemplateRow(
    id: 'tmpl_${now.millisecondsSinceEpoch}',
    label: 'Template',
    body: '',
  );
}

void disposeTemplateRows(Map<String, List<TemplateRow>> rowsByStatus) {
  for (final rows in rowsByStatus.values) {
    for (final row in rows) {
      row.dispose();
    }
  }
}
