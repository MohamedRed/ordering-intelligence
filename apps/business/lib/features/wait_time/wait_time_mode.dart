enum WaitTimeMode { overall, lunch, dinner }

extension WaitTimeModeLabel on WaitTimeMode {
  String get label {
    switch (this) {
      case WaitTimeMode.overall:
        return 'Overall';
      case WaitTimeMode.lunch:
        return 'Lunch';
      case WaitTimeMode.dinner:
        return 'Dinner';
    }
  }
}
