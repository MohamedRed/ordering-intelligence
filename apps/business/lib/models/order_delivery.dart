import 'order_delivery_models.dart';

class OrderDelivery {
  final String fleetMode;
  final String trackingUrl;
  final String assignmentStatus;
  final String assignedDriverId;
  final String assignedRouteId;
  final String deliveryStatusSummary;
  final DeliveryAddress? dropoffAddress;
  final DeliveryLatLng? dropoffLatLng;
  final DeliveryQuote? quote;
  final bool customerPaysDeliveryFee;
  final int deliveryFeeCentsChargedToCustomer;
  final String providerDeliveryId;

  const OrderDelivery({
    required this.fleetMode,
    required this.trackingUrl,
    required this.assignmentStatus,
    required this.assignedDriverId,
    required this.assignedRouteId,
    required this.deliveryStatusSummary,
    required this.dropoffAddress,
    required this.dropoffLatLng,
    required this.quote,
    required this.customerPaysDeliveryFee,
    required this.deliveryFeeCentsChargedToCustomer,
    required this.providerDeliveryId,
  });

  factory OrderDelivery.fromJson(Map<String, dynamic> json) {
    final addressRaw = json['dropoffAddress'];
    final dropoffAddress = addressRaw is Map
        ? DeliveryAddress.fromJson(addressRaw.cast<String, dynamic>())
        : null;
    final latLngRaw = json['dropoffLatLng'];
    final dropoffLatLng = latLngRaw is Map
        ? DeliveryLatLng.fromJson(latLngRaw.cast<String, dynamic>())
        : null;
    final quoteRaw = json['quote'];
    final quote = quoteRaw is Map
        ? DeliveryQuote.fromJson(quoteRaw.cast<String, dynamic>())
        : null;
    return OrderDelivery(
      fleetMode: (json['fleetMode'] as String?)?.trim() ?? '',
      trackingUrl: (json['trackingUrl'] as String?)?.trim() ?? '',
      assignmentStatus: (json['assignmentStatus'] as String?)?.trim() ?? '',
      assignedDriverId: (json['assignedDriverId'] as String?)?.trim() ?? '',
      assignedRouteId: (json['assignedRouteId'] as String?)?.trim() ?? '',
      deliveryStatusSummary:
          (json['deliveryStatusSummary'] as String?)?.trim() ?? '',
      dropoffAddress: dropoffAddress,
      dropoffLatLng: dropoffLatLng,
      quote: quote,
      customerPaysDeliveryFee: json['customerPaysDeliveryFee'] == true,
      deliveryFeeCentsChargedToCustomer:
          (json['deliveryFeeCentsChargedToCustomer'] is num)
              ? (json['deliveryFeeCentsChargedToCustomer'] as num).toInt()
              : 0,
      providerDeliveryId: (json['providerDeliveryId'] as String?)?.trim() ?? '',
    );
  }
}
