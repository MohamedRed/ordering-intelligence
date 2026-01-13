import 'package:flutter/material.dart';
import 'app/telegram_mini_app.dart';
import 'telegram/telegram_webapp.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  TelegramWebApp.ready();
  runApp(const TelegramMiniApp());
}
