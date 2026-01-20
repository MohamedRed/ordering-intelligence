import 'package:flutter/semantics.dart';
import 'package:flutter/widgets.dart';

SemanticsHandle? _ciSemanticsHandle;

void enableCiSemantics() {
  const enabled = bool.fromEnvironment('CI_FORCE_SEMANTICS');
  if (!enabled) return;
  WidgetsBinding.instance.addPostFrameCallback((_) {
    _ciSemanticsHandle ??= WidgetsBinding.instance.ensureSemantics();
  });
}
