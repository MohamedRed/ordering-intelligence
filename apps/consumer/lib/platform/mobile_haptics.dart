import 'package:consumer_ui/consumer_ui.dart';
import 'package:flutter/services.dart';

class MobileHaptics extends MiniAppHaptics {
  const MobileHaptics();

  @override
  void selection() {
    HapticFeedback.selectionClick();
  }

  @override
  void impact({String style = 'light'}) {
    switch (style) {
      case 'medium':
        HapticFeedback.mediumImpact();
        break;
      case 'heavy':
        HapticFeedback.heavyImpact();
        break;
      default:
        HapticFeedback.lightImpact();
    }
  }
}
