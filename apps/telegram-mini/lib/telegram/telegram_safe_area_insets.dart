class TelegramSafeAreaInsets {
  const TelegramSafeAreaInsets({
    this.top = 0,
    this.bottom = 0,
    this.left = 0,
    this.right = 0,
  });

  final double top;
  final double bottom;
  final double left;
  final double right;

  TelegramSafeAreaInsets merge(TelegramSafeAreaInsets other) {
    return TelegramSafeAreaInsets(
      top: top > other.top ? top : other.top,
      bottom: bottom > other.bottom ? bottom : other.bottom,
      left: left > other.left ? left : other.left,
      right: right > other.right ? right : other.right,
    );
  }
}
