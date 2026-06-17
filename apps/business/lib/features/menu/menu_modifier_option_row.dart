import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../models/menu.dart';
import 'menu_editor_factories.dart';

class MenuModifierOptionRow extends StatelessWidget {
  const MenuModifierOptionRow({
    super.key,
    required this.option,
    required this.onChanged,
    required this.onRemoved,
  });

  final MenuModifierOptionModel option;
  final ValueChanged<MenuModifierOptionModel> onChanged;
  final VoidCallback onRemoved;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth < 520) {
            return _NarrowOptionLayout(
              option: option,
              onChanged: onChanged,
              onRemoved: onRemoved,
            );
          }
          return _WideOptionLayout(
            option: option,
            onChanged: onChanged,
            onRemoved: onRemoved,
          );
        },
      ),
    );
  }
}

class _WideOptionLayout extends StatelessWidget {
  const _WideOptionLayout({
    required this.option,
    required this.onChanged,
    required this.onRemoved,
  });

  final MenuModifierOptionModel option;
  final ValueChanged<MenuModifierOptionModel> onChanged;
  final VoidCallback onRemoved;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: _NameField(option: option, onChanged: onChanged)),
        const SizedBox(width: 8),
        SizedBox(
          width: 140,
          child: _PriceField(option: option, onChanged: onChanged),
        ),
        IconButton(
          onPressed: onRemoved,
          icon: const Icon(Icons.delete_outline),
        ),
      ],
    );
  }
}

class _NarrowOptionLayout extends StatelessWidget {
  const _NarrowOptionLayout({
    required this.option,
    required this.onChanged,
    required this.onRemoved,
  });

  final MenuModifierOptionModel option;
  final ValueChanged<MenuModifierOptionModel> onChanged;
  final VoidCallback onRemoved;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _NameField(option: option, onChanged: onChanged),
        const SizedBox(height: 8),
        SizedBox(
          width: 140,
          child: _PriceField(option: option, onChanged: onChanged),
        ),
        Align(
          alignment: Alignment.centerRight,
          child: IconButton(
            onPressed: onRemoved,
            icon: const Icon(Icons.delete_outline),
          ),
        ),
      ],
    );
  }
}

class _NameField extends StatelessWidget {
  const _NameField({required this.option, required this.onChanged});

  final MenuModifierOptionModel option;
  final ValueChanged<MenuModifierOptionModel> onChanged;

  @override
  Widget build(BuildContext context) {
    return ShadInputFormField(
      initialValue: option.name,
      label: const Text('Name'),
      onChanged: (value) => onChanged(
        MenuModifierOptionModel(
          id: option.id,
          name: value,
          priceCents: option.priceCents,
        ),
      ),
    );
  }
}

class _PriceField extends StatelessWidget {
  const _PriceField({required this.option, required this.onChanged});

  final MenuModifierOptionModel option;
  final ValueChanged<MenuModifierOptionModel> onChanged;

  @override
  Widget build(BuildContext context) {
    return ShadInputFormField(
      initialValue: option.priceCents.toString(),
      label: const Text('Price (cents)'),
      keyboardType: TextInputType.number,
      onChanged: (value) => onChanged(
        MenuModifierOptionModel(
          id: option.id,
          name: option.name,
          priceCents: parseMenuEditorInt(value),
        ),
      ),
    );
  }
}
