import 'package:flutter_test/flutter_test.dart';

import 'package:business_app/features/dispatch/dispatch_helpers.dart';
import 'package:business_app/features/dispatch/dispatch_models.dart';
import 'package:business_app/providers/dispatch_api.dart';

void main() {
  test('dispatch helpers filter drivers by active and shift state', () {
    final drivers = [
      const DispatchDriver(
        id: 'driver-1',
        displayName: 'Ana',
        phoneE164: '+10000000001',
        active: true,
        maxActiveStops: 3,
        uid: 'uid-1',
      ),
      const DispatchDriver(
        id: 'driver-2',
        displayName: '',
        phoneE164: '+10000000002',
        active: false,
        maxActiveStops: 2,
        uid: '',
      ),
    ];
    final shifts = {
      'uid-1': DriverShiftInfo(
        status: 'on_shift',
        updatedAt: DateTime(2026, 6, 17, 9, 30),
      ),
    };

    expect(
      filteredDispatchDrivers(
        drivers: drivers,
        shifts: shifts,
        shiftFilter: 'on_shift',
        activeOnly: true,
      ).single.id,
      'driver-1',
    );
    expect(
      filteredDispatchDrivers(
        drivers: drivers,
        shifts: shifts,
        shiftFilter: 'unclaimed',
        activeOnly: false,
      ).single.id,
      'driver-2',
    );
    expect(dispatchDriverLabel(drivers, 'uid-1'), 'Ana');
    expect(dispatchDriverLabel(drivers, ''), 'unassigned');
  });

  test('dispatch helpers filter assignments, routes, and ETA labels', () {
    final expiresAt = DateTime(2026, 6, 17, 10, 5);
    final assignments = [
      DispatchAssignment(
        id: 'assignment-1',
        orderId: 'order-1',
        driverId: 'uid-1',
        status: 'assigned',
        expiresAt: expiresAt,
        updatedAt: null,
        candidates: const [
          {'driverId': 'uid-1', 'etaToPickupSecs': 540},
        ],
      ),
      const DispatchAssignment(
        id: 'assignment-2',
        orderId: 'order-2',
        driverId: '',
        status: 'pending',
        expiresAt: null,
        updatedAt: null,
        candidates: [],
      ),
    ];
    final routes = [
      const DispatchRoute(
        id: 'route-1',
        driverId: 'uid-1',
        status: 'planned',
        deliveryIds: ['delivery-1'],
        updatedAt: null,
      ),
      const DispatchRoute(
        id: 'route-2',
        driverId: 'uid-2',
        status: 'completed',
        deliveryIds: [],
        updatedAt: null,
      ),
    ];

    expect(filteredDispatchAssignments(assignments, 'assigned'), [
      assignments.first,
    ]);
    expect(filteredDispatchRoutes(routes, 'completed'), [routes.last]);
    expect(dispatchAssignmentEta(assignments.first), '~9 min');
    expect(formatDispatchTime(expiresAt), '2026-06-17 10:05');
    expect(readDispatchNum('12.5'), 12.5);
  });
}
