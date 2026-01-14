part of 'mini_app_screen.dart';

mixin MiniAppStateBuild
    on
        State<MiniAppScreen>,
        MiniAppStateFields,
        MiniAppStateSearch,
        MiniAppStateStoreSearchChat,
        MiniAppStateHomeChat,
        MiniAppStateStore,
        MiniAppStateMenu,
        MiniAppStateCart,
        MiniAppStateGroupOrdersView,
        MiniAppStateOrder,
        MiniAppStateGasPumpActions,
        MiniAppStateBuildMenu,
        MiniAppStateSignOut,
        MiniAppStateLifecycle {
  Widget buildMiniApp(BuildContext context) {
    final wrapSafeArea = widget.platform.wrapSafeArea;
    if (_loadingSession) {
      return Scaffold(
        body: wrapSafeArea(const Center(child: CircularProgressIndicator())),
      );
    }
    if (_sessionError != null) {
      return Scaffold(
        body: wrapSafeArea(
          CenteredMessage(
            title: 'Unable to start session',
            description: _sessionError!,
            actionLabel: 'Retry',
            onAction: _bootstrap,
          ),
        ),
      );
    }
    if (_orderConfirmation != null) {
      if (_session?.businessType == 'gas_station') {
        return Scaffold(
          body: wrapSafeArea(
            GasOrderConfirmation(
              order: _orderConfirmation!,
              pumpController: _pumpNumberController,
              onSubmitPump: _submitPumpNumber,
              onNewOrder: _resetOrder,
              isSubmitting: _fuelPumpSubmitting,
              errorMessage: _fuelOrderError,
            ),
          ),
        );
      }
      return Scaffold(
        body: wrapSafeArea(
          OrderConfirmation(
            order: _orderConfirmation!,
            onNewOrder: _resetOrder,
            updatesLabel: _orderUpdatesLabel,
            onUpdates: _orderUpdatesLabel == null ? null : _handleOrderUpdates,
          ),
        ),
      );
    }
    final session = _session;
    if (session == null || session.storeId.isEmpty) {
      if (_shouldShowGroupOrderLoading) {
        return Scaffold(
          body: wrapSafeArea(const Center(child: CircularProgressIndicator())),
        );
      }
      _seedHomeChatIfNeeded();
      return Scaffold(
        body: wrapSafeArea(
          StoreSearchChatView(
            messages: _chatMessages,
            controller: _searchController,
            searching: _searching,
            searchResults: _searchResults,
            searchError: _searchError,
            onSend: _sendStoreSearchMessage,
            onOptionSelected: _handleStoreSearchOptionSelected,
            onOptionsConfirmed: _handleStoreSearchOptionsConfirmed,
            onSelectSuggestion: _selectStoreFromSearchSuggestion,
            onBack: _storeSearchMode ? _exitStoreSearchMode : null,
            signOutLabel: _signOutLabel,
            onSignOut: _signOutLabel == null ? null : _requestSignOut,
            signingOut: _signingOut,
          ),
        ),
      );
    }
    return Scaffold(body: wrapSafeArea(_buildMenuLayout(session)));
  }

  bool get _shouldShowGroupOrderLoading {
    if (_groupOrder != null) {
      return true;
    }
    if (!_groupOrderBusy) return false;
    return (_pendingInviteId?.isNotEmpty ?? false) ||
        (_pendingJoinCode?.isNotEmpty ?? false) ||
        (_pendingGroupOrderId?.isNotEmpty ?? false);
  }
}
