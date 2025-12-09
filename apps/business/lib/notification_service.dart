import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  String? _initialPayload;
  String? _selectedPayload;

  static const AndroidNotificationChannel _channel = AndroidNotificationChannel(
    'orders',
    'Orders',
    description: 'Order status updates',
    importance: Importance.high,
  );

  Future<void> init() async {
    const initSettingsAndroid =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    final initSettings = InitializationSettings(android: initSettingsAndroid);

    final launchDetails = await _plugin.getNotificationAppLaunchDetails();
    _initialPayload = launchDetails?.notificationResponse?.payload;

    await _plugin.initialize(initSettings,
        onDidReceiveNotificationResponse: (resp) {
      _selectedPayload = resp.payload;
    });

    await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(_channel);
  }

  Future<void> showRemoteMessage(RemoteMessage message) async {
    final notification = message.notification;
    if (notification == null) return;
    final androidDetails = AndroidNotificationDetails(
      _channel.id,
      _channel.name,
      channelDescription: _channel.description,
      importance: Importance.high,
      priority: Priority.high,
    );
    const details = NotificationDetails(android: androidDetails);
    await _plugin.show(
      notification.hashCode,
      notification.title,
      notification.body,
      details,
      payload: message.data['orderId'] ?? '',
    );
  }

  /// Returns and clears any pending payload (from launch or selection).
  String? takePayload() {
    final payload = _selectedPayload ?? _initialPayload;
    _selectedPayload = null;
    _initialPayload = null;
    return payload?.isNotEmpty == true ? payload : null;
  }
}
