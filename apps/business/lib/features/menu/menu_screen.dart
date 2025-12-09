import 'package:flutter/material.dart';

import '../../widgets/business_drawer.dart';
import 'menu_editor.dart';

class MenuScreen extends StatelessWidget {
  const MenuScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      appBar: AppBar(title: Text('Menu Manager')),
      drawer: BusinessDrawer(),
      body: MenuEditorScreen(),
    );
  }
}
