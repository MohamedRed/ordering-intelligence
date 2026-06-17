import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../providers/dispatch_api.dart';
import 'dispatch_filter_chips.dart';
import 'dispatch_helpers.dart';
import 'dispatch_models.dart';

class DispatchRoutesCard extends StatelessWidget {
  const DispatchRoutesCard({
    super.key,
    required this.routes,
    required this.drivers,
    required this.statusFilter,
    required this.onStatusFilterChanged,
  });

  final List<DispatchRoute> routes;
  final List<DispatchDriver> drivers;
  final String statusFilter;
  final ValueChanged<String> onStatusFilterChanged;

  @override
  Widget build(BuildContext context) {
    final filtered = filteredDispatchRoutes(routes, statusFilter);
    return ShadCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Active routes', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          DispatchFilterChips(
            options: const [
              'all',
              'planned',
              'in_progress',
              'completed',
              'cancelled'
            ],
            selected: statusFilter,
            onSelected: onStatusFilterChanged,
            replaceUnderscores: true,
          ),
          const SizedBox(height: 8),
          if (filtered.isEmpty)
            const Text('No active routes.')
          else
            for (final route in filtered)
              ListTile(
                title: Text(route.id),
                subtitle: Text(
                  'Driver: ${dispatchDriverLabel(drivers, route.driverId)} • ${route.deliveryIds.length} stops',
                ),
                trailing: Text(route.status.isEmpty
                    ? 'unknown'
                    : route.status.toUpperCase()),
              ),
        ],
      ),
    );
  }
}
