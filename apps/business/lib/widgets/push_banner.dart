import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

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
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: ShadAlert(
        icon: const Icon(Icons.notifications_active_outlined),
        title: Text(title),
        description: body.isNotEmpty
            ? Text(body, maxLines: 2, overflow: TextOverflow.ellipsis)
            : null,
        trailing: ShadButton.ghost(
          size: ShadButtonSize.sm,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          onPressed: () => setState(() => _message = null),
          child: const Icon(Icons.close, size: 16),
        ),
      ),
    );
  }
}
