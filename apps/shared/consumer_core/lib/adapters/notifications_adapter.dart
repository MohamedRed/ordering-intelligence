abstract class NotificationsAdapter {
  Future<void> registerDevice({
    required String customerId,
    required String sessionId,
  });

  Future<void> unregisterDevice({
    required String sessionId,
  });
}
