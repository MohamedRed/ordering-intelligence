import 'store_settings_defaults.dart';
import 'store_settings_template_row.dart';

Map<String, dynamic> buildStoreSettingsPayload({
  required int defaultWaitMinutes,
  required bool readyEscalationEnabled,
  required int readyEscalationMinutes,
  required String readyEscalationChannel,
  required bool deliveryArrivingSoonEnabled,
  required int deliveryArrivingSoonMinutes,
  required int deliveryRateLimitPerHour,
  required bool deliveryEnabled,
  required String deliveryFleetMode,
  required String storeAddress,
  required String storeLat,
  required String storeLng,
  required String marketplaceOffer,
  required int marketplaceOfferCents,
  required Map<String, String> defaultChannelByStatus,
  required Map<String, String> defaultTemplateIdByStatus,
  required Map<String, List<TemplateRow>> templatesByStatus,
  required Map<String, String> deliveryDefaultChannelByStatus,
  required Map<String, String> deliveryDefaultTemplateIdByStatus,
  required Map<String, List<TemplateRow>> deliveryTemplatesByStatus,
}) {
  return {
    'order_comms': {
      'default_wait_minutes': defaultWaitMinutes,
      'statuses': serializeCommsStatuses(
        orderCommsStatuses,
        defaultChannelByStatus,
        defaultTemplateIdByStatus,
        templatesByStatus,
      ),
      'ready_escalation_enabled': readyEscalationEnabled,
      'ready_escalation_minutes': readyEscalationMinutes,
      'ready_escalation_channel': readyEscalationChannel,
    },
    'delivery_comms': {
      'rate_limit_per_hour': deliveryRateLimitPerHour,
      'arriving_soon_enabled': deliveryArrivingSoonEnabled,
      'arriving_soon_eta_threshold_minutes': deliveryArrivingSoonMinutes,
      'statuses': serializeCommsStatuses(
        deliveryCommsStatuses,
        deliveryDefaultChannelByStatus,
        deliveryDefaultTemplateIdByStatus,
        deliveryTemplatesByStatus,
      ),
    },
    'delivery_settings': {
      'enabled': deliveryEnabled,
      'fleet_mode': deliveryFleetMode,
      'store_location': buildStoreLocation(
        address: storeAddress,
        lat: storeLat,
        lng: storeLng,
      ),
      'marketplace_offer_cents':
          int.tryParse(marketplaceOffer.trim()) ?? marketplaceOfferCents,
    },
  };
}

Map<String, dynamic> buildStoreLocation({
  required String address,
  required String lat,
  required String lng,
}) {
  final location = <String, dynamic>{'formatted': address.trim()};
  final parsedLat = double.tryParse(lat.trim());
  final parsedLng = double.tryParse(lng.trim());
  if (parsedLat != null && parsedLng != null) {
    location['lat'] = parsedLat;
    location['lng'] = parsedLng;
  }
  return location;
}
