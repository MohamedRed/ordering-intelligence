part of 'store_settings_screen.dart';

extension _StoreSettingsScreenBody on _StoreSettingsScreenState {
  Widget _buildSettingsBody() {
    return StoreSettingsBody(
      storeId: _storeId,
      saving: _saving,
      deliveryEnabled: _deliveryEnabled,
      onDeliveryEnabledChanged: (value) =>
          _update(() => _deliveryEnabled = value),
      fleetMode: _deliveryFleetMode,
      onFleetModeChanged: (value) =>
          _update(() => _deliveryFleetMode = value ?? 'owned_fleet'),
      storeAddressController: _storeAddressCtrl,
      storeLatController: _storeLatCtrl,
      storeLngController: _storeLngCtrl,
      marketplaceOfferController: _marketplaceOfferCtrl,
      defaultWaitController: _defaultWaitCtrl,
      onDefaultWaitChanged: _setDefaultWait,
      readyEscalationEnabled: _readyEscalationEnabled,
      onReadyEscalationEnabledChanged: (value) =>
          _update(() => _readyEscalationEnabled = value),
      readyEscalationMinutes: _readyEscalationMinutes,
      onReadyEscalationMinutesChanged: (value) =>
          _update(() => _readyEscalationMinutes = value),
      readyEscalationChannel: _readyEscalationChannel,
      onReadyEscalationChannelChanged: (value) =>
          _update(() => _readyEscalationChannel = value ?? 'call'),
      deliveryArrivingSoonEnabled: _deliveryArrivingSoonEnabled,
      onDeliveryArrivingSoonEnabledChanged: (value) =>
          _update(() => _deliveryArrivingSoonEnabled = value),
      deliveryArrivingSoonMinutes: _deliveryArrivingSoonMinutes,
      onDeliveryArrivingSoonMinutesChanged: (value) =>
          _update(() => _deliveryArrivingSoonMinutes = value),
      deliveryRateLimitPerHour: _deliveryRateLimitPerHour,
      onDeliveryRateLimitPerHourChanged: (value) =>
          _update(() => _deliveryRateLimitPerHour = value),
      defaultChannelByStatus: _defaultChannelByStatus,
      defaultTemplateIdByStatus: _defaultTemplateIdByStatus,
      templatesByStatus: _templatesByStatus,
      deliveryDefaultChannelByStatus: _deliveryDefaultChannelByStatus,
      deliveryDefaultTemplateIdByStatus: _deliveryDefaultTemplateIdByStatus,
      deliveryTemplatesByStatus: _deliveryTemplatesByStatus,
      onOrderStatusChanged: _setOrderStatusConfig,
      onDeliveryStatusChanged: _setDeliveryStatusConfig,
      onAddTemplate: _addTemplate,
      onRemoveTemplate: _removeTemplate,
      onSave: _save,
    );
  }
}
