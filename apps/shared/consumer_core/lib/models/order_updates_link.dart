class OrderUpdatesLink {
  final bool linked;
  final bool messageSent;
  final bool needsUserStart;

  const OrderUpdatesLink({
    required this.linked,
    required this.messageSent,
    required this.needsUserStart,
  });

  factory OrderUpdatesLink.fromJson(Map<String, dynamic> json) {
    return OrderUpdatesLink(
      linked: json['linked'] == true ||
          json['linked']?.toString().toLowerCase() == 'true',
      messageSent: json['messageSent'] == true ||
          json['messageSent']?.toString().toLowerCase() == 'true',
      needsUserStart: json['needsUserStart'] == true ||
          json['needsUserStart']?.toString().toLowerCase() == 'true',
    );
  }
}
