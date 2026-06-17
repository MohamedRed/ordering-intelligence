import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import 'delivery_settings_card.dart';
import 'store_settings_basic_cards.dart';
import 'store_settings_defaults.dart';
import 'store_settings_template_cards.dart';
import 'store_settings_template_row.dart';

class StoreSettingsBody extends StatelessWidget {
  const StoreSettingsBody({
    super.key,
    required this.storeId,
    required this.saving,
    required this.deliveryEnabled,
    required this.onDeliveryEnabledChanged,
    required this.fleetMode,
    required this.onFleetModeChanged,
    required this.storeAddressController,
    required this.storeLatController,
    required this.storeLngController,
    required this.marketplaceOfferController,
    required this.defaultWaitController,
    required this.onDefaultWaitChanged,
    required this.readyEscalationEnabled,
    required this.onReadyEscalationEnabledChanged,
    required this.readyEscalationMinutes,
    required this.onReadyEscalationMinutesChanged,
    required this.readyEscalationChannel,
    required this.onReadyEscalationChannelChanged,
    required this.deliveryArrivingSoonEnabled,
    required this.onDeliveryArrivingSoonEnabledChanged,
    required this.deliveryArrivingSoonMinutes,
    required this.onDeliveryArrivingSoonMinutesChanged,
    required this.deliveryRateLimitPerHour,
    required this.onDeliveryRateLimitPerHourChanged,
    required this.defaultChannelByStatus,
    required this.defaultTemplateIdByStatus,
    required this.templatesByStatus,
    required this.deliveryDefaultChannelByStatus,
    required this.deliveryDefaultTemplateIdByStatus,
    required this.deliveryTemplatesByStatus,
    required this.onOrderStatusChanged,
    required this.onDeliveryStatusChanged,
    required this.onAddTemplate,
    required this.onRemoveTemplate,
    required this.onSave,
  });

  final String storeId;
  final bool saving;
  final bool deliveryEnabled;
  final ValueChanged<bool> onDeliveryEnabledChanged;
  final String fleetMode;
  final ValueChanged<String?> onFleetModeChanged;
  final TextEditingController storeAddressController;
  final TextEditingController storeLatController;
  final TextEditingController storeLngController;
  final TextEditingController marketplaceOfferController;
  final TextEditingController defaultWaitController;
  final ValueChanged<String> onDefaultWaitChanged;
  final bool readyEscalationEnabled;
  final ValueChanged<bool> onReadyEscalationEnabledChanged;
  final int readyEscalationMinutes;
  final ValueChanged<int> onReadyEscalationMinutesChanged;
  final String readyEscalationChannel;
  final ValueChanged<String?> onReadyEscalationChannelChanged;
  final bool deliveryArrivingSoonEnabled;
  final ValueChanged<bool> onDeliveryArrivingSoonEnabledChanged;
  final int deliveryArrivingSoonMinutes;
  final ValueChanged<int> onDeliveryArrivingSoonMinutesChanged;
  final int deliveryRateLimitPerHour;
  final ValueChanged<int> onDeliveryRateLimitPerHourChanged;
  final Map<String, String> defaultChannelByStatus;
  final Map<String, String> defaultTemplateIdByStatus;
  final Map<String, List<TemplateRow>> templatesByStatus;
  final Map<String, String> deliveryDefaultChannelByStatus;
  final Map<String, String> deliveryDefaultTemplateIdByStatus;
  final Map<String, List<TemplateRow>> deliveryTemplatesByStatus;
  final StatusConfigChanged onOrderStatusChanged;
  final StatusConfigChanged onDeliveryStatusChanged;
  final TemplateAdded onAddTemplate;
  final TemplateRemoved onRemoveTemplate;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        StoreInfoCard(storeId: storeId),
        const SizedBox(height: 12),
        DeliverySettingsCard(
          deliveryEnabled: deliveryEnabled,
          onDeliveryEnabledChanged: onDeliveryEnabledChanged,
          fleetMode: fleetMode,
          onFleetModeChanged: onFleetModeChanged,
          storeAddressController: storeAddressController,
          storeLatController: storeLatController,
          storeLngController: storeLngController,
          marketplaceOfferController: marketplaceOfferController,
          showMarketplaceOffer: fleetMode == 'marketplace',
        ),
        const SizedBox(height: 12),
        DefaultWaitTimeCard(
          controller: defaultWaitController,
          onChanged: onDefaultWaitChanged,
        ),
        const SizedBox(height: 12),
        ReadyEscalationCard(
          enabled: readyEscalationEnabled,
          onEnabledChanged: onReadyEscalationEnabledChanged,
          minutes: readyEscalationMinutes,
          onMinutesChanged: onReadyEscalationMinutesChanged,
          channel: readyEscalationChannel,
          onChannelChanged: onReadyEscalationChannelChanged,
        ),
        const SizedBox(height: 12),
        for (final status in orderCommsStatuses)
          StatusTemplateCard(
            status: status,
            templates: templatesByStatus[status] ?? const [],
            defaultChannel: defaultChannelByStatus[status] ?? 'none',
            defaultTemplateId: defaultTemplateIdByStatus[status] ?? 'default',
            onStatusChanged: onOrderStatusChanged,
            onAddTemplate: () => onAddTemplate(status, isDelivery: false),
            onRemoveTemplate: (row) =>
                onRemoveTemplate(status, row, isDelivery: false),
          ),
        const SizedBox(height: 12),
        Text('Delivery notifications',
            style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        DeliveryCommsControlsCard(
          arrivingSoonEnabled: deliveryArrivingSoonEnabled,
          onArrivingSoonEnabledChanged: onDeliveryArrivingSoonEnabledChanged,
          arrivingSoonMinutes: deliveryArrivingSoonMinutes,
          onArrivingSoonMinutesChanged: onDeliveryArrivingSoonMinutesChanged,
          rateLimitPerHour: deliveryRateLimitPerHour,
          onRateLimitPerHourChanged: onDeliveryRateLimitPerHourChanged,
        ),
        const SizedBox(height: 12),
        for (final status in deliveryCommsStatuses)
          StatusTemplateCard(
            status: status,
            templates: deliveryTemplatesByStatus[status] ?? const [],
            defaultChannel: deliveryDefaultChannelByStatus[status] ?? 'none',
            defaultTemplateId:
                deliveryDefaultTemplateIdByStatus[status] ?? 'default',
            onStatusChanged: onDeliveryStatusChanged,
            onAddTemplate: () => onAddTemplate(status, isDelivery: true),
            onRemoveTemplate: (row) =>
                onRemoveTemplate(status, row, isDelivery: true),
          ),
        const SizedBox(height: 12),
        ShadButton(
          onPressed: saving ? null : onSave,
          child: const Text('Save changes'),
        ),
      ],
    );
  }
}
