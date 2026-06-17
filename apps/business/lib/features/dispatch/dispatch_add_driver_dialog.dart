import 'package:flutter/material.dart';

class DispatchAddDriverResult {
  const DispatchAddDriverResult({
    required this.displayName,
    required this.phoneE164,
    required this.maxActiveStops,
  });

  final String displayName;
  final String phoneE164;
  final int maxActiveStops;
}

Future<DispatchAddDriverResult?> showDispatchAddDriverDialog(
  BuildContext context,
) async {
  final nameCtrl = TextEditingController();
  final phoneCtrl = TextEditingController();
  final stopsCtrl = TextEditingController(text: '3');
  try {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Add driver'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtrl,
                decoration: const InputDecoration(labelText: 'Display name'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: phoneCtrl,
                decoration: const InputDecoration(labelText: 'Phone (E.164)'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: stopsCtrl,
                decoration:
                    const InputDecoration(labelText: 'Max active stops'),
                keyboardType: TextInputType.number,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Create'),
            ),
          ],
        );
      },
    );
    if (ok != true) return null;
    return DispatchAddDriverResult(
      displayName: nameCtrl.text.trim(),
      phoneE164: phoneCtrl.text.trim(),
      maxActiveStops: int.tryParse(stopsCtrl.text.trim()) ?? 3,
    );
  } finally {
    nameCtrl.dispose();
    phoneCtrl.dispose();
    stopsCtrl.dispose();
  }
}
