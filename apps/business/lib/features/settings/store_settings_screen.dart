import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../util/store_id.dart';
import '../../widgets/business_scaffold.dart';
import 'store_settings_body.dart';
import 'store_settings_defaults.dart';
import 'store_settings_payload.dart';
import 'store_settings_snacks.dart';
import 'store_settings_template_row.dart';

part 'store_settings_screen_body.dart';

class StoreSettingsScreen extends StatefulWidget {
  const StoreSettingsScreen({super.key});

  @override
  State<StoreSettingsScreen> createState() => _StoreSettingsScreenState();
}

class _StoreSettingsScreenState extends State<StoreSettingsScreen> {
  bool _loading = true;
  bool _saving = false;

  final Map<String, String> _defaultChannelByStatus = {};
  final Map<String, String> _defaultTemplateIdByStatus = {};
  final Map<String, List<TemplateRow>> _templatesByStatus = {};
  final Map<String, String> _deliveryDefaultChannelByStatus = {};
  final Map<String, String> _deliveryDefaultTemplateIdByStatus = {};
  final Map<String, List<TemplateRow>> _deliveryTemplatesByStatus = {};

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
    disposeTemplateRows(_templatesByStatus);
    disposeTemplateRows(_deliveryTemplatesByStatus);
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final snap = await FirebaseFirestore.instance
          .collection('stores')
          .doc(_storeId)
          .get();
      final data = snap.data() ?? <String, dynamic>{};
      _loadDeliverySettings(data);
      _loadOrderComms(data);
      _loadDeliveryComms(data);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _loadDeliverySettings(Map<String, dynamic> data) {
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
    _marketplaceOfferCents =
        readSettingsInt(delivery['marketplace_offer_cents'], 300);
    _marketplaceOfferCtrl.text = _marketplaceOfferCents.toString();
  }

  void _loadOrderComms(Map<String, dynamic> data) {
    final comms = (data['order_comms'] as Map?)?.cast<String, dynamic>() ?? {};
    final merged = defaultOrderComms()..addAll(comms);
    final statuses =
        (merged['statuses'] as Map?)?.cast<String, dynamic>() ?? {};
    for (final status in orderCommsStatuses) {
      final cfg = (statuses[status] as Map?)?.cast<String, dynamic>() ?? {};
      _defaultChannelByStatus[status] =
          (cfg['default_channel'] as String?)?.trim() ?? 'none';
      _defaultTemplateIdByStatus[status] =
          (cfg['default_template_id'] as String?)?.trim() ?? 'default';
      _templatesByStatus[status] = templateRowsFromConfig(
        cfg['templates'],
        fallbackBody: 'Order status updated.',
      );
    }
    _readyEscalationEnabled = merged['ready_escalation_enabled'] == true;
    _readyEscalationMinutes =
        readSettingsInt(merged['ready_escalation_minutes'], 5);
    _readyEscalationChannel =
        (merged['ready_escalation_channel'] as String?)?.trim() ?? 'call';
    _defaultWaitMinutes = readSettingsInt(merged['default_wait_minutes'], 15);
    _defaultWaitCtrl.text = _defaultWaitMinutes.toString();
  }

