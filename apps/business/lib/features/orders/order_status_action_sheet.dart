import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../models/order.dart';

class OrderStatusActionResult {
  const OrderStatusActionResult({
    required this.notifyMode,
    this.note,
    this.templateId,
  });

  final String notifyMode; // auto|sms|call|none
  final String? note;
  final String? templateId;
}

Future<OrderStatusActionResult?> showOrderStatusActionSheet({
  required BuildContext context,
  required String storeId,
  required OrderStatus status,
}) {
  return showModalBottomSheet<OrderStatusActionResult>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) =>
        _OrderStatusActionSheet(storeId: storeId, status: status),
  );
}

Future<OrderStatusActionResult?> showOrderDelayActionSheet({
  required BuildContext context,
  required String storeId,
}) {
  return showModalBottomSheet<OrderStatusActionResult>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => _OrderStatusActionSheet(
      storeId: storeId,
      status: OrderStatus.pending,
      statusKeyOverride: 'delay',
      titleOverride: 'Notify delay',
      descriptionOverride:
          'Send a “running late” message without changing the order status.',
    ),
  );
}

class _TemplateOption {
  const _TemplateOption(
      {required this.id, required this.label, required this.body});
  final String id;
  final String label;
  final String body;
}

class _OrderStatusActionSheet extends StatefulWidget {
  const _OrderStatusActionSheet({
    required this.storeId,
    required this.status,
    this.statusKeyOverride,
    this.titleOverride,
    this.descriptionOverride,
  });
  final String storeId;
  final OrderStatus status;
  final String? statusKeyOverride; // e.g. "delay"
  final String? titleOverride;
  final String? descriptionOverride;

  @override
  State<_OrderStatusActionSheet> createState() =>
      _OrderStatusActionSheetState();
}

class _OrderStatusActionSheetState extends State<_OrderStatusActionSheet> {
  final _noteController = TextEditingController();

  bool _loading = true;
  String _notifyMode = 'auto';
  String? _selectedTemplateId;
  String _defaultChannel = 'none';
  String? _defaultTemplateId;
  List<_TemplateOption> _templates = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  String get _statusKey =>
      (widget.statusKeyOverride ?? orderStatusToString(widget.status)).trim();

  Future<void> _load() async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('stores')
          .doc(widget.storeId)
          .get();
      final data = snap.data() ?? <String, dynamic>{};
      final orderComms =
          (data['order_comms'] as Map?)?.cast<String, dynamic>() ??
              const <String, dynamic>{};
      final statuses =
          (orderComms['statuses'] as Map?)?.cast<String, dynamic>() ??
              const <String, dynamic>{};
      final statusCfg =
          (statuses[_statusKey] as Map?)?.cast<String, dynamic>() ??
              const <String, dynamic>{};

      final defaultChannel = (statusCfg['default_channel'] as String?)?.trim();
      final defaultTemplateId =
          (statusCfg['default_template_id'] as String?)?.trim();
      final templatesRaw =
          (statusCfg['templates'] as List?)?.cast<dynamic>() ?? const [];
      final templates = <_TemplateOption>[];
      for (final t in templatesRaw) {
        final m = (t as Map?)?.cast<String, dynamic>();
        if (m == null) continue;
        final id = (m['id'] as String?)?.trim() ?? '';
        if (id.isEmpty) continue;
        templates.add(_TemplateOption(
          id: id,
          label: ((m['label'] as String?)?.trim().isNotEmpty ?? false)
              ? (m['label'] as String).trim()
              : id,
          body: (m['body'] as String?)?.trim() ?? '',
        ));
      }

      setState(() {
        _defaultChannel = (defaultChannel != null && defaultChannel.isNotEmpty)
            ? defaultChannel
            : 'none';
        _defaultTemplateId =
            (defaultTemplateId != null && defaultTemplateId.isNotEmpty)
                ? defaultTemplateId
                : null;
        _templates = templates;
        _selectedTemplateId = _defaultTemplateId;
        _loading = false;
      });

      // Prefill note with default template if present and empty.
      if (_noteController.text.trim().isEmpty && _selectedTemplateId != null) {
        final opt = _templates
            .where((t) => t.id == _selectedTemplateId)
            .cast<_TemplateOption?>()
            .firstWhere(
              (t) => t != null,
              orElse: () => null,
            );
        if (opt != null && opt.body.trim().isNotEmpty) {
          _noteController.text = opt.body.trim();
        }
      }
    } catch (_) {
      setState(() {
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(
          left: 16, right: 16, top: 8, bottom: 16 + bottomInset),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(widget.titleOverride ?? 'Update status',
              style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 4),
          Text(
            widget.descriptionOverride ??
                'Set to ${_statusKey.toUpperCase()} • Default: ${_defaultChannel.toUpperCase()}',
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: Colors.grey[600]),
          ),
          const SizedBox(height: 12),
          _buildModePicker(context),
          const SizedBox(height: 12),
          if (_loading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Center(child: CircularProgressIndicator()),
            )
          else
            _buildTemplateAndNote(context),
          const SizedBox(height: 12),
          ShadButton(
            onPressed: () {
              Navigator.of(context).pop(OrderStatusActionResult(
                notifyMode: _notifyMode,
                note: _noteController.text.trim().isEmpty
                    ? null
                    : _noteController.text.trim(),
                templateId: _selectedTemplateId,
              ));
            },
            child: const Text('Confirm'),
          ),
          const SizedBox(height: 8),
          ShadButton.outline(
            onPressed: () => Navigator.of(context).pop(null),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }

  Widget _buildModePicker(BuildContext context) {
    Widget chip(String label, String value) {
      final selected = _notifyMode == value;
      return ChoiceChip(
        label: Text(label),
        selected: selected,
        onSelected: (_) => setState(() => _notifyMode = value),
      );
    }

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        chip('Auto', 'auto'),
        chip('SMS', 'sms'),
        chip('Call', 'call'),
        chip('None', 'none'),
      ],
    );
  }

  Widget _buildTemplateAndNote(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_templates.isNotEmpty)
          DropdownButtonFormField<String?>(
            initialValue: _selectedTemplateId,
            decoration: const InputDecoration(
              labelText: 'Template',
              border: OutlineInputBorder(),
            ),
            items: [
              const DropdownMenuItem<String?>(
                  value: null, child: Text('No template')),
              ..._templates.map(
                  (t) => DropdownMenuItem(value: t.id, child: Text(t.label))),
            ],
            onChanged: (value) {
              setState(() => _selectedTemplateId = value);
              final tmpl = _templates
                  .where((t) => t.id == value)
                  .cast<_TemplateOption?>()
                  .firstWhere(
                    (t) => t != null,
                    orElse: () => null,
                  );
              if (tmpl != null && tmpl.body.trim().isNotEmpty) {
                _noteController.text = tmpl.body.trim();
              }
            },
          ),
        if (_templates.isNotEmpty) const SizedBox(height: 12),
        TextField(
          controller: _noteController,
          minLines: 3,
          maxLines: 6,
          decoration: const InputDecoration(
            labelText: 'Note (optional)',
            hintText: 'What should we tell the customer?',
            border: OutlineInputBorder(),
          ),
        ),
      ],
    );
  }
}
