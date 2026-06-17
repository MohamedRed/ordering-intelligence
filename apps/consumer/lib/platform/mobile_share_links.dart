import 'dart:async';

import 'package:consumer_core/consumer_core.dart';
import 'package:consumer_ui/consumer_ui.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

class MobileShareLinks {
  const MobileShareLinks({required String facebookAppId})
    : _facebookAppId = facebookAppId;

  final String _facebookAppId;

  List<MiniAppLinkTarget> linkTargets() => defaultMiniAppLinkTargets;

  String labelForChannel(String channel) {
    switch (channel.toLowerCase()) {
      case 'discord':
        return 'Discord';
      case 'snapchat':
        return 'Snapchat';
      default:
        return 'Telegram';
    }
  }

  Uri buildLinkUri({
    required MiniAppLaunchContext context,
    required String targetChannel,
    required String token,
    SessionInfo? session,
  }) {
    final base = context.baseUri;
    final params = Map<String, String>.from(base.queryParameters);
    params['platform'] = targetChannel;
    params['linkToken'] = token;
    if (session != null && session.storeId.isNotEmpty) {
      params['storeId'] = session.storeId;
    }
    params.remove('code');
    params.remove('state');
    params.remove('error');
    params.remove('error_description');
    return base.replace(queryParameters: params);
  }

  void openLink(String channel, Uri uri) {
    unawaited(launchUrl(uri, mode: LaunchMode.externalApplication));
  }

  Future<void> shareGroupOrderLink(Uri uri, {required String text}) async {
    await Share.share('$text\n${uri.toString()}');
  }

  List<MiniAppShareTarget> groupOrderShareTargets() {
    return [
      const MiniAppShareTarget(id: 'system', label: 'Share'),
      const MiniAppShareTarget(id: 'telegram', label: 'Telegram'),
      const MiniAppShareTarget(id: 'whatsapp', label: 'WhatsApp'),
      if (_facebookAppId.isNotEmpty)
        const MiniAppShareTarget(id: 'messenger', label: 'Messenger'),
      const MiniAppShareTarget(id: 'discord', label: 'Discord'),
      const MiniAppShareTarget(id: 'sms', label: 'SMS'),
    ];
  }

  Future<void> shareGroupOrderLinkToTarget(
    MiniAppShareTarget target,
    Uri uri, {
    required String text,
  }) async {
    final shareText = '$text\n${uri.toString()}';
    switch (target.id) {
      case 'system':
        await shareGroupOrderLink(uri, text: text);
        return;
      case 'telegram':
        await _launchShareUri(
          _telegramShareUri(uri, text),
          fallbackText: shareText,
        );
        return;
      case 'whatsapp':
        await _launchShareUri(
          _whatsAppShareUri(shareText),
          fallbackText: shareText,
        );
        return;
      case 'messenger':
        await _launchShareUri(_messengerShareUri(uri), fallbackText: shareText);
        return;
      case 'sms':
        await _launchShareUri(_smsShareUri(shareText), fallbackText: shareText);
        return;
      case 'discord':
        await shareGroupOrderLink(uri, text: text);
        return;
      default:
        await shareGroupOrderLink(uri, text: text);
    }
  }

  Uri _telegramShareUri(Uri inviteUri, String text) {
    return Uri.parse(
      'https://t.me/share/url?url=${Uri.encodeComponent(inviteUri.toString())}&text=${Uri.encodeComponent(text)}',
    );
  }

  Uri _whatsAppShareUri(String text) {
    return Uri.parse('https://wa.me/?text=${Uri.encodeComponent(text)}');
  }

  Uri _messengerShareUri(Uri inviteUri) {
    final params = {'link': inviteUri.toString(), 'app_id': _facebookAppId};
    return Uri(scheme: 'fb-messenger', host: 'share', queryParameters: params);
  }

  Uri _smsShareUri(String text) {
    return Uri(scheme: 'sms', queryParameters: {'body': text});
  }

  Future<void> _launchShareUri(Uri uri, {required String fallbackText}) async {
    final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!launched) {
      await Share.share(fallbackText);
    }
  }
}
