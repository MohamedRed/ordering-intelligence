// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

import 'dart:html' as html;
import 'dart:ui_web' as ui;

import 'package:flutter/material.dart';

class WebIFrame extends StatefulWidget {
  const WebIFrame({
    super.key,
    this.url,
    this.srcDoc,
  });

  final String? url;
  final String? srcDoc;

  @override
  State<WebIFrame> createState() => _WebIFrameState();
}

class _WebIFrameState extends State<WebIFrame> {
  late final String _viewType;

  @override
  void initState() {
    super.initState();
    _viewType = 'iframe_${DateTime.now().microsecondsSinceEpoch}';
    // Register once per widget instance.
    // ignore: undefined_prefixed_name
    ui.platformViewRegistry.registerViewFactory(_viewType, (int _) {
      final el = html.IFrameElement()
        ..style.border = '0'
        ..style.width = '100%'
        ..style.height = '100%'
        ..allow = 'microphone; autoplay; clipboard-read; clipboard-write';

      final sb = el.sandbox;
      if (sb != null) {
        for (final token in const [
          'allow-scripts',
          'allow-same-origin',
          'allow-forms',
          'allow-popups',
          'allow-modals',
        ]) {
          sb.add(token);
        }
      }

      final srcDoc = widget.srcDoc?.trim();
      final url = widget.url?.trim();
      if (srcDoc != null && srcDoc.isNotEmpty) {
        el.srcdoc = srcDoc;
      } else if (url != null && url.isNotEmpty) {
        el.src = url;
      }
      return el;
    });
  }

  @override
  Widget build(BuildContext context) {
    return HtmlElementView(viewType: _viewType);
  }
}
