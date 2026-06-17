import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../providers/dispatch_api.dart';
import 'dispatch_filter_chips.dart';
import 'dispatch_helpers.dart';
import 'dispatch_models.dart';

class DispatchAssignmentsCard extends StatelessWidget {
  const DispatchAssignmentsCard({
    super.key,
    required this.assignments,
    required this.drivers,
    required this.statusFilter,
    required this.onStatusFilterChanged,
  });

  final List<DispatchAssignment> assignments;
  final List<DispatchDriver> drivers;
  final String statusFilter;
  final ValueChanged<String> onStatusFilterChanged;

  @override
  Widget build(BuildContext context) {
    final filtered = filteredDispatchAssignments(assignments, statusFilter);
    return ShadCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Active assignments',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          DispatchFilterChips(
            options: const [
              'all',
              'pending',
              'assigned',
              'declined',
              'expired'
            ],
            selected: statusFilter,
            onSelected: onStatusFilterChanged,
          ),
          const SizedBox(height: 8),
          if (filtered.isEmpty)
            const Text('No assignments yet.')
          else
            for (final assignment in filtered)
              ListTile(
                title: Text(
                  assignment.orderId.isNotEmpty
                      ? assignment.orderId
                      : assignment.id,
                ),
                subtitle: Text(
                  'Status: ${assignment.status.isEmpty ? 'unknown' : assignment.status} • Driver: ${dispatchDriverLabel(drivers, assignment.driverId)}',
                ),
                trailing: Text(dispatchAssignmentEta(assignment)),
              ),
        ],
      ),
    );
  }
}
