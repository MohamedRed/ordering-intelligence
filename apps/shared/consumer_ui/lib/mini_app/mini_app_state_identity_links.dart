part of 'mini_app_screen.dart';

mixin MiniAppStateIdentityLinks
    on
        State<MiniAppScreen>,
        MiniAppStateFields,
        MiniAppStateIdentity,
        MiniAppStateIdentityActions {
  Future<void> beginLinkFlow(String targetChannel) async {
    final targetLabel = channelLabel(targetChannel);
    final consent = await _confirmLinkConsent(targetLabel);
    if (!consent) return;
    final token = await _startIdentityLinkRequest(
      targetChannel: targetChannel,
      consent: true,
    );
    if (token == null || token.token.isEmpty) return;
    final linkUri = buildLinkUrl(targetChannel, token.token);
    openLink(targetChannel, linkUri);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Finish linking on $targetLabel.')),
    );
  }

  Future<bool> _confirmLinkConsent(String label) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Link accounts'),
        content: Text(
          'This will merge your order history across channels. Continue linking $label?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Link'),
          ),
        ],
      ),
    );
    return confirmed == true;
  }

  String currentChannel() => _platform.currentChannel(_launchContext);

  String channelLabel(String channel) => _platform.labelForChannel(channel);

  Uri buildLinkUrl(String targetChannel, String token) {
    return _platform.buildLinkUri(
      context: _launchContext,
      targetChannel: targetChannel,
      token: token,
      session: _session,
    );
  }

  void openLink(String channel, Uri uri) {
    _platform.openLink(channel, uri);
  }
}
