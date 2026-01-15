part of 'mini_app_screen.dart';

mixin MiniAppStateBuildMenu
    on
        State<MiniAppScreen>,
        MiniAppStateGas,
        MiniAppStateBuildMenuGas,
        MiniAppStateBuildMenuBrowse,
        MiniAppStateBuildMenuChat {
  Widget _buildMenuLayout(SessionInfo session, {VoidCallback? onOpenMenu}) {
    if (session.storeId.isNotEmpty && session.businessType == 'gas_station') {
      return _buildGasMenuLayout(session, onOpenMenu: onOpenMenu);
    }
    if (session.storeId.isNotEmpty && _menuViewMode == MenuViewMode.browse) {
      return _buildBrowseMenuLayout(session, onOpenMenu: onOpenMenu);
    }
    return _buildChatMenuLayout(session, onOpenMenu: onOpenMenu);
  }
}
