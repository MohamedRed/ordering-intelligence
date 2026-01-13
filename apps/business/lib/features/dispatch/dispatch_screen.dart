import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../providers/dispatch_api.dart';
import '../../util/store_id.dart';
import '../../widgets/business_scaffold.dart';
import '../../widgets/shad_snackbar.dart';

class _DriverShiftInfo {
  const _DriverShiftInfo({required this.status, required this.updatedAt});
  final String status;
  final DateTime? updatedAt;
}

class _DriverLocationInfo {
  const _DriverLocationInfo({
    required this.lat,
    required this.lng,
    required this.accuracyM,
    required this.recordedAt,
  });
  final double lat;
  final double lng;
  final double accuracyM;
  final DateTime? recordedAt;
}

class _DispatchAssignment {
  const _DispatchAssignment({
    required this.id,
    required this.orderId,
    required this.driverId,
    required this.status,
    required this.expiresAt,
    required this.updatedAt,
    required this.candidates,
  });
  final String id;
  final String orderId;
  final String driverId;
  final String status;
  final DateTime? expiresAt;
  final DateTime? updatedAt;
  final List<Map<String, dynamic>> candidates;
}

class _DispatchRoute {
  const _DispatchRoute({
    required this.id,
    required this.driverId,
    required this.status,
    required this.deliveryIds,
    required this.updatedAt,
  });
  final String id;
  final String driverId;
  final String status;
  final List<String> deliveryIds;
  final DateTime? updatedAt;
}

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
  List<_DispatchAssignment> _assignments = const [];
  List<_DispatchRoute> _routes = const [];
  Map<String, _DriverShiftInfo> _shifts = const {};
  Map<String, _DriverLocationInfo> _locations = const {};
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
      final results = await Future.wait([
        _api.listDrivers(),
        _fetchAssignments(storeId),
        _fetchRoutes(storeId),
        _fetchShifts(storeId),
        _fetchLocations(storeId),
      ]);
      if (!mounted) return;
      setState(() {
        _drivers = results[0] as List<DispatchDriver>;
        _assignments = results[1] as List<_DispatchAssignment>;
        _routes = results[2] as List<_DispatchRoute>;
        _shifts = results[3] as Map<String, _DriverShiftInfo>;
        _locations = results[4] as Map<String, _DriverLocationInfo>;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<List<_DispatchAssignment>> _fetchAssignments(String storeId) async {
    final snap = await FirebaseFirestore.instance
        .collection('stores')
        .doc(storeId)
        .collection('driver_assignments')
        .orderBy('updatedAt', descending: true)
        .limit(25)
        .get();
    return snap.docs.map((doc) {
      final data = doc.data();
      final candidatesRaw = data['candidates'];
      final candidates = candidatesRaw is List
          ? candidatesRaw
              .whereType<Map>()
              .map((e) => e.cast<String, dynamic>())
              .toList()
          : <Map<String, dynamic>>[];
      return _DispatchAssignment(
        id: doc.id,
        orderId: (data['orderId'] as String?)?.trim() ?? '',
        driverId: (data['driverId'] as String?)?.trim() ?? '',
        status: (data['status'] as String?)?.trim() ?? '',
        expiresAt: _readTime(data['expiresAt']),
        updatedAt: _readTime(data['updatedAt']),
        candidates: candidates,
      );
    }).toList(growable: false);
  }

  Future<List<_DispatchRoute>> _fetchRoutes(String storeId) async {
    final snap = await FirebaseFirestore.instance
        .collection('stores')
        .doc(storeId)
        .collection('driver_routes')
        .orderBy('updatedAt', descending: true)
        .limit(25)
        .get();
    return snap.docs.map((doc) {
      final data = doc.data();
      final deliveriesRaw = data['deliveryIds'];
      final deliveries = deliveriesRaw is List
          ? deliveriesRaw.map((e) => e.toString()).toList()
          : const <String>[];
      return _DispatchRoute(
        id: doc.id,
        driverId: (data['driverId'] as String?)?.trim() ?? '',
        status: (data['status'] as String?)?.trim() ?? '',
        deliveryIds: deliveries,
        updatedAt: _readTime(data['updatedAt']),
      );
    }).toList(growable: false);
  }

  Future<Map<String, _DriverShiftInfo>> _fetchShifts(String storeId) async {
    final snap = await FirebaseFirestore.instance
        .collection('stores')
        .doc(storeId)
        .collection('driver_shifts')
        .get();
    final out = <String, _DriverShiftInfo>{};
    for (final doc in snap.docs) {
      final data = doc.data();
      out[doc.id] = _DriverShiftInfo(
        status: (data['status'] as String?)?.trim() ?? '',
        updatedAt: _readTime(data['updatedAt']),
      );
    }
    return out;
  }

  Future<Map<String, _DriverLocationInfo>> _fetchLocations(
      String storeId) async {
    final snap = await FirebaseFirestore.instance
        .collection('stores')
        .doc(storeId)
        .collection('driver_locations')
        .get();
    final out = <String, _DriverLocationInfo>{};
    for (final doc in snap.docs) {
      final data = doc.data();
      final lat = _readNum(data['lat']);
      final lng = _readNum(data['lng']);
      final accuracy = _readNum(data['accuracyM']);
      out[doc.id] = _DriverLocationInfo(
        lat: lat,
        lng: lng,
        accuracyM: accuracy,
        recordedAt: _readTime(data['recordedAt']),
      );
    }
    return out;
  }

  Future<void> _addDriver() async {
    final nameCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();
    final stopsCtrl = TextEditingController(text: '3');
    try {
      final ok = await showDialog<bool>(
        context: context,
        builder: (context) {
          return AlertDialog(
            title: const Text('Add driver'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(labelText: 'Display name'),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: phoneCtrl,
                  decoration: const InputDecoration(labelText: 'Phone (E.164)'),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: stopsCtrl,
                  decoration:
                      const InputDecoration(labelText: 'Max active stops'),
                  keyboardType: TextInputType.number,
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Create'),
              ),
            ],
          );
        },
      );
      if (!mounted) return;
      if (ok != true) return;

      final name = nameCtrl.text.trim();
      final phone = phoneCtrl.text.trim();
      final stops = int.tryParse(stopsCtrl.text.trim()) ?? 3;
      if (name.isEmpty || phone.isEmpty) {
        showShadSnack(
          context,
          title: 'Missing fields',
          message: 'Name and phone are required.',
          type: ShadSnackType.error,
        );
        return;
      }
      await _api.createDriver(
        displayName: name,
        phoneE164: phone,
        maxActiveStops: stops,
      );
      if (!mounted) return;
      showShadSnack(
        context,
        title: 'Driver added',
        message: name,
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
    } finally {
      nameCtrl.dispose();
      phoneCtrl.dispose();
      stopsCtrl.dispose();
    }
  }

  Future<void> _toggleActive(DispatchDriver d, bool active) async {
    try {
      await _api.setDriverActive(d.id, active);
      if (!mounted) return;
      setState(() {
        _drivers = _drivers
            .map((x) => x.id == d.id
                ? DispatchDriver(
                    id: x.id,
                    displayName: x.displayName,
                    phoneE164: x.phoneE164,
                    active: active,
                    maxActiveStops: x.maxActiveStops,
                    uid: x.uid,
                  )
                : x)
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
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!))
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    ShadCard(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Drivers',
                              style: Theme.of(context).textTheme.titleMedium),
                          const SizedBox(height: 8),
                          _buildDriverFilters(),
                          const SizedBox(height: 8),
                          if (_drivers.isEmpty)
                            const Text(
                                'No drivers yet. Add one to get started.')
                          else
                            ..._filteredDrivers().map((d) => ListTile(
                                  title: Text(d.displayName.isNotEmpty
                                      ? d.displayName
                                      : d.id),
                                  subtitle: _buildDriverMeta(d),
                                  trailing: Switch(
                                    value: d.active,
                                    onChanged: (v) => _toggleActive(d, v),
                                  ),
                                )),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    _buildAssignmentsCard(context),
                    const SizedBox(height: 12),
                    _buildRoutesCard(context),
                  ],
                ),
    );
  }

  Widget _buildDriverMeta(DispatchDriver d) {
    final uid = d.uid;
    final shift = uid.isNotEmpty ? _shifts[uid] : null;
    final location = uid.isNotEmpty ? _locations[uid] : null;
    final rows = <Widget>[
      Text('${d.phoneE164} • max stops ${d.maxActiveStops}'),
    ];
    if (uid.isEmpty) {
      rows.add(const Text('Unclaimed • no driver app user linked'));
    } else if (shift != null) {
      rows.add(Text(
          'Shift: ${shift.status.isEmpty ? 'unknown' : shift.status} • ${_fmtTime(shift.updatedAt)}'));
    }
    if (location != null && (location.lat != 0 || location.lng != 0)) {
      rows.add(Text(
          'Loc: ${location.lat.toStringAsFixed(4)}, ${location.lng.toStringAsFixed(4)} • ±${location.accuracyM.toStringAsFixed(0)}m'));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: rows,
    );
  }

  Widget _buildDriverFilters() {
    const shiftOptions = [
      'all',
      'on_shift',
      'paused',
      'off_shift',
      'unclaimed'
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 6,
          children: shiftOptions
              .map((opt) => ChoiceChip(
                    label: Text(opt.replaceAll('_', ' ').toUpperCase()),
                    selected: _driverShiftFilter == opt,
                    onSelected: (_) => setState(() => _driverShiftFilter = opt),
                  ))
              .toList(),
        ),
        const SizedBox(height: 6),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Active drivers only'),
          value: _activeDriversOnly,
          onChanged: (v) => setState(() => _activeDriversOnly = v),
        ),
      ],
    );
  }

  List<DispatchDriver> _filteredDrivers() {
    final shiftFilter = _driverShiftFilter;
    return _drivers.where((d) {
      if (_activeDriversOnly && !d.active) return false;
      if (shiftFilter == 'all') return true;
      final uid = d.uid.trim();
      if (shiftFilter == 'unclaimed') return uid.isEmpty;
      if (uid.isEmpty) return false;
      final status = _shifts[uid]?.status ?? '';
      return status == shiftFilter;
    }).toList(growable: false);
  }

  Widget _buildAssignmentsCard(BuildContext context) {
    final filtered = _filteredAssignments();
    return ShadCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Active assignments',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          _buildAssignmentFilters(),
          const SizedBox(height: 8),
          if (filtered.isEmpty)
            const Text('No assignments yet.')
          else
            ...filtered.map((a) => ListTile(
                  title: Text(a.orderId.isNotEmpty ? a.orderId : a.id),
                  subtitle: Text(
                      'Status: ${a.status.isEmpty ? 'unknown' : a.status} • Driver: ${_driverLabel(a.driverId)}'),
                  trailing: Text(_assignmentEta(a)),
                )),
        ],
      ),
    );
  }

  Widget _buildRoutesCard(BuildContext context) {
    final filtered = _filteredRoutes();
    return ShadCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Active routes', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          _buildRouteFilters(),
          const SizedBox(height: 8),
          if (filtered.isEmpty)
            const Text('No active routes.')
          else
            ...filtered.map((r) => ListTile(
                  title: Text(r.id),
                  subtitle: Text(
                      'Driver: ${_driverLabel(r.driverId)} • ${r.deliveryIds.length} stops'),
                  trailing: Text(
                      r.status.isEmpty ? 'unknown' : r.status.toUpperCase()),
                )),
        ],
      ),
    );
  }

  String _driverLabel(String uid) {
    if (uid.isEmpty) return 'unassigned';
    final match = _drivers.where((d) => d.uid == uid).toList();
    if (match.isNotEmpty) {
      final d = match.first;
      return d.displayName.isNotEmpty ? d.displayName : d.id;
    }
    return uid;
  }

  String _assignmentEta(_DispatchAssignment a) {
    if (a.driverId.isEmpty || a.candidates.isEmpty) {
      return _fmtTime(a.expiresAt);
    }
    final match = a.candidates.firstWhere(
      (c) => (c['driverId'] as String?)?.trim() == a.driverId,
      orElse: () => const <String, dynamic>{},
    );
    final etaSecs = _readNum(match['etaToPickupSecs']).toInt();
    if (etaSecs <= 0) {
      return _fmtTime(a.expiresAt);
    }
    final mins = (etaSecs / 60).round();
    return '~$mins min';
  }

  Widget _buildAssignmentFilters() {
    const options = ['all', 'pending', 'assigned', 'declined', 'expired'];
    return Wrap(
      spacing: 8,
      runSpacing: 6,
      children: options
          .map((opt) => ChoiceChip(
                label: Text(opt.toUpperCase()),
                selected: _assignmentStatusFilter == opt,
                onSelected: (_) =>
                    setState(() => _assignmentStatusFilter = opt),
              ))
          .toList(),
    );
  }

  Widget _buildRouteFilters() {
    const options = ['all', 'planned', 'in_progress', 'completed', 'cancelled'];
    return Wrap(
      spacing: 8,
      runSpacing: 6,
      children: options
          .map((opt) => ChoiceChip(
                label: Text(opt.replaceAll('_', ' ').toUpperCase()),
                selected: _routeStatusFilter == opt,
                onSelected: (_) => setState(() => _routeStatusFilter = opt),
              ))
          .toList(),
    );
  }

  List<_DispatchAssignment> _filteredAssignments() {
    if (_assignmentStatusFilter == 'all') return _assignments;
    return _assignments
        .where((a) => a.status == _assignmentStatusFilter)
        .toList(growable: false);
  }

  List<_DispatchRoute> _filteredRoutes() {
    if (_routeStatusFilter == 'all') return _routes;
    return _routes
        .where((r) => r.status == _routeStatusFilter)
        .toList(growable: false);
  }

  static DateTime? _readTime(dynamic value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    if (value is String) return DateTime.tryParse(value);
    return null;
  }

  static double _readNum(dynamic value) {
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value) ?? 0;
    return 0;
  }

  static String _fmtTime(DateTime? time) {
    if (time == null) return '';
    final local = time.toLocal();
    final date =
        '${local.year.toString().padLeft(4, '0')}-${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')}';
    final clock =
        '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
    return '$date $clock';
  }
}
