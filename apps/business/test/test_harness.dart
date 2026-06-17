import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

Widget businessTestApp(
  Widget child, {
  List<Override> overrides = const [],
}) {
  return ProviderScope(
    overrides: overrides,
    child: ShadApp.custom(
      theme: ShadThemeData(
        brightness: Brightness.light,
        colorScheme: const ShadRedColorScheme.light(),
      ),
      appBuilder: (_) => MaterialApp(
        home: ShadAppBuilder(child: child),
      ),
    ),
  );
}
