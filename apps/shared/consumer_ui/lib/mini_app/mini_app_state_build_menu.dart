part of 'mini_app_screen.dart';

mixin MiniAppStateBuildMenu
    on
        State<MiniAppScreen>,
        MiniAppStateGas,
        MiniAppStateBuildMenuGas,
        MiniAppStateBuildMenuChat {
  Widget _buildMenuLayout(SessionInfo session, {VoidCallback? onOpenMenu}) {
    if (session.businessType == 'gas_station') {
      return _buildGasMenuLayout(session, onOpenMenu: onOpenMenu);
    }
    return _buildChatMenuLayout(session, onOpenMenu: onOpenMenu);
  }
}
