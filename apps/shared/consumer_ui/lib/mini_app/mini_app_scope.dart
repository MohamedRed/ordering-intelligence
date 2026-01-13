import 'package:flutter/widgets.dart';

import 'mini_app_platform.dart';

class MiniAppScope extends InheritedWidget {
  const MiniAppScope({
    super.key,
    required this.platform,
    required super.child,
  });

  final MiniAppPlatform platform;

  static MiniAppPlatform of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<MiniAppScope>();
    assert(scope != null, 'MiniAppScope not found in context');
    return scope!.platform;
  }

  @override
  bool updateShouldNotify(MiniAppScope oldWidget) {
    return platform != oldWidget.platform;
  }
}
