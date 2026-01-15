part of 'mini_app_screen.dart';

mixin MiniAppStateGroupOrdersView
    on
        State<MiniAppScreen>,
        MiniAppStateFields,
        MiniAppStateGroupOrdersActions,
        MiniAppStateGroupOrdersCheckout,
        MiniAppStateGroupOrdersShare {
  bool get _isGroupOrderHost {
    final session = _session;
    final groupOrder = _groupOrder;
    if (session == null || groupOrder == null) return false;
    if (groupOrder.host.userId.isNotEmpty &&
        groupOrder.host.userId == session.userId) {
      return true;
    }
    return groupOrder.host.accountId.isNotEmpty &&
        groupOrder.host.accountId == session.accountId;
  }

  bool get _isSplitPayment =>
      (_groupOrder?.paymentMode ?? _groupOrderPaymentMode) ==
      'split_by_participant';

  bool get _isCashPayment =>
      (_groupOrder?.paymentMethod.isNotEmpty == true
          ? _groupOrder!.paymentMethod
          : _groupOrderPaymentMethod) ==
      'cash';

  Widget? buildGroupOrderPanel() {
    if (_session == null) return null;
    if (_session?.storeId.isEmpty == true) {
      return null;
    }
    if (_groupOrder == null && !_pendingStartGroupOrder) {
      return null;
    }
    String? primaryLabel;
    VoidCallback? primaryAction;
    String? secondaryLabel;
    VoidCallback? secondaryAction;
    var shareTargets = const <MiniAppShareTarget>[];

    String? codeText;
    if (_groupOrder != null) {
      if (_isGroupOrderHost) {
        shareTargets = _platform.groupOrderShareTargets();
        if (shareTargets.isEmpty) {
          secondaryLabel = 'Share';
          secondaryAction = () {
            _shareGroupOrder();
          };
        }
      }
      final status = _groupOrder!.status;
      if (status == 'open' && _isGroupOrderHost) {
        if (_isCashPayment) {
          primaryLabel = 'Lock order';
          primaryAction = () async {
            await _lockGroupOrder();
            await _submitGroupOrder();
          };
        } else {
          primaryLabel = _isSplitPayment ? 'Lock order' : 'Lock & pay';
          primaryAction = () async {
            await _lockGroupOrder();
            if (!_isSplitPayment) {
              await _checkoutGroupOrder();
            }
          };
        }
      } else if (status == 'locked' || status == 'payment_pending') {
        if (_isCashPayment) {
          if (_isGroupOrderHost) {
            primaryLabel = 'Submit order';
            primaryAction = _submitGroupOrder;
          }
        } else if (_isSplitPayment) {
          primaryLabel = 'Pay my share';
          primaryAction = () => _checkoutGroupOrder(
            participantId: _groupOrderParticipantId ?? _session!.userId,
          );
        } else if (_isGroupOrderHost) {
          primaryLabel = 'Pay now';
          primaryAction = _checkoutGroupOrder;
        }
      }
      if (_isGroupOrderHost) {
        final inviteId = _latestInviteId;
        if (inviteId != null && inviteId.isNotEmpty) {
          codeText = 'Invite code: $inviteId';
        } else {
          codeText = 'Tap Share to create an invite';
        }
      } else {
        codeText = 'You joined this group order';
      }
    }

    return GroupOrderPanel(
      groupOrder: _groupOrder,
      paymentMode: _groupOrderPaymentMode,
      paymentMethod: _groupOrderPaymentMethod,
      busy: _groupOrderBusy,
      error: _groupOrderError,
      codeText: codeText,
      collapsed: _groupOrderCollapsed,
      onToggle: () => setState(() {
        _groupOrderCollapsed = !_groupOrderCollapsed;
      }),
      onPaymentModeChanged: (mode) => setState(() {
        _groupOrderPaymentMode = mode;
      }),
      onPaymentMethodChanged: (method) => setState(() {
        _groupOrderPaymentMethod = method;
      }),
      onCreate: _createGroupOrder,
      primaryActionLabel: primaryLabel,
      onPrimaryAction: primaryAction,
      secondaryActionLabel: secondaryLabel,
      onSecondaryAction: secondaryAction,
      shareTargets: shareTargets,
      onShareTarget: shareTargets.isEmpty ? null : _shareGroupOrderToTarget,
    );
  }
}
