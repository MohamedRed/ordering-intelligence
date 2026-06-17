import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/menu.dart';
import '../../providers/menu_providers.dart';
import '../../widgets/shad_snackbar.dart';
import 'menu_editor_list.dart';

class MenuEditorScreen extends ConsumerStatefulWidget {
  const MenuEditorScreen({super.key});

  @override
  ConsumerState<MenuEditorScreen> createState() => _MenuEditorScreenState();
}

class _MenuEditorScreenState extends ConsumerState<MenuEditorScreen> {
  late Future<MenuRecordModel> _future;
  late MenuApi _api;

  @override
  void initState() {
    super.initState();
    _api = MenuApi();
    _future = _api.fetchMenu();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<MenuRecordModel>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(child: Text('Error: ${snapshot.error}'));
        }
        final menu = snapshot.data ?? MenuRecordModel.empty();
        return MenuEditorList(
          menu: menu,
          onSave: (newMenu) async {
            await _api.saveMenu(newMenu);
            if (!context.mounted) return;
            showShadSnack(
              context,
              title: 'Menu saved',
              type: ShadSnackType.success,
            );
            setState(() {
              _future = Future.value(newMenu);
            });
          },
        );
      },
    );
  }
}
