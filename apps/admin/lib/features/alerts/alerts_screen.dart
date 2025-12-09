import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/alert_providers.dart';
import '../../widgets/admin_navigation_drawer.dart';

class AlertsScreen extends ConsumerWidget {
  const AlertsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final alertsAsync = ref.watch(alertsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Alerts')),
      drawer: const AdminNavigationDrawer(),
      body: alertsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => Center(child: Text('Failed to load alerts: $err')),
        data: (alerts) {
          if (alerts.isEmpty) {
            return const Center(child: Text('No alerts.'));
          }
          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(alertsProvider),
            child: ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: alerts.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (_, index) {
                final alert = alerts[index];
                return Card(
                  child: ListTile(
                    leading: Icon(
                      Icons.notifications_active_outlined,
                      color: _color(alert.severity),
                    ),
                    title: Text(alert.title),
                    subtitle: Text(alert.body),
                    trailing: Text(
                      _format(alert.createdAt),
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }

  Color _color(String severity) {
    switch (severity) {
      case 'warning':
        return Colors.orange;
      case 'error':
        return Colors.red;
      default:
        return Colors.blueGrey;
    }
  }

  String _format(DateTime dt) {
    return '${dt.month}/${dt.day} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }
}
