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
        MiniAppStateStoreSearchChat,
        MiniAppStateChatSelection,
        MiniAppStateChatSeed,
        MiniAppStateChatComms,
        MiniAppStateChatActions,
        MiniAppStateChatParticipants,
        MiniAppStateChatAudio {
  Widget _buildChatMenuLayout(SessionInfo session, {VoidCallback? onOpenMenu}) {
    final hasStore = session.storeId.isNotEmpty;
    if (_menu != null && hasStore) {
      _seedMenuChatIfNeeded();
    }
    final subtitle = hasStore
        ? (_groupOrder != null
              ? 'Group order active • ${_groupOrder!.participants.length} joined'
              : 'Chat-based ordering with quick picks.')
        : 'Search by name or pick a recent order.';
    final cartLabel = hasStore
        ? (_cartItemCount == 0
              ? 'Cart is empty'
              : 'Cart • $_cartItemCount item(s) • ${_formatPrice(_cartTotalCents)}')
        : null;
    final controller = hasStore ? _chatController : _searchController;
    final footer = hasStore
        ? null
        : StoreSearchFooter(
            controller: _searchController,
            searching: _searching,
            searchResults: _searchResults,
            searchError: _searchError,
            onSelectSuggestion: _selectStoreFromSearchSuggestion,
          );
    final isBusy = hasStore ? _chatBusy : _searching;
    final groupOrderPanel = hasStore ? buildGroupOrderPanel() : null;
    final header = ChatHeaderCard(
      key: ValueKey(hasStore ? session.storeId : 'no-store'),
      storeName: hasStore ? session.storeName : 'Find a store',
      subtitle: subtitle,
      cartLabel: cartLabel,
      onOpenCart: hasStore
          ? (_cartItemCount == 0 ? null : _openCartSheet)
          : null,
      onChangeStore: hasStore ? _changeStore : null,
      onOpenMenu: onOpenMenu,
    );
    final contextBlock = hasStore
        ? Column(
            children: [
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
              if (_menuError != null || _loadingMenu)
                const SizedBox(height: 12),
              ChatContextPanel(
                expanded: _contextExpanded,
                onToggleExpanded: () => _setContextExpanded(!_contextExpanded),
                summaryText: _buildContextSummaryText(session),
                deliveryEnabled: _deliveryEnabled,
                isDelivery: _isDeliverySelected,
                onFulfillmentChanged: _toggleDelivery,
                expandedContent: Column(
                  children: [
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
                      onFulfillmentChanged: _toggleDelivery,
                    ),
                    if (groupOrderPanel != null) ...[
                      const SizedBox(height: 12),
                      groupOrderPanel,
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 12),
            ],
          )
        : const SizedBox.shrink();
    final chatView = ChatView(
      key: const ValueKey('chat'),
      messages: _chatMessages,
      controller: controller,
      scrollController: _chatScrollController,
      onSend: hasStore ? _sendChatText : _sendStoreSearchMessage,
      onOptionSelected: hasStore
          ? _handleOptionSelected
          : _handleStoreSearchOptionSelected,
      onOptionsConfirmed: hasStore
          ? _handleMultiOptionsSelected
          : _handleStoreSearchOptionsConfirmed,
      onProductSelected: hasStore ? _handleProductSelected : (_) {},
      onToggleRecording: hasStore ? _toggleRecording : () {},
      isLoading: isBusy,
      isRecording: hasStore ? _chatRecording : false,
      isSending: isBusy,
      canRecord: hasStore && _audioRecorder != null,
      footer: footer,
      summaryText: hasStore ? null : _buildChatSummaryText(session),
    );
    return Column(
      children: [
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 220),
          switchInCurve: Curves.easeOut,
          switchOutCurve: Curves.easeIn,
          child: header,
        ),
        const SizedBox(height: 12),
        AnimatedCrossFade(
          duration: const Duration(milliseconds: 220),
          sizeCurve: Curves.easeOut,
          crossFadeState: hasStore
              ? CrossFadeState.showSecond
              : CrossFadeState.showFirst,
          firstChild: const SizedBox.shrink(),
          secondChild: contextBlock,
        ),
        Expanded(child: chatView),
      ],
    );
  }

  String? _buildChatSummaryText(SessionInfo session) {
    if (session.storeId.isEmpty) return null;
    if (_cartItemCount == 0) {
      if (_groupOrder != null) {
        return 'Group order active • ${_groupOrder!.participants.length} joined. No items yet.';
      }
      return 'No items yet. Pick a category to start.';
    }
    final parts = <String>[
      '$_cartItemCount item${_cartItemCount == 1 ? '' : 's'}',
      _formatPrice(_cartTotalCents),
      _isDeliverySelected ? 'Delivery' : 'Pickup',
    ];
    if (_groupOrder != null) {
      parts.add('Group order • ${_groupOrder!.participants.length} joined');
    }
    return 'Current order: ${parts.join(' • ')}';
  }

  String _buildContextSummaryText(SessionInfo session) {
    if (session.storeId.isEmpty) return 'Details';
    final parts = <String>[];
    if (_deliveryEnabled) {
      parts.add(_isDeliverySelected ? 'Delivery' : 'Pickup');
    }
    if (_activeCategory.isNotEmpty && _activeCategory.toLowerCase() != 'all') {
      parts.add(_activeCategory);
    }
    if (_selectedProduct != null) {
      parts.add(_selectedProduct!.name);
    }
    if (_groupOrder != null) {
      parts.add('Group order');
    }
    if (parts.isEmpty) return 'Details';
    return parts.join(' • ');
  }
}
