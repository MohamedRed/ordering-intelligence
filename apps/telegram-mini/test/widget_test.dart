import 'package:test/test.dart';
import 'package:telegram_mini_app/app_config.dart';

void main() {
  test('resolveApiBase defaults to gateway URL', () {
    expect(
      resolveApiBase(),
      'https://channel-gateway-230152279015.us-central1.run.app',
    );
  });

  test('resolveWebAppPathPrefix defaults to Telegram path', () {
    expect(resolveWebAppPathPrefix(), '/telegram/webapp');
  });

  test('resolveDiscordClientId defaults to configured value', () {
    expect(resolveDiscordClientId(), '1457874399339347988');
  });
}
