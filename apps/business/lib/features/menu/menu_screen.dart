import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../widgets/business_scaffold.dart';
import 'menu_editor.dart';

class MenuScreen extends StatelessWidget {
  const MenuScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BusinessScaffold(
      title: const Text('Menu Manager'),
      actions: const [
        Padding(
          padding: EdgeInsets.only(right: 12.0),
          child: ShadButton.outline(child: Text('Preview')),
        )
      ],
      body: const MenuEditorScreen(),
    );
  }
}
