part of 'mini_app_screen.dart';

mixin MiniAppStateBuildMenu
    on
        State<MiniAppScreen>,
        MiniAppStateGas,
        MiniAppStateBuildMenuGas,
        MiniAppStateBuildMenuChat {
  Widget _buildMenuLayout(SessionInfo session) {
    if (session.businessType == 'gas_station') {
      return _buildGasMenuLayout(session);
    }
    return _buildChatMenuLayout(session);
  }
}
