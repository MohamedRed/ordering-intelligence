part of 'mini_app_screen.dart';

mixin MiniAppStateBuildHome
    on
        State<MiniAppScreen>,
        MiniAppStateFields,
        MiniAppStateSearch,
        MiniAppStateStore,
        MiniAppStateHomeChat,
        MiniAppStateStoreSearchChat {
  Widget _buildHomeLayout(SessionInfo session, {VoidCallback? onOpenMenu}) {
    final header = ChatHeaderCard(
      storeName: 'Find a store',
      subtitle: '',
      cartLabel: null,
      onOpenMenu: onOpenMenu,
    );
    final recentStores = _recentStoreChoices();
    final singleOrders = _singleRecentOrders();
    final groupOrders = _groupRecentOrders();
    return Column(
      children: [
        header,
        const SizedBox(height: 12),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            children: [
              _SectionTitle(title: 'Search'),
              const SizedBox(height: 8),
              ShadInput(
                controller: _searchController,
                placeholder: const Text('Search stores by name'),
                onChanged: (_) => _onSearchChanged(),
                onSubmitted: (_) => _performSearch(),
              ),
              StoreSearchFooter(
                controller: _searchController,
                searching: _searching,
                searchResults: _searchResults,
                searchError: _searchError,
                onSelectSuggestion: _selectStoreFromSearchSuggestion,
                onStartSingle: _startSingleOrderForStore,
                onStartGroup: _startGroupOrderForStore,
              ),
              if (recentStores.isNotEmpty) ...[
                const SizedBox(height: 12),
                StoreInlineSuggestions(
                  results: recentStores,
                  onSelect: _selectHomeStore,
                  title: 'Recent stores',
                  maxItems: 6,
                  axis: Axis.vertical,
                  onStartSingle: _startSingleOrderForStore,
                  onStartGroup: _startGroupOrderForStore,
                ),
              ],
              if (!_recommendedOrdersLoaded)
                const Padding(
                  padding: EdgeInsets.only(top: 16),
                  child: LinearProgressIndicator(minHeight: 2),
                ),
              if (singleOrders.isNotEmpty) ...[
                const SizedBox(height: 16),
                _SectionTitle(title: 'Recent single orders'),
                const SizedBox(height: 8),
                for (final order in singleOrders) ...[
                  _OrderRow(
                    order: order,
                    onTap: () => _selectRecommendedOrder(order),
                    onStartSingle: () => _startSingleOrderForOrder(order),
                    onStartGroup: () => _startGroupOrderForOrder(order),
                  ),
                  const SizedBox(height: 10),
                ],
              ],
              if (groupOrders.isNotEmpty) ...[
                const SizedBox(height: 8),
                _SectionTitle(title: 'Recent group orders'),
                const SizedBox(height: 8),
                for (final order in groupOrders) ...[
                  _OrderRow(
                    order: order,
                    onTap: () => _selectRecommendedOrder(order),
                    onStartSingle: () => _startSingleOrderForOrder(order),
                    onStartGroup: () => _startGroupOrderForOrder(order),
                  ),
                  const SizedBox(height: 10),
                ],
              ],
              if (_recommendedOrdersLoaded &&
                  singleOrders.isEmpty &&
                  groupOrders.isEmpty) ...[
                const SizedBox(height: 16),
                CenteredMessage(
                  title: 'No recent orders yet',
                  description: 'Search for a store to start ordering.',
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  List<StoreChoice> _recentStoreChoices() {
    final seen = <String>{};
    final stores = <StoreChoice>[];
    for (final order in _recommendedOrders) {
      final id = order.storeId.trim();
      if (id.isEmpty || seen.contains(id)) continue;
      seen.add(id);
      stores.add(
        StoreChoice(
          name: order.storeName,
          storeId: order.storeId,
          tenantId: order.tenantId,
          businessType: order.businessType,
          logoUrl: order.logoUrl,
        ),
      );
    }
    return stores;
  }

  void _selectHomeStore(StoreChoice store) {
    _setPendingMenuViewMode(MenuViewMode.browse);
    _selectStore(store);
  }

  void _startSingleOrderForStore(StoreChoice store) {
    _pendingStartGroupOrder = false;
    _setPendingMenuViewMode(MenuViewMode.browse);
    _selectStore(store);
  }

  void _startGroupOrderForStore(StoreChoice store) {
    _pendingStartGroupOrder = true;
    _setPendingMenuViewMode(MenuViewMode.browse);
    _selectStore(store);
  }

  StoreChoice _storeChoiceFromOrder(RecommendedOrder order) {
    return StoreChoice(
      name: order.storeName,
      storeId: order.storeId,
      tenantId: order.tenantId,
      businessType: order.businessType,
      logoUrl: order.logoUrl,
    );
  }

  void _startSingleOrderForOrder(RecommendedOrder order) {
    _startSingleOrderForStore(_storeChoiceFromOrder(order));
  }

  void _startGroupOrderForOrder(RecommendedOrder order) {
    _startGroupOrderForStore(_storeChoiceFromOrder(order));
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Text(title, style: ShadTheme.of(context).textTheme.muted);
  }
}

class _OrderRow extends StatelessWidget {
  const _OrderRow({
    required this.order,
    required this.onTap,
    required this.onStartSingle,
    required this.onStartGroup,
  });

  final RecommendedOrder order;
  final VoidCallback onTap;
  final VoidCallback onStartSingle;
  final VoidCallback onStartGroup;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: RecommendedOrderCard(order: order, onTap: onTap),
        ),
        const SizedBox(width: 8),
        Column(
          children: [
            ShadButton.outline(
              size: ShadButtonSize.sm,
              onPressed: onStartSingle,
              child: const Icon(Icons.person_outline, size: 16),
            ),
            const SizedBox(height: 6),
            ShadButton.outline(
              size: ShadButtonSize.sm,
              onPressed: onStartGroup,
              child: const Icon(Icons.group_outlined, size: 16),
            ),
          ],
        ),
      ],
    );
  }
}
