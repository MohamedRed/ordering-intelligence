import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../providers/dispatch_api.dart';
import 'dispatch_filter_chips.dart';
import 'dispatch_helpers.dart';
import 'dispatch_models.dart';

class DispatchDriversCard extends StatelessWidget {
  const DispatchDriversCard({
    super.key,
    required this.drivers,
    required this.shifts,
    required this.locations,
    required this.shiftFilter,
    required this.activeOnly,
    required this.onShiftFilterChanged,
    required this.onActiveOnlyChanged,
    required this.onActiveChanged,
  });

  final List<DispatchDriver> drivers;
  final Map<String, DriverShiftInfo> shifts;
  final Map<String, DriverLocationInfo> locations;
  final String shiftFilter;
  final bool activeOnly;
  final ValueChanged<String> onShiftFilterChanged;
  final ValueChanged<bool> onActiveOnlyChanged;
  final void Function(DispatchDriver driver, bool active) onActiveChanged;

  @override
  Widget build(BuildContext context) {
    final filtered = filteredDispatchDrivers(
      drivers: drivers,
      shifts: shifts,
      shiftFilter: shiftFilter,
      activeOnly: activeOnly,
    );

    return ShadCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Drivers', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          DispatchFilterChips(
            options: const [
              'all',
              'on_shift',
              'paused',
              'off_shift',
              'unclaimed'
            ],
            selected: shiftFilter,
            onSelected: onShiftFilterChanged,
            replaceUnderscores: true,
          ),
          const SizedBox(height: 6),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Active drivers only'),
            value: activeOnly,
            onChanged: onActiveOnlyChanged,
          ),
          if (drivers.isEmpty)
            const Text('No drivers yet. Add one to get started.')
          else if (filtered.isEmpty)
            const Text('No drivers match the selected filters.')
          else
            for (final driver in filtered)
              ListTile(
                title: Text(
                  driver.displayName.isNotEmpty
                      ? driver.displayName
                      : driver.id,
                ),
                subtitle: _DriverMeta(
                  driver: driver,
                  shift: driver.uid.isNotEmpty ? shifts[driver.uid] : null,
                  location:
                      driver.uid.isNotEmpty ? locations[driver.uid] : null,
                ),
                trailing: Switch(
                  value: driver.active,
                  onChanged: (value) => onActiveChanged(driver, value),
                ),
              ),
        ],
      ),
    );
  }
}

class _DriverMeta extends StatelessWidget {
  const _DriverMeta({
    required this.driver,
    required this.shift,
    required this.location,
  });

  final DispatchDriver driver;
  final DriverShiftInfo? shift;
  final DriverLocationInfo? location;

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[
      Text('${driver.phoneE164} • max stops ${driver.maxActiveStops}'),
    ];
    if (driver.uid.isEmpty) {
      rows.add(const Text('Unclaimed • no driver app user linked'));
    } else if (shift != null) {
      rows.add(
        Text(
          'Shift: ${shift!.status.isEmpty ? 'unknown' : shift!.status} • ${formatDispatchTime(shift!.updatedAt)}',
        ),
      );
    }
    if (location != null && (location!.lat != 0 || location!.lng != 0)) {
      rows.add(
        Text(
          'Loc: ${location!.lat.toStringAsFixed(4)}, ${location!.lng.toStringAsFixed(4)} • ±${location!.accuracyM.toStringAsFixed(0)}m',
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: rows,
    );
  }
}
