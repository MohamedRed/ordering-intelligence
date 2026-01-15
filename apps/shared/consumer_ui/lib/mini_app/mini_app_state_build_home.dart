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
      onOpenMenu: null,
    );
    final recentStores = _recentStoreChoices();
    final singleOrders = _singleRecentOrders();
    final groupOrders = _groupRecentOrders();
    const tileSize = 140.0;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
          child: MenuModeBar(toggle: null, onOpenMenu: onOpenMenu),
        ),
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
                actionsOnlyTap: true,
              ),
              if (recentStores.isNotEmpty) ...[
                const SizedBox(height: 12),
                _SectionTitle(title: 'Recent stores'),
                const SizedBox(height: 8),
                SizedBox(
                  height: tileSize,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: recentStores.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 10),
                    itemBuilder: (context, index) {
                      final store = recentStores[index];
                      return _RecentStoreTile(
                        store: store,
                        size: tileSize,
                        onStartSingle: () => _startSingleOrderForStore(store),
                        onStartGroup: () => _startGroupOrderForStore(store),
                      );
                    },
                  ),
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
                SizedBox(
                  height: tileSize,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: singleOrders.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 10),
                    itemBuilder: (context, index) {
                      final order = singleOrders[index];
                      return _RecentOrderTile(
                        order: order,
                        size: tileSize,
                        onStartSingle: () => _startSingleOrderForOrder(order),
                        onStartGroup: () => _startGroupOrderForOrder(order),
                      );
                    },
                  ),
                ),
              ],
              if (groupOrders.isNotEmpty) ...[
                const SizedBox(height: 8),
                _SectionTitle(title: 'Recent group orders'),
                const SizedBox(height: 8),
                SizedBox(
                  height: tileSize,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: groupOrders.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 10),
                    itemBuilder: (context, index) {
                      final order = groupOrders[index];
                      return _RecentOrderTile(
                        order: order,
                        size: tileSize,
                        onStartSingle: () => _startSingleOrderForOrder(order),
                        onStartGroup: () => _startGroupOrderForOrder(order),
                      );
                    },
                  ),
                ),
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

class _RecentStoreTile extends StatelessWidget {
  const _RecentStoreTile({
    required this.store,
    required this.size,
    required this.onStartSingle,
    required this.onStartGroup,
  });

  final StoreChoice store;
  final double size;
  final VoidCallback onStartSingle;
  final VoidCallback onStartGroup;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final name = store.name.isEmpty ? store.storeId : store.name;
    return Container(
      width: size,
      height: size,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.muted,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.colorScheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          StoreLogo(name: name, logoUrl: store.logoUrl, size: 34),
          const SizedBox(height: 8),
          Text(
            name,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.small,
          ),
          const Spacer(),
          Row(
            children: [
              ActionIconButton(
                icon: Icons.person_outline,
                onPressed: onStartSingle,
                size: 30,
              ),
              const SizedBox(width: 6),
              ActionIconButton(
                icon: Icons.group_outlined,
                onPressed: onStartGroup,
                size: 30,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _RecentOrderTile extends StatelessWidget {
  const _RecentOrderTile({
    required this.order,
    required this.size,
    required this.onStartSingle,
    required this.onStartGroup,
  });

  final RecommendedOrder order;
  final double size;
  final VoidCallback onStartSingle;
  final VoidCallback onStartGroup;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final title = order.storeName;
    final subtitle = order.isGroupOrder
        ? 'Group order'
        : order.itemCount > 0
        ? '${order.itemCount} items'
        : 'Recent order';
    return Container(
      width: size,
      height: size,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.muted,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.colorScheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          StoreLogo(name: title, logoUrl: order.logoUrl, size: 34),
          const SizedBox(height: 8),
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.small,
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.muted,
          ),
          const Spacer(),
          Row(
            children: [
              ActionIconButton(
                icon: Icons.person_outline,
                onPressed: onStartSingle,
                size: 30,
              ),
              const SizedBox(width: 6),
              ActionIconButton(
                icon: Icons.group_outlined,
                onPressed: onStartGroup,
                size: 30,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
