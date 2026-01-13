part of 'mini_app_screen.dart';

mixin MiniAppStateBuildMenu
    on
        State<MiniAppScreen>,
        MiniAppStateFields,
        MiniAppStateMenu,
        MiniAppStateStore,
        MiniAppStateCart,
        MiniAppStateCartSheet,
        MiniAppStateSearch,
        MiniAppStateReorders,
        MiniAppStateIdentityUI,
        MiniAppStateSignOut,
        MiniAppStateGroupOrdersView,
        MiniAppStateGas,
        MiniAppStateGasActions,
        MiniAppStateChatState,
        MiniAppStateChatActions,
        MiniAppStateChatAudio {
  Widget _buildMenuLayout(SessionInfo session) {
    final isGas = session.businessType == 'gas_station';
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
      if (isGas) {
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
      } else {
        final items = _menu!.items;
        final visibleItems = _activeCategory.isEmpty || _activeCategory == 'All'
            ? items
            : items.where((item) => item.category == _activeCategory).toList();
        menuBody = MenuView(
          key: const ValueKey('browse'),
          storeName: session.storeName,
          showHeader: false,
          categories: _categories,
          activeCategory: _activeCategory,
          items: visibleItems,
          recommendations: _storeRecommendations,
          identityPanel: buildIdentityPanel(),
          groupOrderPanel: buildGroupOrderPanel(),
          onChangeStore: _changeStore,
          onCategorySelected: (category) {
            setState(() {
              _activeCategory = category;
            });
            _scrollMenuToItemsStart();
          },
          onAddItem: _handleAdd,
          onSelectRecommendation: _applyRecommendedOrder,
          cartItemCount: _cartItemCount,
          cartTotalLabel: _formatPrice(_cartTotalCents),
          onOpenCart: _openCartSheet,
          formatPrice: _formatPrice,
          scrollController: _menuScrollController,
          itemsAnchorKey: _menuItemsAnchorKey,
        );
      }
    }
    final subtitle = _groupOrder != null
        ? 'Group order active • ${_groupOrder!.participants.length} joined'
        : 'Chat with Live or browse the menu to order.';
    final cartLabel = _cartItemCount == 0
        ? 'Cart is empty'
        : 'Cart • $_cartItemCount item(s) • ${_formatPrice(_cartTotalCents)}';
    final chatView = ChatView(
      key: const ValueKey('chat'),
      messages: _chatMessages,
      controller: _chatController,
      scrollController: _chatScrollController,
      onSend: _sendChatText,
      onOptionSelected: _handleOptionSelected,
      onToggleRecording: _toggleRecording,
      isLoading: _chatBusy,
      isRecording: _chatRecording,
      isSending: _chatBusy,
      canRecord: _audioRecorder != null,
    );

    return Column(
      children: [
        ChatHeaderCard(
          storeName: session.storeName,
          subtitle: subtitle,
          cartLabel: cartLabel,
          onOpenCart: _cartItemCount == 0 ? null : _openCartSheet,
          onChangeStore: _changeStore,
          signOutLabel: _signOutLabel,
          onSignOut: _signOutLabel == null ? null : _requestSignOut,
          signingOut: _signingOut,
        ),
        const SizedBox(height: 12),
        ChatSegmentedControl(
          segment: _activeSegment,
          onChanged: (segment) => setState(() => _activeSegment = segment),
        ),
        const SizedBox(height: 12),
        Expanded(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 220),
            child: _activeSegment == MiniAppSegment.chat ? chatView : menuBody,
          ),
        ),
      ],
    );
  }

  void _scrollMenuToItemsStart() {
    const categoryHeaderHeight = 56.0;
    final context = _menuItemsAnchorKey.currentContext;
    if (context == null) {
      return;
    }
    void animateToAnchor() {
      final box = context.findRenderObject();
      if (box == null) {
        return;
      }
      final viewport = RenderAbstractViewport.of(box);
      final offset = viewport.getOffsetToReveal(box, 0).offset;
      final target = (offset - categoryHeaderHeight)
          .clamp(0.0, _menuScrollController.position.maxScrollExtent);
      _menuScrollController.animateTo(
        target,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    }
    if (_menuScrollController.hasClients) {
      animateToAnchor();
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_menuScrollController.hasClients) {
        animateToAnchor();
      }
    });
  }
}
