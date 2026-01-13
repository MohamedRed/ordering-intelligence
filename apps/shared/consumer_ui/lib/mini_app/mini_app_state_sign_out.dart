part of 'mini_app_screen.dart';

mixin MiniAppStateSignOut on State<MiniAppScreen>, MiniAppStateFields {
  bool _signingOut = false;

  String? get _signOutLabel => _platform.signOutLabel();

  Future<void> _requestSignOut() async {
    final label = _signOutLabel;
    if (label == null || _signingOut) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(label),
        content: const Text('Are you sure you want to sign out?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Sign out'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() => _signingOut = true);
    try {
      await _platform.signOut();
    } finally {
      if (mounted) setState(() => _signingOut = false);
    }
  }
}
