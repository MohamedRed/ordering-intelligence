part of 'mini_app_screen.dart';

mixin MiniAppStateBuildMenuBrowse
    on
        State<MiniAppScreen>,
        MiniAppStateFields,
        MiniAppStateMenu,
        MiniAppStateStore,
        MiniAppStateCart,
        MiniAppStateCartSheet,
        MiniAppStateDelivery,
        MiniAppStateGroupOrdersView,
        MiniAppStateBuildMenuChat,
        MiniAppStateChatSelection,
        MiniAppStateChatParticipants {
  Widget _buildBrowseMenuLayout(
    SessionInfo session, {
    VoidCallback? onOpenMenu,
  }) {
    final modeToggle = MenuViewToggle(
      mode: _menuViewMode,
      onChanged: _setMenuViewMode,
    );
    final cartLabel = _cartItemCount == 0
        ? 'Cart is empty'
        : 'Cart • $_cartItemCount item(s) • ${_formatPrice(_cartTotalCents)}';
    final groupOrderPanel = buildGroupOrderPanel();
    final header = ChatHeaderCard(
      key: ValueKey('browse-${session.storeId}'),
      storeName: session.storeName,
      subtitle: _groupOrder != null
          ? 'Group order active • ${_groupOrder!.participants.length} joined'
          : '',
      cartLabel: cartLabel,
      onOpenCart: _cartItemCount == 0 ? null : _openCartSheet,
      onChangeStore: _changeStore,
      onOpenMenu: null,
      contextSection: ChatContextPanel(
        embedded: true,
        expanded: _contextExpanded,
        onToggleExpanded: () => _setContextExpanded(!_contextExpanded),
        summaryText: _buildContextSummaryText(session),
        deliveryEnabled: _deliveryEnabled,
        isDelivery: _isDeliverySelected,
        onFulfillmentChanged: _toggleDelivery,
        showToggle: false,
        expandedContent: const SizedBox.shrink(),
      ),
    );

    Widget body;
    if (_loadingMenu) {
      body = const Center(child: CircularProgressIndicator());
    } else if (_menuError != null) {
      body = CenteredMessage(
        title: 'Menu unavailable',
        description: _menuError!,
        actionLabel: 'Retry',
        onAction: () => _loadMenu(session.storeId),
      );
    } else if (_menu == null) {
      body = CenteredMessage(
        title: 'No menu available',
        description: 'Try another store.',
        actionLabel: 'Change store',
        onAction: _changeStore,
      );
    } else {
      final filtered = _filteredMenuItems(_menu!);
      body = Column(
        children: [
          MenuBrowseFilters(
            categories: _categories,
            activeCategory: _activeCategory,
            onCategorySelected: _selectBrowseCategory,
            participants: _groupOrder?.participants ?? const [],
            selectedParticipantId: _groupOrderSelectedParticipantId,
            onParticipantSelected: _handleBrowseParticipantSelected,
            deliveryEnabled: false,
            isDelivery: _isDeliverySelected,
            onFulfillmentChanged: (_) {},
          ),
          if (groupOrderPanel != null) ...[
            const SizedBox(height: 12),
            groupOrderPanel,
          ],
          const SizedBox(height: 12),
          Expanded(
            child: filtered.isEmpty
                ? CenteredMessage(
                    title: 'No items found',
                    description: 'Try another category.',
                  )
                : ListView.separated(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    itemCount: filtered.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 12),
                    itemBuilder: (context, index) {
                      final item = filtered[index];
                      return MenuItemCard(
                        item: item,
                        formatPrice: _formatPrice,
                        onAdd: () => _handleAdd(item),
                      );
                    },
                  ),
          ),
        ],
      );
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
          child: MenuModeBar(toggle: modeToggle, onOpenMenu: onOpenMenu),
        ),
        header,
        const SizedBox(height: 12),
        Expanded(child: body),
      ],
    );
  }

  List<MenuItem> _filteredMenuItems(MenuSnapshot menu) {
    final active = _activeCategory.trim();
    if (active.isEmpty || active.toLowerCase() == 'all') {
      return menu.items;
    }
    final normalized = active.toLowerCase();
    return menu.items
        .where((item) => item.category.toLowerCase() == normalized)
        .toList();
  }

  void _selectBrowseCategory(String category) {
    final normalized = _normalizeCategory(category) ?? category.trim();
    if (normalized.isEmpty) {
      return;
    }
    setState(() {
      _activeCategory = normalized;
      _selectedProduct = null;
    });
  }

  void _handleBrowseParticipantSelected(GroupOrderParticipant participant) {
    setState(
      () => _groupOrderSelectedParticipantId = participant.participantId,
    );
  }
}
