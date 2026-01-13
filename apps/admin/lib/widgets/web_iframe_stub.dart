import 'package:flutter/material.dart';

/// Non-web fallback: display a placeholder.
class WebIFrame extends StatelessWidget {
  const WebIFrame({
    super.key,
    this.url,
    this.srcDoc,
  });

  final String? url;
  final String? srcDoc;

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Text('Embedded web views are only supported on Flutter Web.'),
    );
  }
}


