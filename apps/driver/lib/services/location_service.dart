import 'dart:async';
import 'dart:io';

import 'package:geolocator/geolocator.dart';

import 'dispatch_api.dart';

class LocationService {
  LocationService({
    required this.api,
    this.onPosition,
    this.onSent,
    this.onError,
    this.minSendInterval = const Duration(seconds: 30),
  });

  final DispatchDriverApi api;
  final void Function(Position position)? onPosition;
  final void Function(Position position)? onSent;
  final void Function(String message)? onError;
  final Duration minSendInterval;

  StreamSubscription<Position>? _subscription;
  DateTime? _lastSentAt;

  bool get isRunning => _subscription != null;

  Future<bool> ensurePermission() async {
    final enabled = await Geolocator.isLocationServiceEnabled();
    if (!enabled) {
      onError?.call('Location services are disabled');
      return false;
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied) {
      onError?.call('Location permission denied');
      return false;
    }
    if (permission == LocationPermission.deniedForever) {
      onError?.call('Location permission permanently denied');
      return false;
    }
    return true;
  }

  Future<bool> start() async {
    if (isRunning) return true;
    final ok = await ensurePermission();
    if (!ok) return false;

    final LocationSettings settings;
    if (Platform.isAndroid) {
      settings = AndroidSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 25,
        intervalDuration: const Duration(seconds: 15),
        foregroundNotificationConfig: const ForegroundNotificationConfig(
          notificationTitle: 'Driver location active',
          notificationText: 'Sharing location for dispatch.',
          notificationChannelName: 'Driver Location',
          setOngoing: true,
          enableWakeLock: true,
        ),
      );
    } else if (Platform.isIOS) {
      settings = AppleSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        distanceFilter: 25,
        activityType: ActivityType.automotiveNavigation,
        allowBackgroundLocationUpdates: true,
        showBackgroundLocationIndicator: true,
      );
    } else {
      settings = const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 25,
      );
    }

    _subscription = Geolocator.getPositionStream(locationSettings: settings)
        .listen(
          (position) async {
            onPosition?.call(position);
            final now = DateTime.now().toUtc();
            if (_lastSentAt == null ||
                now.difference(_lastSentAt!) >= minSendInterval) {
              try {
                await api.postLocation(
                  lat: position.latitude,
                  lng: position.longitude,
                  accuracyM: position.accuracy,
                );
                _lastSentAt = now;
                onSent?.call(position);
              } catch (e) {
                onError?.call(e.toString());
              }
            }
          },
          onError: (err) {
            onError?.call(err.toString());
          },
        );

    return true;
  }

  Future<void> stop() async {
    await _subscription?.cancel();
    _subscription = null;
  }
}
