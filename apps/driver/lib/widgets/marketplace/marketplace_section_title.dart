import 'package:flutter/material.dart';

class MarketplaceSectionTitle extends StatelessWidget {
  const MarketplaceSectionTitle(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(text, style: Theme.of(context).textTheme.titleMedium),
    );
  }
}
