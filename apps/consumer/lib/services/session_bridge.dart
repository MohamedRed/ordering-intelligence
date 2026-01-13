import 'package:consumer_core/consumer_core.dart';
import 'package:flutter/services.dart';

class SessionBridge {
  SessionBridge._();

  static const MethodChannel _channel =
      MethodChannel('com.orderingintelligence.consumer/session_bridge');

  static Future<void> save(SessionInfo session) async {
    try {
      await _channel.invokeMethod('saveSession', {
        'sessionId': session.sessionId,
        'customerId': session.customerId,
        'tenantId': session.tenantId,
        'accountId': session.accountId,
        'userId': session.userId,
        'displayName': session.displayName,
        'storeId': session.storeId,
        'storeName': session.storeName,
        'businessType': session.businessType,
        'currency': session.currency,
        'fuelDefaultPrepayCents': session.fuelDefaultPrepayCents,
        'fuelPreauthCapCents': session.fuelPreauthCapCents,
      });
    } catch (_) {}
  }

  static Future<void> clear() async {
    try {
      await _channel.invokeMethod('clearSession');
    } catch (_) {}
  }

  static Future<void> saveHandoffLink(String link) async {
    try {
      await _channel.invokeMethod('saveHandoffLink', {'link': link});
    } catch (_) {}
  }

  static Future<String?> loadHandoffLink() async {
    try {
      final result = await _channel.invokeMethod('loadHandoffLink');
      return result?.toString();
    } catch (_) {
      return null;
    }
  }

  static Future<void> clearHandoffLink() async {
    try {
      await _channel.invokeMethod('clearHandoffLink');
    } catch (_) {}
  }

  static Future<Map<String, dynamic>?> load() async {
    try {
      final result = await _channel.invokeMethod('loadSession');
      if (result is Map) {
        return result.map(
          (key, value) => MapEntry(key.toString(), value),
        );
      }
      return null;
    } catch (_) {
      return null;
    }
  }
}
