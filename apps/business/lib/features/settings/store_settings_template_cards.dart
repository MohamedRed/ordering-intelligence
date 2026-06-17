import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import 'store_settings_defaults.dart';
import 'store_settings_template_row.dart';

typedef StatusConfigChanged = void Function(
  String status, {
  String? channel,
  String? templateId,
});
typedef TemplateAdded = void Function(String status,
    {required bool isDelivery});
typedef TemplateRemoved = void Function(
  String status,
  TemplateRow row, {
  required bool isDelivery,
});

class StatusTemplateCard extends StatelessWidget {
  const StatusTemplateCard({
    super.key,
    required this.status,
    required this.templates,
    required this.defaultChannel,
    required this.defaultTemplateId,
    required this.onStatusChanged,
    required this.onAddTemplate,
    required this.onRemoveTemplate,
  });

  final String status;
  final List<TemplateRow> templates;
  final String defaultChannel;
  final String defaultTemplateId;
  final StatusConfigChanged onStatusChanged;
  final VoidCallback onAddTemplate;
  final ValueChanged<TemplateRow> onRemoveTemplate;

  @override
  Widget build(BuildContext context) {
    final selectedTemplateId = selectedTemplateValue(
      templates,
      defaultTemplateId,
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: ShadCard(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              status.toUpperCase(),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              initialValue: defaultChannel,
              decoration: const InputDecoration(
                labelText: 'Default channel',
                border: OutlineInputBorder(),
              ),
              items: notificationChannels
                  .map((entry) => DropdownMenuItem(
                        value: entry,
                        child: Text(entry.toUpperCase()),
                      ))
                  .toList(),
              onChanged: (value) =>
                  onStatusChanged(status, channel: value ?? 'none'),
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              initialValue: selectedTemplateId,
              decoration: const InputDecoration(
                labelText: 'Default template',
                border: OutlineInputBorder(),
              ),
              items: templates
                  .map((template) => DropdownMenuItem(
                        value: template.id.text.trim(),
                        child: Text(templateLabel(template)),
                      ))
                  .toList(),
              onChanged: (value) =>
                  onStatusChanged(status, templateId: value ?? 'default'),
            ),
            const SizedBox(height: 12),
            Text('Templates', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            for (final template in templates)
              TemplateEditor(
                row: template,
                onRemove: () => onRemoveTemplate(template),
              ),
            ShadButton.outline(
              onPressed: onAddTemplate,
              child: const Text('Add template'),
            ),
          ],
        ),
      ),
    );
  }
}

class TemplateEditor extends StatelessWidget {
  const TemplateEditor({super.key, required this.row, required this.onRemove});

  final TemplateRow row;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              if (constraints.maxWidth < 560) {
                return Column(
                  children: [
                    _TemplateLabelField(row: row),
                    const SizedBox(height: 8),
                    _TemplateIdField(row: row),
                    Align(
                      alignment: Alignment.centerRight,
                      child: IconButton(
                        onPressed: onRemove,
                        icon: const Icon(Icons.delete_outline),
                        tooltip: 'Delete template',
                      ),
                    ),
                  ],
                );
              }
              return Row(
                children: [
                  Expanded(child: _TemplateLabelField(row: row)),
                  const SizedBox(width: 10),
                  SizedBox(width: 140, child: _TemplateIdField(row: row)),
                  const SizedBox(width: 10),
                  IconButton(
                    onPressed: onRemove,
                    icon: const Icon(Icons.delete_outline),
                    tooltip: 'Delete template',
                  ),
                ],
              );
            },
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
      ),
    );
  }
}

String? selectedTemplateValue(
  List<TemplateRow> templates,
  String preferredTemplateId,
) {
  for (final template in templates) {
    final id = template.id.text.trim();
    if (id == preferredTemplateId) return id;
  }
  for (final template in templates) {
    final id = template.id.text.trim();
    if (id.isNotEmpty) return id;
  }
  return null;
}

String templateLabel(TemplateRow template) {
  final label = template.label.text.trim();
  if (label.isNotEmpty) return label;
  return template.id.text.trim();
}

class _TemplateLabelField extends StatelessWidget {
  const _TemplateLabelField({required this.row});

  final TemplateRow row;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: row.label,
      decoration: const InputDecoration(
        labelText: 'Label',
        border: OutlineInputBorder(),
      ),
    );
  }
}

class _TemplateIdField extends StatelessWidget {
  const _TemplateIdField({required this.row});

  final TemplateRow row;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: row.id,
      decoration: const InputDecoration(
        labelText: 'ID',
        border: OutlineInputBorder(),
      ),
    );
  }
}
