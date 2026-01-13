import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../util/store_id.dart';
import '../../widgets/business_scaffold.dart';
import '../../widgets/shad_snackbar.dart';
import 'delivery_settings_card.dart';

class StoreSettingsScreen extends StatefulWidget {
  const StoreSettingsScreen({super.key});

  @override
  State<StoreSettingsScreen> createState() => _StoreSettingsScreenState();
}

class _TemplateRow {
  _TemplateRow({required String id, String label = '', String body = ''})
      : id = TextEditingController(text: id),
        label = TextEditingController(text: label),
        body = TextEditingController(text: body);

  final TextEditingController id;
  final TextEditingController label;
  final TextEditingController body;

  void dispose() {
    id.dispose();
    label.dispose();
    body.dispose();
  }
}

class _StoreSettingsScreenState extends State<StoreSettingsScreen> {
  final _statuses = const [
    'pending',
    'confirmed',
    'ready',
    'completed',
    'cancelled',
    'delay',
  ];
  final _deliveryStatuses = const [
    'delivery_assigned',
    'picked_up',
    'out_for_delivery',
    'arriving_soon',
    'delivered',
    'delivery_failed',
  ];
  final _channels = const ['none', 'sms', 'call'];

  bool _loading = true;
  bool _saving = false;

  final Map<String, String> _defaultChannelByStatus = {};
  final Map<String, String> _defaultTemplateIdByStatus = {};
  final Map<String, List<_TemplateRow>> _templatesByStatus = {};
  final Map<String, String> _deliveryDefaultChannelByStatus = {};
  final Map<String, String> _deliveryDefaultTemplateIdByStatus = {};
  final Map<String, List<_TemplateRow>> _deliveryTemplatesByStatus = {};

  bool _readyEscalationEnabled = false;
  int _readyEscalationMinutes = 5;
  String _readyEscalationChannel = 'call';
  int _defaultWaitMinutes = 15;
  final TextEditingController _defaultWaitCtrl = TextEditingController();

  bool _deliveryEnabled = false;
  String _deliveryFleetMode = 'owned_fleet';
  final TextEditingController _storeLatCtrl = TextEditingController();
  final TextEditingController _storeLngCtrl = TextEditingController();
  final TextEditingController _storeAddressCtrl = TextEditingController();
  final TextEditingController _marketplaceOfferCtrl = TextEditingController();
  bool _deliveryArrivingSoonEnabled = false;
  int _deliveryArrivingSoonMinutes = 3;
  int _deliveryRateLimitPerHour = 3;
  int _marketplaceOfferCents = 300;

  String get _storeId => effectiveStoreId();

  @override
  void initState() {
    super.initState();
    _defaultWaitCtrl.text = _defaultWaitMinutes.toString();
    _load();
  }

  @override
  void dispose() {
    _defaultWaitCtrl.dispose();
    _storeLatCtrl.dispose();
    _storeLngCtrl.dispose();
    _storeAddressCtrl.dispose();
    _marketplaceOfferCtrl.dispose();
    for (final list in _templatesByStatus.values) {
      for (final row in list) {
        row.dispose();
      }
    }
    for (final list in _deliveryTemplatesByStatus.values) {
      for (final row in list) {
        row.dispose();
      }
    }
    super.dispose();
  }

  Map<String, dynamic> _defaultComms() {
    const defaults = {
      'pending': 'Your order was received.',
      'confirmed': 'Your order has been confirmed.',
      'ready': 'Your order is ready for pickup.',
      'completed': 'Thanks — your order is marked completed.',
      'cancelled':
          'Your order was cancelled. Please contact the store if you have questions.',
      'delay': 'Your order is running a bit late.',
    };

    final statuses = <String, dynamic>{};
    for (final s in _statuses) {
      statuses[s] = {
        'default_channel': 'none',
        'default_template_id': 'default',
        'templates': [
          {
            'id': 'default',
            'label': 'Default',
            'body': defaults[s] ?? 'Order status updated.'
          }
        ],
      };
    }
    return {
      'default_wait_minutes': 15,
      'statuses': statuses,
      'ready_escalation_enabled': false,
      'ready_escalation_minutes': 5,
      'ready_escalation_channel': 'call',
    };
  }

