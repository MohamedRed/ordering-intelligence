import 'package:flutter/material.dart';

import '../../providers/dispatch_api.dart';
import '../../util/store_id.dart';
import '../../widgets/business_scaffold.dart';
import '../../widgets/shad_snackbar.dart';
import 'dispatch_add_driver_dialog.dart';
import 'dispatch_assignments_card.dart';
import 'dispatch_firestore_queries.dart';
import 'dispatch_models.dart';
import 'dispatch_routes_card.dart';
import 'dispatch_drivers_card.dart';

class DispatchScreen extends StatefulWidget {
  const DispatchScreen({super.key});

  @override
  State<DispatchScreen> createState() => _DispatchScreenState();
}

class _DispatchScreenState extends State<DispatchScreen> {
  final _api = DispatchApi();
  bool _loading = true;
  String? _error;
  List<DispatchDriver> _drivers = const [];
  List<DispatchAssignment> _assignments = const [];
  List<DispatchRoute> _routes = const [];
  Map<String, DriverShiftInfo> _shifts = const {};
  Map<String, DriverLocationInfo> _locations = const {};
  String _driverShiftFilter = 'all';
  bool _activeDriversOnly = false;
  String _assignmentStatusFilter = 'all';
  String _routeStatusFilter = 'all';

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final storeId = effectiveStoreId();
      final results = await Future.wait<dynamic>([
        _api.listDrivers(),
        fetchDispatchAssignments(storeId),
        fetchDispatchRoutes(storeId),
        fetchDriverShifts(storeId),
        fetchDriverLocations(storeId),
      ]);
      if (!mounted) return;
      setState(() {
        _drivers = results[0] as List<DispatchDriver>;
        _assignments = results[1] as List<DispatchAssignment>;
        _routes = results[2] as List<DispatchRoute>;
        _shifts = results[3] as Map<String, DriverShiftInfo>;
        _locations = results[4] as Map<String, DriverLocationInfo>;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _addDriver() async {
    try {
      final result = await showDispatchAddDriverDialog(context);
      if (!mounted || result == null) return;
      if (result.displayName.isEmpty || result.phoneE164.isEmpty) {
        showShadSnack(
          context,
          title: 'Missing fields',
          message: 'Name and phone are required.',
          type: ShadSnackType.error,
        );
        return;
      }
      await _api.createDriver(
        displayName: result.displayName,
        phoneE164: result.phoneE164,
        maxActiveStops: result.maxActiveStops,
      );
      if (!mounted) return;
      showShadSnack(
        context,
        title: 'Driver added',
        message: result.displayName,
        type: ShadSnackType.success,
      );
      await _reload();
    } catch (e) {
      if (!mounted) return;
      showShadSnack(
        context,
        title: 'Create failed',
        message: '$e',
        type: ShadSnackType.error,
      );
    }
  }

  Future<void> _toggleActive(DispatchDriver driver, bool active) async {
    try {
      await _api.setDriverActive(driver.id, active);
      if (!mounted) return;
      setState(() {
        _drivers = _drivers
            .map((candidate) => candidate.id == driver.id
                ? DispatchDriver(
                    id: candidate.id,
                    displayName: candidate.displayName,
                    phoneE164: candidate.phoneE164,
                    active: active,
                    maxActiveStops: candidate.maxActiveStops,
                    uid: candidate.uid,
                  )
                : candidate)
            .toList();
      });
    } catch (e) {
      if (!mounted) return;
      showShadSnack(
        context,
        title: 'Update failed',
        message: '$e',
        type: ShadSnackType.error,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return BusinessScaffold(
      title: const Text('Delivery & dispatch'),
      actions: [
        IconButton(
          tooltip: 'Refresh',
          onPressed: _loading ? null : _reload,
          icon: const Icon(Icons.refresh),
        ),
        IconButton(
          tooltip: 'Add driver',
          onPressed: _loading ? null : _addDriver,
          icon: const Icon(Icons.person_add_alt_1),
        ),
      ],
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    final error = _error;
    if (error != null) return Center(child: Text(error));

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        DispatchDriversCard(
          drivers: _drivers,
          shifts: _shifts,
          locations: _locations,
          shiftFilter: _driverShiftFilter,
          activeOnly: _activeDriversOnly,
          onShiftFilterChanged: (value) =>
              setState(() => _driverShiftFilter = value),
          onActiveOnlyChanged: (value) =>
              setState(() => _activeDriversOnly = value),
          onActiveChanged: _toggleActive,
        ),
        const SizedBox(height: 12),
        DispatchAssignmentsCard(
          assignments: _assignments,
          drivers: _drivers,
          statusFilter: _assignmentStatusFilter,
          onStatusFilterChanged: (value) =>
              setState(() => _assignmentStatusFilter = value),
        ),
        const SizedBox(height: 12),
        DispatchRoutesCard(
          routes: _routes,
          drivers: _drivers,
          statusFilter: _routeStatusFilter,
          onStatusFilterChanged: (value) =>
              setState(() => _routeStatusFilter = value),
        ),
      ],
    );
  }
}
