part of 'mini_app_screen.dart';

mixin MiniAppStateBuildMenuGas
    on
        State<MiniAppScreen>,
        MiniAppStateFields,
        MiniAppStateMenu,
        MiniAppStateStore,
        MiniAppStateCart,
        MiniAppStateSignOut,
        MiniAppStateGas,
        MiniAppStateGasActions {
  Widget _buildGasMenuLayout(SessionInfo session) {
    Widget menuBody;
    if (_loadingMenu) {
      menuBody = const Center(child: CircularProgressIndicator());
    } else if (_menuError != null) {
      menuBody = CenteredMessage(
        title: 'Menu unavailable',
        description: _menuError!,
        actionLabel: 'Retry',
        onAction: () => _loadMenu(session.storeId),
      );
    } else if (_menu == null) {
      menuBody = CenteredMessage(
        title: 'No menu available',
        description: 'Try another store.',
        actionLabel: 'Change store',
        onAction: _changeStore,
      );
    } else {
      menuBody = GasOrderView(
        key: const ValueKey('browse'),
        grades: _fuelGrades,
        selectedGrade: _selectedFuelGrade,
        paymentFlow: _fuelPaymentFlow,
        prepayMode: _fuelPrepayMode,
        amountController: _fuelAmountController,
        litersController: _fuelLitersController,
        preauthController: _fuelPreauthController,
        isSubmitting: _placingFuelOrder,
        errorMessage: _fuelOrderError,
        formatPrice: _formatPrice,
        preauthHint: _fuelPreauthHint(),
        onSelectGrade: _selectFuelGrade,
        onPaymentFlowChanged: (flow) => setState(() => _fuelPaymentFlow = flow),
        onPrepayModeChanged: (mode) => setState(() => _fuelPrepayMode = mode),
        onPreauthChanged: (_) {
          if (!_fuelPreauthEdited) {
            setState(() => _fuelPreauthEdited = true);
          }
        },
        onSubmit: _placeFuelOrder,
      );
    }
    return Column(
      children: [
        ChatHeaderCard(
          storeName: session.storeName,
          subtitle: 'Complete your fuel order.',
          cartLabel: null,
          onChangeStore: _changeStore,
          signOutLabel: _signOutLabel,
          onSignOut: _signOutLabel == null ? null : _requestSignOut,
          signingOut: _signingOut,
        ),
        const SizedBox(height: 12),
        Expanded(child: menuBody),
      ],
    );
  }
}
