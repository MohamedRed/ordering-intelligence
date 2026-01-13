import 'dart:ui';

import 'package:flutter/material.dart';

/// Light glassy backdrop with a warm neutral gradient and subtle overlay.
/// Wrap your app content with this to get the glossy background seen in the
/// reference design while keeping the scaffold itself transparent.
class GlassBackdrop extends StatelessWidget {
  /// Set [blurSigma] lower (e.g., 6–8) for low-end devices.
  const GlassBackdrop({
    super.key,
    required this.child,
    this.blurSigma = 12,
  });

  final Widget child;
  final double blurSigma;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // Base gradient background.
        Positioned.fill(
          child: DecoratedBox(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color(0xFFF2F0EC), // soft warm white
                  Color(0xFFE6E0D6), // light sand
                  Color(0xFFD9D0C5), // muted taupe
                ],
                stops: [0.05, 0.55, 1.0],
              ),
            ),
          ),
        ),
        // Glassy overlay for a slight sheen.
        Positioned.fill(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: blurSigma, sigmaY: blurSigma),
            child: Container(
              color: Colors.white.withOpacity(0.06),
            ),
          ),
        ),
        // Foreground content.
        Positioned.fill(child: child),
      ],
    );
  }
}
