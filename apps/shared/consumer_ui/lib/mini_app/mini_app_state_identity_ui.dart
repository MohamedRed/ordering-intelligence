part of 'mini_app_screen.dart';

mixin MiniAppStateIdentityUI
    on
        State<MiniAppScreen>,
        MiniAppStateFields,
        MiniAppStateIdentity,
        MiniAppStateIdentityLinks {
  Widget? buildIdentityPanel() {
    final session = _session;
    if (session == null || session.tenantId.isEmpty) {
      return null;
    }
    return AccountLinkPanel(
      profile: _customerProfile,
      loading: _loadingIdentity,
      error: _identityError,
      onRetry: _loadIdentity,
      onLink: _showLinkOptions,
      onUnlink: _confirmUnlink,
      linking: _linkingIdentity,
    );
  }

  Future<void> _showLinkOptions() async {
    final targets = _availableLinkTargets();
    if (targets.isEmpty) return;
    final selected = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: targets
              .map(
                (target) => ListTile(
                  title: Text(target.label),
                  subtitle: Text('Link your ${target.label} account'),
                  onTap: () => Navigator.pop(ctx, target.channel),
                ),
              )
              .toList(),
        ),
      ),
    );
    if (selected == null || selected.isEmpty) return;
    await beginLinkFlow(selected);
  }

  Future<void> _confirmUnlink(CustomerProfileIdentity identity) async {
    final label = channelLabel(identity.channel);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Unlink account'),
        content: Text('Stop linking your $label account?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Unlink'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await _unlinkIdentity(identity);
    }
  }

  List<MiniAppLinkTarget> _availableLinkTargets() {
    final current = currentChannel();
    final linked = _customerProfile?.linkedChannels
            .map((entry) => entry.channel.toLowerCase())
            .toSet() ??
        <String>{};
    final targets = <MiniAppLinkTarget>[];
    for (final entry in _platform.linkTargets()) {
      if (entry.channel == current || linked.contains(entry.channel)) continue;
      targets.add(entry);
    }
    return targets;
  }
}
