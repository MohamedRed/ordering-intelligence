import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Lightweight in-app banner for foreground notifications.
class PushBanner extends ConsumerStatefulWidget {
  const PushBanner({super.key});

  @override
  ConsumerState<PushBanner> createState() => _PushBannerState();
}

class _PushBannerState extends ConsumerState<PushBanner> {
  RemoteMessage? _message;

  @override
  void initState() {
    super.initState();
    FirebaseMessaging.onMessage.listen((message) {
      setState(() => _message = message);
      // auto-hide after few seconds
      Future.delayed(const Duration(seconds: 5), () {
        if (mounted && _message == message) setState(() => _message = null);
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_message == null) return const SizedBox.shrink();
    final title = _message!.notification?.title ?? 'New update';
    final body = _message!.notification?.body ?? '';
    return Material(
      elevation: 2,
      color: Colors.blueGrey.shade50,
      child: InkWell(
        onTap: () {
          // In future, deep-link to specific order via data[orderId]
          setState(() => _message = null);
        },
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              const Icon(Icons.notifications_active_outlined,
                  color: Colors.blueGrey),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                    if (body.isNotEmpty)
                      Text(body, maxLines: 2, overflow: TextOverflow.ellipsis),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => setState(() => _message = null),
              )
            ],
          ),
        ),
      ),
    );
  }
}
