import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../services/dispatch_api.dart';
import '../services/fcm_token_manager.dart';
import '../services/location_service.dart';
import '../services/store_prefs.dart';

class DriverHomeScreen extends StatefulWidget {
  const DriverHomeScreen({super.key});

  @override
  State<DriverHomeScreen> createState() => _DriverHomeScreenState();
}

class _DriverHomeScreenState extends State<DriverHomeScreen> {
  late DispatchDriverApi _api;
  late LocationService _locationService;
  final _assignmentCtrl = TextEditingController();
  final _latCtrl = TextEditingController();
  final _lngCtrl = TextEditingController();
  final _accuracyCtrl = TextEditingController(text: '10');

  String _shiftStatus = 'off_shift';
  DispatchRoute? _route;
  bool _autoLocation = false;
  double? _lastLat;
  double? _lastLng;
  double? _lastAccuracy;
  DateTime? _lastSentAt;
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final storeId = StorePrefs.instance.storeId();
    _api = DispatchDriverApi(storeId: storeId);
    _locationService = LocationService(
      api: _api,
      onPosition: (pos) {
        if (!mounted) return;
        setState(() {
          _lastLat = pos.latitude;
          _lastLng = pos.longitude;
          _lastAccuracy = pos.accuracy;
        });
      },
      onSent: (pos) {
        if (!mounted) return;
        setState(() => _lastSentAt = DateTime.now().toUtc());
      },
      onError: (msg) {
        if (!mounted) return;
        setState(() => _error = msg);
      },
    );
    _initFcm(storeId);
    _refreshRoute();
  }

  Future<void> _initFcm(String storeId) async {
    final token = await fetchFcmToken();
    if (token != null && token.trim().isNotEmpty) {
      await registerTokenWithBackend(token: token, storeId: storeId);
    }
  }

  @override
  void dispose() {
    _assignmentCtrl.dispose();
    _latCtrl.dispose();
    _lngCtrl.dispose();
    _accuracyCtrl.dispose();
    _locationService.stop();
    super.dispose();
  }

  Future<void> _updateShift(String status) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _api.updateShift(status);
      setState(() => _shiftStatus = status);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _refreshRoute() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final route = await _api.getCurrentRoute();
      setState(() => _route = route);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _sendLocation() async {
    final lat = double.tryParse(_latCtrl.text.trim());
    final lng = double.tryParse(_lngCtrl.text.trim());
    final acc = double.tryParse(_accuracyCtrl.text.trim()) ?? 0;
    if (lat == null || lng == null) {
      setState(() => _error = 'Enter valid lat/lng');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _api.postLocation(lat: lat, lng: lng, accuracyM: acc);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _toggleAutoLocation(bool enabled) async {
    if (enabled) {
      final ok = await _locationService.start();
      if (!ok) {
        if (mounted) setState(() => _autoLocation = false);
        return;
      }
    } else {
      await _locationService.stop();
    }
    if (mounted) setState(() => _autoLocation = enabled);
  }

  Future<void> _handleAssignment(bool accept) async {
    final assignmentId = _assignmentCtrl.text.trim();
    if (assignmentId.isEmpty) {
      setState(() => _error = 'Enter assignment id');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (accept) {
        await _api.acceptAssignment(assignmentId);
      } else {
        await _api.declineAssignment(assignmentId);
      }
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _updateStopStatus(String deliveryId, String status) async {
    final route = _route;
    if (route == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _api.updateStopStatus(
        routeId: route.id,
        deliveryId: deliveryId,
        status: status,
      );
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final storeId = StorePrefs.instance.storeId();
    return Scaffold(
      appBar: AppBar(
        title: Text('Driver · $storeId'),
        actions: [
          IconButton(
            onPressed: _busy ? null : _refreshRoute,
            icon: const Icon(Icons.refresh),
          ),
          IconButton(
            onPressed: () => FirebaseAuth.instance.signOut(),
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(_error!, style: const TextStyle(color: Colors.red)),
            ),
          _sectionTitle('Shift'),
          Wrap(
            spacing: 12,
            children: [
              _shiftButton('Start', 'start'),
              _shiftButton('Pause', 'pause'),
              _shiftButton('End', 'end'),
              Chip(label: Text('Status: $_shiftStatus')),
            ],
          ),
          const SizedBox(height: 16),
          _sectionTitle('Assignment'),
          TextField(
            controller: _assignmentCtrl,
            decoration: const InputDecoration(
              labelText: 'Assignment ID',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: ElevatedButton(
                  onPressed: _busy ? null : () => _handleAssignment(true),
                  child: const Text('Accept'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton(
                  onPressed: _busy ? null : () => _handleAssignment(false),
                  child: const Text('Decline'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _sectionTitle('Location'),
          SwitchListTile.adaptive(
            value: _autoLocation,
            onChanged: _busy ? null : _toggleAutoLocation,
            title: const Text('Auto location updates'),
            subtitle: Text(
              _autoLocation
                  ? 'Streaming location every ~30s'
                  : 'Manual location updates',
            ),
          ),
          if (_lastLat != null && _lastLng != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                'Last position: ${_lastLat!.toStringAsFixed(5)}, '
                '${_lastLng!.toStringAsFixed(5)} '
                '±${(_lastAccuracy ?? 0).toStringAsFixed(1)}m'
                '${_lastSentAt != null ? ' · sent ${_lastSentAt!.toIso8601String()}' : ''}',
              ),
            ),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _latCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Lat',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _lngCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Lng',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _accuracyCtrl,
            decoration: const InputDecoration(
              labelText: 'Accuracy (m)',
              border: OutlineInputBorder(),
            ),
            keyboardType: TextInputType.number,
          ),
          const SizedBox(height: 8),
          ElevatedButton(
            onPressed: _busy ? null : _sendLocation,
            child: const Text('Send location'),
          ),
          const SizedBox(height: 16),
          _sectionTitle('Current route'),
          if (_route == null)
            const Text('No active route')
          else
            _routeCard(_route!),
        ],
      ),
    );
  }

  Widget _sectionTitle(String label) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        label,
        style: Theme.of(
          context,
        ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
      ),
    );
  }

  Widget _shiftButton(String label, String action) {
    return ElevatedButton(
      onPressed: _busy
          ? null
          : () {
              switch (action) {
                case 'start':
                  _updateShift('start');
                  break;
                case 'pause':
                  _updateShift('pause');
                  break;
                case 'end':
                  _updateShift('end');
                  break;
              }
            },
      child: Text(label),
    );
  }

  Widget _routeCard(DispatchRoute route) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Route: ${route.id}',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 4),
            Text('Status: ${route.status}'),
            const SizedBox(height: 8),
            ...route.deliveryIds.map(
              (deliveryId) => _stopRow(route, deliveryId),
            ),
          ],
        ),
      ),
    );
  }

  Widget _stopRow(DispatchRoute route, String deliveryId) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Delivery: $deliveryId'),
          const SizedBox(height: 4),
          Wrap(
            spacing: 8,
            children: [
              OutlinedButton(
                onPressed: _busy
                    ? null
                    : () => _updateStopStatus(deliveryId, 'picked_up'),
                child: const Text('Picked up'),
              ),
              OutlinedButton(
                onPressed: _busy
                    ? null
                    : () => _updateStopStatus(deliveryId, 'out_for_delivery'),
                child: const Text('Out for delivery'),
              ),
              OutlinedButton(
                onPressed: _busy
                    ? null
                    : () => _updateStopStatus(deliveryId, 'delivered'),
                child: const Text('Delivered'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
