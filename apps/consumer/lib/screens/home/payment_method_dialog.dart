import 'package:flutter/material.dart';

Future<String?> showPaymentMethodDialog(
  BuildContext context, {
  bool allowCash = true,
}) async {
  var selected = 'card';
  return showDialog<String>(
    context: context,
    builder: (dialogContext) {
      return StatefulBuilder(
        builder: (context, setStateDialog) {
          return AlertDialog(
            title: const Text('Payment method'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                RadioGroup<String>(
                  groupValue: selected,
                  onChanged: (value) {
                    setStateDialog(() => selected = value ?? 'card');
                  },
                  child: Column(
                    children: [
                      const RadioListTile<String>(
                        value: 'card',
                        title: Text('Card on file'),
                      ),
                      if (allowCash)
                        const RadioListTile<String>(
                          value: 'cash',
                          title: Text('Cash at pickup'),
                        ),
                    ],
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(null),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.of(dialogContext).pop(selected),
                child: const Text('Confirm'),
              ),
            ],
          );
        },
      );
    },
  );
}
