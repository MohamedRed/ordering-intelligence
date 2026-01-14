part of 'mini_app_screen.dart';

mixin MiniAppStateBuildMenuChat
    on
        State<MiniAppScreen>,
        MiniAppStateFields,
        MiniAppStateMenu,
        MiniAppStateStore,
        MiniAppStateCart,
        MiniAppStateCartSheet,
        MiniAppStateGroupOrdersView,
        MiniAppStateDelivery,
        MiniAppStateChatState,
        MiniAppStateChatSelection,
        MiniAppStateChatSeed,
        MiniAppStateChatComms,
        MiniAppStateChatActions,
        MiniAppStateChatParticipants,
        MiniAppStateChatAudio {
  Widget _buildChatMenuLayout(SessionInfo session, {VoidCallback? onOpenMenu}) {
    if (_menu != null) {
      _seedMenuChatIfNeeded();
    }
    final subtitle = _groupOrder != null
        ? 'Group order active • ${_groupOrder!.participants.length} joined'
        : 'Chat-based ordering with quick picks.';
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
      onOptionsConfirmed: _handleMultiOptionsSelected,
      onProductSelected: _handleProductSelected,
      onToggleRecording: _toggleRecording,
      isLoading: _chatBusy,
      isRecording: _chatRecording,
      isSending: _chatBusy,
      canRecord: _audioRecorder != null,
    );
    final groupOrderPanel = buildGroupOrderPanel();

    return Column(
      children: [
        ChatHeaderCard(
          storeName: session.storeName,
          subtitle: subtitle,
          cartLabel: cartLabel,
          onOpenCart: _cartItemCount == 0 ? null : _openCartSheet,
          onChangeStore: _changeStore,
          onOpenMenu: onOpenMenu,
        ),
        const SizedBox(height: 12),
        if (_menuError != null) ...[
          ShadAlert.destructive(
            title: const Text('Menu unavailable'),
            description: Text(_menuError!),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: ShadButton.outline(
              onPressed: () => _loadMenu(session.storeId),
              child: const Text('Retry menu'),
            ),
          ),
        ] else if (_loadingMenu)
          const LinearProgressIndicator(minHeight: 2),
        if (_menuError != null || _loadingMenu) const SizedBox(height: 12),
        ChatContextBar(
          categories: _categories,
          activeCategory: _activeCategory,
          onCategorySelected: _handleCategorySelected,
          selectedProduct: _selectedProduct,
          onClearProduct: _selectedProduct == null
              ? null
              : () => setState(() => _selectedProduct = null),
          participants: _groupOrder?.participants ?? const [],
          selectedParticipantId: _groupOrderSelectedParticipantId,
          onParticipantSelected: _handleParticipantSelected,
          deliveryEnabled: _deliveryEnabled,
          isDelivery: _isDeliverySelected,
          onFulfillmentChanged: (isDelivery) => _toggleDelivery(isDelivery),
        ),
        if (groupOrderPanel != null) ...[
          const SizedBox(height: 12),
          groupOrderPanel,
        ],
        const SizedBox(height: 12),
        Expanded(child: chatView),
      ],
    );
  }
}