  void _loadDeliveryComms(Map<String, dynamic> data) {
    final deliveryComms =
        (data['delivery_comms'] as Map?)?.cast<String, dynamic>() ?? {};
    final merged = defaultDeliveryComms()..addAll(deliveryComms);
    final statuses =
        (merged['statuses'] as Map?)?.cast<String, dynamic>() ?? {};
    for (final status in deliveryCommsStatuses) {
      final cfg = (statuses[status] as Map?)?.cast<String, dynamic>() ?? {};
      _deliveryDefaultChannelByStatus[status] =
          (cfg['default_channel'] as String?)?.trim() ?? 'none';
      _deliveryDefaultTemplateIdByStatus[status] =
          (cfg['default_template_id'] as String?)?.trim() ?? 'default';
      _deliveryTemplatesByStatus[status] = templateRowsFromConfig(
        cfg['templates'],
        fallbackBody: 'Delivery status updated.',
      );
    }
    _deliveryArrivingSoonEnabled = merged['arriving_soon_enabled'] == true;
    _deliveryArrivingSoonMinutes =
        readSettingsInt(merged['arriving_soon_eta_threshold_minutes'], 3);
    _deliveryRateLimitPerHour =
        readSettingsInt(merged['rate_limit_per_hour'], 3);
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final payload = buildStoreSettingsPayload(
        defaultWaitMinutes: _defaultWaitMinutes,
        readyEscalationEnabled: _readyEscalationEnabled,
        readyEscalationMinutes: _readyEscalationMinutes,
        readyEscalationChannel: _readyEscalationChannel,
        deliveryArrivingSoonEnabled: _deliveryArrivingSoonEnabled,
        deliveryArrivingSoonMinutes: _deliveryArrivingSoonMinutes,
        deliveryRateLimitPerHour: _deliveryRateLimitPerHour,
        deliveryEnabled: _deliveryEnabled,
        deliveryFleetMode: _deliveryFleetMode,
        storeAddress: _storeAddressCtrl.text,
        storeLat: _storeLatCtrl.text,
        storeLng: _storeLngCtrl.text,
        marketplaceOffer: _marketplaceOfferCtrl.text,
        marketplaceOfferCents: _marketplaceOfferCents,
        defaultChannelByStatus: _defaultChannelByStatus,
        defaultTemplateIdByStatus: _defaultTemplateIdByStatus,
        templatesByStatus: _templatesByStatus,
        deliveryDefaultChannelByStatus: _deliveryDefaultChannelByStatus,
        deliveryDefaultTemplateIdByStatus: _deliveryDefaultTemplateIdByStatus,
        deliveryTemplatesByStatus: _deliveryTemplatesByStatus,
      );
      await FirebaseFirestore.instance
          .collection('stores')
          .doc(_storeId)
          .set(payload, SetOptions(merge: true));
      if (mounted) showStoreSettingsSavedSnack(context, _storeId);
    } catch (err) {
      if (mounted) showStoreSettingsSaveFailedSnack(context, err);
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
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.save),
          tooltip: 'Save',
        ),
      ],
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _buildSettingsBody(),
    );
  }

  void _setDefaultWait(String value) {
    final n = int.tryParse(value.trim());
    if (n != null) setState(() => _defaultWaitMinutes = n.clamp(1, 180));
  }

  void _update(VoidCallback update) => setState(update);

  void _setOrderStatusConfig(
    String status, {
    String? channel,
    String? templateId,
  }) {
    setState(() {
      if (channel != null) _defaultChannelByStatus[status] = channel;
      if (templateId != null) _defaultTemplateIdByStatus[status] = templateId;
    });
  }

  void _setDeliveryStatusConfig(
    String status, {
    String? channel,
    String? templateId,
  }) {
    setState(() {
      if (channel != null) _deliveryDefaultChannelByStatus[status] = channel;
      if (templateId != null) {
        _deliveryDefaultTemplateIdByStatus[status] = templateId;
      }
    });
  }

  void _addTemplate(String status, {required bool isDelivery}) {
    final row = newTemplateRow(DateTime.now());
    setState(() {
      final map = isDelivery ? _deliveryTemplatesByStatus : _templatesByStatus;
      map[status] = [...(map[status] ?? const <TemplateRow>[]), row];
    });
  }

  void _removeTemplate(String status, TemplateRow row,
      {required bool isDelivery}) {
    setState(() {
      final map = isDelivery ? _deliveryTemplatesByStatus : _templatesByStatus;
      map[status] = (map[status] ?? []).where((item) => item != row).toList();
      row.dispose();
    });
  }
}
