import 'package:consumer_core/consumer_core.dart';
import 'package:flutter/material.dart';

class GasOrderStorePicker extends StatefulWidget {
  const GasOrderStorePicker({
    super.key,
    required this.api,
    required this.session,
    required this.onStoreSelected,
  });

  final ChannelGatewayApi api;
  final SessionInfo session;
  final ValueChanged<StoreChoice> onStoreSelected;

  @override
  State<GasOrderStorePicker> createState() => _GasOrderStorePickerState();
}

class _GasOrderStorePickerState extends State<GasOrderStorePicker> {
  final TextEditingController _searchController = TextEditingController();
  bool _searching = false;
  String? _error;
  List<StoreChoice> _results = const [];

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final query = _searchController.text.trim();
    if (query.isEmpty) return;
    setState(() {
      _searching = true;
      _error = null;
    });
    try {
      final results = await widget.api.searchStores(query);
      final gasOnly = results
          .where((store) => store.businessType.trim().toLowerCase() == 'gas_station')
          .toList();
      if (!mounted) return;
      setState(() {
        _results = gasOnly;
      });
    } catch (err) {
      if (!mounted) return;
      setState(() => _error = err.toString());
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  Future<void> _selectStore(StoreChoice store) async {
    setState(() {
      _searching = true;
      _error = null;
    });
    try {
      await widget.api.selectStore(
        sessionId: widget.session.sessionId,
        storeId: store.storeId,
      );
      if (!mounted) return;
      widget.onStoreSelected(store);
    } catch (err) {
      if (!mounted) return;
      setState(() => _error = err.toString());
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text(
          'Find a gas station',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _searchController,
          textInputAction: TextInputAction.search,
          onSubmitted: (_) => _search(),
          decoration: InputDecoration(
            labelText: 'Search stores',
            suffixIcon: IconButton(
              icon: const Icon(Icons.search),
              onPressed: _searching ? null : _search,
            ),
          ),
        ),
        const SizedBox(height: 12),
        if (_searching) const LinearProgressIndicator(),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(
              _error!,
              style: const TextStyle(color: Colors.redAccent),
            ),
          ),
        if (!_searching && _results.isEmpty)
          const Padding(
            padding: EdgeInsets.only(top: 20),
            child: Text('No gas stations yet. Try another search.'),
          ),
        const SizedBox(height: 16),
        ..._results.map(
          (store) => Card(
            child: ListTile(
              leading: const Icon(Icons.local_gas_station),
              title: Text(store.name.isEmpty ? store.storeId : store.name),
              subtitle: Text(store.storeId),
              trailing: const Icon(Icons.chevron_right),
              onTap: _searching ? null : () => _selectStore(store),
            ),
          ),
        ),
      ],
    );
  }
}