  Map<String, dynamic> _defaultDeliveryComms() {
    const defaults = {
      'delivery_assigned':
          'Your delivery is being prepared. A driver has been assigned.',
      'picked_up': 'Your order has been picked up and is on the way.',
      'out_for_delivery': 'Your order is out for delivery.',
      'arriving_soon': 'Your driver is nearby. Arriving soon.',
      'delivered': 'Delivered. Enjoy!',
      'delivery_failed':
          "We couldn't complete the delivery. Please contact the store.",
    };

    final statuses = <String, dynamic>{};
    for (final s in _deliveryStatuses) {
      statuses[s] = {
        'default_channel': 'none',
        'default_template_id': 'default',
        'templates': [
          {
            'id': 'default',
            'label': 'Default',
            'body': defaults[s] ?? 'Delivery status updated.'
          }
        ],
      };
    }
    return {
      'rate_limit_per_hour': 3,
      'arriving_soon_enabled': false,
      'arriving_soon_eta_threshold_minutes': 3,
      'statuses': statuses,
    };
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final snap = await FirebaseFirestore.instance
          .collection('stores')
          .doc(_storeId)
          .get();
      final data = snap.data() ?? <String, dynamic>{};
      final comms = (data['order_comms'] as Map?)?.cast<String, dynamic>() ??
          <String, dynamic>{};

      final delivery =
          (data['delivery_settings'] as Map?)?.cast<String, dynamic>() ??
              <String, dynamic>{};
      _deliveryEnabled = delivery['enabled'] == true;
      _deliveryFleetMode =
          (delivery['fleet_mode'] as String?)?.trim() ?? 'owned_fleet';
      final storeLoc =
          (delivery['store_location'] as Map?)?.cast<String, dynamic>() ??
              <String, dynamic>{};
      _storeLatCtrl.text = (storeLoc['lat'] ?? '').toString();
      _storeLngCtrl.text = (storeLoc['lng'] ?? '').toString();
      _storeAddressCtrl.text = (storeLoc['formatted'] as String?)?.trim() ?? '';
      final offer = delivery['marketplace_offer_cents'];
      _marketplaceOfferCents =
          offer is int ? offer : (offer is num ? offer.toInt() : 300);
      _marketplaceOfferCtrl.text = _marketplaceOfferCents.toString();

      final merged = _defaultComms();
      merged.addAll(comms);
      final statuses =
          (merged['statuses'] as Map?)?.cast<String, dynamic>() ?? {};

      for (final status in _statuses) {
        final cfg = (statuses[status] as Map?)?.cast<String, dynamic>() ?? {};
        _defaultChannelByStatus[status] =
            (cfg['default_channel'] as String?)?.trim() ?? 'none';
        _defaultTemplateIdByStatus[status] =
            (cfg['default_template_id'] as String?)?.trim() ?? 'default';

        final templatesRaw =
            (cfg['templates'] as List?)?.cast<dynamic>() ?? const [];
        final list = <_TemplateRow>[];
        for (final t in templatesRaw) {
          final m = (t as Map?)?.cast<String, dynamic>();
          if (m == null) continue;
          final id = (m['id'] as String?)?.trim() ?? '';
          if (id.isEmpty) continue;
          list.add(_TemplateRow(
            id: id,
            label: (m['label'] as String?)?.trim() ?? '',
            body: (m['body'] as String?)?.trim() ?? '',
          ));
        }
        if (list.isEmpty) {
          list.add(_TemplateRow(
              id: 'default', label: 'Default', body: 'Order status updated.'));
        }
        _templatesByStatus[status] = list;
      }

      _readyEscalationEnabled = merged['ready_escalation_enabled'] == true;
      final mins = merged['ready_escalation_minutes'];
      _readyEscalationMinutes =
          mins is int ? mins : (mins is num ? mins.toInt() : 5);
      _readyEscalationChannel =
          (merged['ready_escalation_channel'] as String?)?.trim() ?? 'call';

      final defWait = merged['default_wait_minutes'];
      _defaultWaitMinutes =
          defWait is int ? defWait : (defWait is num ? defWait.toInt() : 15);
      _defaultWaitCtrl.text = _defaultWaitMinutes.toString();

      final deliveryComms =
          (data['delivery_comms'] as Map?)?.cast<String, dynamic>() ??
              <String, dynamic>{};
      final mergedDelivery = _defaultDeliveryComms();
      mergedDelivery.addAll(deliveryComms);
      final deliveryStatuses =
          (mergedDelivery['statuses'] as Map?)?.cast<String, dynamic>() ?? {};
      for (final status in _deliveryStatuses) {
        final cfg =
            (deliveryStatuses[status] as Map?)?.cast<String, dynamic>() ?? {};
        _deliveryDefaultChannelByStatus[status] =
            (cfg['default_channel'] as String?)?.trim() ?? 'none';
        _deliveryDefaultTemplateIdByStatus[status] =
            (cfg['default_template_id'] as String?)?.trim() ?? 'default';

        final templatesRaw =
            (cfg['templates'] as List?)?.cast<dynamic>() ?? const [];
        final list = <_TemplateRow>[];
        for (final t in templatesRaw) {
          final m = (t as Map?)?.cast<String, dynamic>();
          if (m == null) continue;
          final id = (m['id'] as String?)?.trim() ?? '';
          if (id.isEmpty) continue;
          list.add(_TemplateRow(
            id: id,
            label: (m['label'] as String?)?.trim() ?? '',
            body: (m['body'] as String?)?.trim() ?? '',
          ));
        }
        if (list.isEmpty) {
          list.add(_TemplateRow(
              id: 'default',
              label: 'Default',
              body: 'Delivery status updated.'));
        }
        _deliveryTemplatesByStatus[status] = list;
      }

      _deliveryArrivingSoonEnabled =
          mergedDelivery['arriving_soon_enabled'] == true;
      final arrivingMins =
          mergedDelivery['arriving_soon_eta_threshold_minutes'];
      _deliveryArrivingSoonMinutes = arrivingMins is int
          ? arrivingMins
          : (arrivingMins is num ? arrivingMins.toInt() : 3);
      final limit = mergedDelivery['rate_limit_per_hour'];
      _deliveryRateLimitPerHour =
          limit is int ? limit : (limit is num ? limit.toInt() : 3);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final statuses = <String, dynamic>{};
      for (final status in _statuses) {
        final templates = (_templatesByStatus[status] ?? const [])
            .map((row) => {
                  'id': row.id.text.trim(),
                  'label': row.label.text.trim(),
                  'body': row.body.text.trim(),
                })
            .where((t) => (t['id'] as String).isNotEmpty)
            .toList();
        statuses[status] = {
          'default_channel': _defaultChannelByStatus[status] ?? 'none',
          'default_template_id':
              _defaultTemplateIdByStatus[status] ?? 'default',
          'templates': templates,
        };
      }

      final comms = {
        'default_wait_minutes': _defaultWaitMinutes,
        'statuses': statuses,
        'ready_escalation_enabled': _readyEscalationEnabled,
        'ready_escalation_minutes': _readyEscalationMinutes,
        'ready_escalation_channel': _readyEscalationChannel,
      };

      final deliveryStatuses = <String, dynamic>{};
      for (final status in _deliveryStatuses) {
        final templates = (_deliveryTemplatesByStatus[status] ?? const [])
            .map((row) => {
                  'id': row.id.text.trim(),
                  'label': row.label.text.trim(),
                  'body': row.body.text.trim(),
                })
            .where((t) => (t['id'] as String).isNotEmpty)
            .toList();
        deliveryStatuses[status] = {
          'default_channel': _deliveryDefaultChannelByStatus[status] ?? 'none',
          'default_template_id':
              _deliveryDefaultTemplateIdByStatus[status] ?? 'default',
          'templates': templates,
        };
      }
      final deliveryComms = {
        'rate_limit_per_hour': _deliveryRateLimitPerHour,
        'arriving_soon_enabled': _deliveryArrivingSoonEnabled,
        'arriving_soon_eta_threshold_minutes': _deliveryArrivingSoonMinutes,
        'statuses': deliveryStatuses,
      };

      final storeLoc = <String, dynamic>{
        'formatted': _storeAddressCtrl.text.trim(),
      };
      final lat = double.tryParse(_storeLatCtrl.text.trim());
      final lng = double.tryParse(_storeLngCtrl.text.trim());
      if (lat != null && lng != null) {
        storeLoc['lat'] = lat;
        storeLoc['lng'] = lng;
      }
      final deliverySettings = <String, dynamic>{
        'enabled': _deliveryEnabled,
        'fleet_mode': _deliveryFleetMode,
        'store_location': storeLoc,
        'marketplace_offer_cents':
            int.tryParse(_marketplaceOfferCtrl.text.trim()) ??
                _marketplaceOfferCents,
      };
      await FirebaseFirestore.instance.collection('stores').doc(_storeId).set({
        'order_comms': comms,
        'delivery_comms': deliveryComms,
        'delivery_settings': deliverySettings,
      }, SetOptions(merge: true));

      if (mounted) {
        showShadSnack(
          context,
          title: 'Saved',
          message: 'Store settings updated for $_storeId',
          type: ShadSnackType.success,
        );
      }
    } catch (err) {
      if (mounted) {
        showShadSnack(
          context,
          title: 'Save failed',
          message: '$err',
          type: ShadSnackType.error,
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return BusinessScaffold(
      title: const Text('Store settings'),
      actions: [
        IconButton(
          onPressed: _loading || _saving ? null : _save,
          icon: _saving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.save),
          tooltip: 'Save',
        ),
      ],
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                ShadCard(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Store',
                          style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 4),
                      Text(_storeId,
                          style: Theme.of(context).textTheme.bodyMedium),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                DeliverySettingsCard(
                  deliveryEnabled: _deliveryEnabled,
                  onDeliveryEnabledChanged: (v) =>
                      setState(() => _deliveryEnabled = v),
                  fleetMode: _deliveryFleetMode,
                  onFleetModeChanged: (v) => setState(
                    () => _deliveryFleetMode = v ?? 'owned_fleet',
                  ),
                  storeAddressController: _storeAddressCtrl,
                  storeLatController: _storeLatCtrl,
                  storeLngController: _storeLngCtrl,
                  marketplaceOfferController: _marketplaceOfferCtrl,
                  showMarketplaceOffer: _deliveryFleetMode == 'marketplace',
                ),
                const SizedBox(height: 12),
                ShadCard(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Default wait time',
                          style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 6),
                      Text(
                        'Fallback ETA (minutes) used when we have no historical prep-time samples.',
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(color: Colors.grey[600]),
                      ),
                      const SizedBox(height: 10),
                      TextFormField(
                        controller: _defaultWaitCtrl,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Minutes',
                          border: OutlineInputBorder(),
                        ),
                        onChanged: (v) {
                          final n = int.tryParse(v.trim());
                          if (n == null) return;
                          setState(() => _defaultWaitMinutes = n.clamp(1, 180));
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                _buildReadyEscalation(context),
                const SizedBox(height: 12),
                ..._statuses.map((s) => Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _buildStatusCard(context, s),
                    )),
                const SizedBox(height: 12),
                Text('Delivery notifications',
                    style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                _buildDeliveryCommsControls(context),
                const SizedBox(height: 12),
                ..._deliveryStatuses.map((s) => Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _buildDeliveryStatusCard(context, s),
                    )),
                const SizedBox(height: 12),
                ShadButton(
                  onPressed: _saving ? null : _save,
                  child: const Text('Save changes'),
                ),
              ],
            ),
    );
  }

  Widget _buildReadyEscalation(BuildContext context) {
    return ShadCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Ready escalation',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Enable outbound escalation'),
            value: _readyEscalationEnabled,
            onChanged: (v) => setState(() => _readyEscalationEnabled = v),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  initialValue: _readyEscalationMinutes.toString(),
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Minutes',
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (v) {
                    final parsed = int.tryParse(v.trim());
                    if (parsed != null) {
                      setState(() => _readyEscalationMinutes = parsed);
                    }
                  },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: DropdownButtonFormField<String>(
                  value: _readyEscalationChannel,
                  decoration: const InputDecoration(
                    labelText: 'Channel',
                    border: OutlineInputBorder(),
                  ),
                  items: _channels
                      .where((c) => c != 'none')
                      .map((c) => DropdownMenuItem(
                          value: c, child: Text(c.toUpperCase())))
                      .toList(),
                  onChanged: (v) =>
                      setState(() => _readyEscalationChannel = v ?? 'call'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDeliveryCommsControls(BuildContext context) {
    return ShadCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Guardrails', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Enable arriving-soon notifications'),
            value: _deliveryArrivingSoonEnabled,
            onChanged: (v) => setState(() => _deliveryArrivingSoonEnabled = v),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  initialValue: _deliveryArrivingSoonMinutes.toString(),
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Arriving soon ETA threshold (minutes)',
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (v) {
                    final parsed = int.tryParse(v.trim());
                    if (parsed != null) {
                      setState(() => _deliveryArrivingSoonMinutes = parsed);
                    }
                  },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextFormField(
                  initialValue: _deliveryRateLimitPerHour.toString(),
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Max messages per hour',
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (v) {
                    final parsed = int.tryParse(v.trim());
                    if (parsed != null) {
                      setState(() => _deliveryRateLimitPerHour = parsed);
                    }
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatusCard(BuildContext context, String status) {
    final templates = _templatesByStatus[status] ?? [];
    final defaultTemplateId = _defaultTemplateIdByStatus[status] ?? 'default';
    return ShadCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(status.toUpperCase(),
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(
            value: _defaultChannelByStatus[status] ?? 'none',
            decoration: const InputDecoration(
              labelText: 'Default channel',
              border: OutlineInputBorder(),
            ),
            items: _channels
                .map((c) =>
                    DropdownMenuItem(value: c, child: Text(c.toUpperCase())))
                .toList(),
            onChanged: (v) =>
                setState(() => _defaultChannelByStatus[status] = v ?? 'none'),
          ),
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(
            value: defaultTemplateId,
            decoration: const InputDecoration(
              labelText: 'Default template',
              border: OutlineInputBorder(),
            ),
            items: templates
                .map((t) => DropdownMenuItem(
                    value: t.id.text.trim(),
                    child: Text(t.label.text.trim().isEmpty
                        ? t.id.text.trim()
                        : t.label.text.trim())))
                .toList(),
            onChanged: (v) => setState(
                () => _defaultTemplateIdByStatus[status] = v ?? 'default'),
          ),
          const SizedBox(height: 12),
          Text('Templates', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          ...templates.map((t) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child:
                    _buildTemplateEditor(context, status, t, isDelivery: false),
              )),
          ShadButton.outline(
            onPressed: () => setState(() {
              final id = 'tmpl_${DateTime.now().millisecondsSinceEpoch}';
              _templatesByStatus[status] = [
                ...templates,
                _TemplateRow(id: id, label: 'Template', body: '')
              ];
            }),
            child: const Text('Add template'),
          ),
        ],
      ),
    );
  }

  Widget _buildDeliveryStatusCard(BuildContext context, String status) {
    final templates = _deliveryTemplatesByStatus[status] ?? [];
    final defaultTemplateId =
        _deliveryDefaultTemplateIdByStatus[status] ?? 'default';
    return ShadCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(status.toUpperCase(),
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(
            value: _deliveryDefaultChannelByStatus[status] ?? 'none',
            decoration: const InputDecoration(
              labelText: 'Default channel',
              border: OutlineInputBorder(),
            ),
            items: _channels
                .map((c) =>
                    DropdownMenuItem(value: c, child: Text(c.toUpperCase())))
                .toList(),
            onChanged: (v) => setState(
                () => _deliveryDefaultChannelByStatus[status] = v ?? 'none'),
          ),
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(
            value: defaultTemplateId,
            decoration: const InputDecoration(
              labelText: 'Default template',
              border: OutlineInputBorder(),
            ),
            items: templates
                .map((t) => DropdownMenuItem(
                    value: t.id.text.trim(),
                    child: Text(t.label.text.trim().isEmpty
                        ? t.id.text.trim()
                        : t.label.text.trim())))
                .toList(),
            onChanged: (v) => setState(() =>
                _deliveryDefaultTemplateIdByStatus[status] = v ?? 'default'),
          ),
          const SizedBox(height: 12),
          Text('Templates', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          ...templates.map((t) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child:
                    _buildTemplateEditor(context, status, t, isDelivery: true),
              )),
          ShadButton.outline(
            onPressed: () => setState(() {
              final id = 'tmpl_${DateTime.now().millisecondsSinceEpoch}';
              _deliveryTemplatesByStatus[status] = [
                ...templates,
                _TemplateRow(id: id, label: 'Template', body: '')
              ];
            }),
            child: const Text('Add template'),
          ),
        ],
      ),
    );
  }

  Widget _buildTemplateEditor(
      BuildContext context, String status, _TemplateRow row,
      {required bool isDelivery}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: row.label,
                decoration: const InputDecoration(
                  labelText: 'Label',
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            const SizedBox(width: 10),
            SizedBox(
              width: 140,
              child: TextField(
                controller: row.id,
                decoration: const InputDecoration(
                  labelText: 'ID',
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            const SizedBox(width: 10),
            IconButton(
              onPressed: () => setState(() {
                if (isDelivery) {
                  _deliveryTemplatesByStatus[status] =
                      (_deliveryTemplatesByStatus[status] ?? [])
                          .where((t) => t != row)
                          .toList();
                } else {
                  _templatesByStatus[status] =
                      (_templatesByStatus[status] ?? [])
                          .where((t) => t != row)
                          .toList();
                }
                row.dispose();
              }),
              icon: const Icon(Icons.delete_outline),
              tooltip: 'Delete template',
            ),
          ],
        ),
        const SizedBox(height: 8),
        TextField(
          controller: row.body,
          minLines: 2,
          maxLines: 6,
          decoration: const InputDecoration(
            labelText: 'Body',
            border: OutlineInputBorder(),
          ),
        ),
      ],
    );
  }
}
