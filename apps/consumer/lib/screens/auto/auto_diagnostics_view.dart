import 'package:flutter/material.dart';

import 'auto_diagnostics_service.dart';

class AutoDiagnosticsView extends StatelessWidget {
  const AutoDiagnosticsView({
    super.key,
    required this.snapshot,
    required this.onRefresh,
  });

  final AutoDiagnosticsSnapshot snapshot;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    final session = snapshot.session;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Auto diagnostics'),
        actions: [
          IconButton(
            onPressed: onRefresh,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _sectionTitle('Session'),
            _row('Session ID', session.sessionId),
            _row('Customer ID', session.customerId),
            _row('Tenant ID', session.tenantId),
            _row('Store ID', session.storeId),
            const SizedBox(height: 16),
            _sectionTitle('Shared storage'),
            _row('Shared session ID', snapshot.sharedSessionId ?? 'n/a'),
            _row('Shared customer ID', snapshot.sharedCustomerId ?? 'n/a'),
            _row(
              'Session match',
              snapshot.sharedSessionMatches ? 'Yes' : 'No',
              valueColor: snapshot.sharedSessionMatches
                  ? Colors.green
                  : Colors.redAccent,
            ),
            const SizedBox(height: 16),
            _sectionTitle('Push'),
            _row('Firebase ready', snapshot.firebaseReady ? 'Yes' : 'No'),
            _row('FCM token', snapshot.fcmToken ?? 'n/a'),
          ],
        ),
      ),
    );
  }

  Widget _sectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        title,
        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
      ),
    );
  }

  Widget _row(String label, String value, {Color? valueColor}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 2,
            child: Text(label, style: const TextStyle(color: Colors.black54)),
          ),
          Expanded(
            flex: 3,
            child: Text(
              value,
              style: TextStyle(color: valueColor),
            ),
          ),
        ],
      ),
    );
  }
}
