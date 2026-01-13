import 'package:consumer_core/consumer_core.dart';
import 'package:flutter/material.dart';

import 'auto_diagnostics_service.dart';
import 'auto_diagnostics_view.dart';

class AutoDiagnosticsScreen extends StatefulWidget {
  const AutoDiagnosticsScreen({super.key, required this.session});

  final SessionInfo session;

  @override
  State<AutoDiagnosticsScreen> createState() => _AutoDiagnosticsScreenState();
}

class _AutoDiagnosticsScreenState extends State<AutoDiagnosticsScreen> {
  final AutoDiagnosticsService _service = AutoDiagnosticsService();
  late Future<AutoDiagnosticsSnapshot> _future;

  @override
  void initState() {
    super.initState();
    _future = _service.load(widget.session);
  }

  void _refresh() {
    setState(() {
      _future = _service.load(widget.session);
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<AutoDiagnosticsSnapshot>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        if (snapshot.hasError) {
          return Scaffold(
            appBar: AppBar(title: const Text('Auto diagnostics')),
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Failed to load diagnostics: ${snapshot.error}',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton(
                      onPressed: _refresh,
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              ),
            ),
          );
        }
        final data = snapshot.data;
        if (data == null) {
          return Scaffold(
            appBar: AppBar(title: const Text('Auto diagnostics')),
            body: Center(
              child: OutlinedButton(
                onPressed: _refresh,
                child: const Text('Reload'),
              ),
            ),
          );
        }
        return AutoDiagnosticsView(
          snapshot: data,
          onRefresh: _refresh,
        );
      },
    );
  }
}
