import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import 'store_settings_defaults.dart';

class StoreInfoCard extends StatelessWidget {
  const StoreInfoCard({super.key, required this.storeId});

  final String storeId;

  @override
  Widget build(BuildContext context) {
    return ShadCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Store', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(storeId, style: Theme.of(context).textTheme.bodyMedium),
        ],
      ),
    );
  }
}

class DefaultWaitTimeCard extends StatelessWidget {
  const DefaultWaitTimeCard({
    super.key,
    required this.controller,
    required this.onChanged,
  });

  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return ShadCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Default wait time',
            style: Theme.of(context).textTheme.titleMedium,
          ),
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
            controller: controller,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Minutes',
              border: OutlineInputBorder(),
            ),
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}

class ReadyEscalationCard extends StatelessWidget {
  const ReadyEscalationCard({
    super.key,
    required this.enabled,
    required this.onEnabledChanged,
    required this.minutes,
    required this.onMinutesChanged,
    required this.channel,
    required this.onChannelChanged,
  });

  final bool enabled;
  final ValueChanged<bool> onEnabledChanged;
  final int minutes;
  final ValueChanged<int> onMinutesChanged;
  final String channel;
  final ValueChanged<String?> onChannelChanged;

  @override
  Widget build(BuildContext context) {
    return ShadCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Ready escalation',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Enable outbound escalation'),
            value: enabled,
            onChanged: onEnabledChanged,
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              SettingsNumberField(
                width: 220,
                initialValue: minutes,
                label: 'Minutes',
                onChanged: onMinutesChanged,
              ),
              SizedBox(
                width: 220,
                child: DropdownButtonFormField<String>(
                  initialValue: channel,
                  decoration: const InputDecoration(
                    labelText: 'Channel',
                    border: OutlineInputBorder(),
                  ),
                  items: notificationChannels
                      .where((entry) => entry != 'none')
                      .map((entry) => DropdownMenuItem(
                            value: entry,
                            child: Text(entry.toUpperCase()),
                          ))
                      .toList(),
                  onChanged: onChannelChanged,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class DeliveryCommsControlsCard extends StatelessWidget {
  const DeliveryCommsControlsCard({
    super.key,
    required this.arrivingSoonEnabled,
    required this.onArrivingSoonEnabledChanged,
    required this.arrivingSoonMinutes,
    required this.onArrivingSoonMinutesChanged,
    required this.rateLimitPerHour,
    required this.onRateLimitPerHourChanged,
  });

  final bool arrivingSoonEnabled;
  final ValueChanged<bool> onArrivingSoonEnabledChanged;
  final int arrivingSoonMinutes;
  final ValueChanged<int> onArrivingSoonMinutesChanged;
  final int rateLimitPerHour;
  final ValueChanged<int> onRateLimitPerHourChanged;

  @override
  Widget build(BuildContext context) {
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
            value: arrivingSoonEnabled,
            onChanged: onArrivingSoonEnabledChanged,
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              SettingsNumberField(
                width: 300,
                initialValue: arrivingSoonMinutes,
                label: 'Arriving soon ETA threshold (minutes)',
                onChanged: onArrivingSoonMinutesChanged,
              ),
              SettingsNumberField(
                width: 220,
                initialValue: rateLimitPerHour,
                label: 'Max messages per hour',
                onChanged: onRateLimitPerHourChanged,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class SettingsNumberField extends StatelessWidget {
  const SettingsNumberField({
    super.key,
    required this.width,
    required this.initialValue,
    required this.label,
    required this.onChanged,
  });

  final double width;
  final int initialValue;
  final String label;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: TextFormField(
        initialValue: initialValue.toString(),
        keyboardType: TextInputType.number,
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
        ),
        onChanged: (value) {
          final parsed = int.tryParse(value.trim());
          if (parsed != null) onChanged(parsed);
        },
      ),
    );
  }
}
