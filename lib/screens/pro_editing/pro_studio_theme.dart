import 'package:flutter/material.dart';

/// InShot-inspired palette for Pro Studio screens.
abstract final class ProStudioTheme {
  static const Color pinkTop = Color(0xFFFF6B9D);
  static const Color pinkMid = Color(0xFFFF8FA3);
  static const Color orangeBottom = Color(0xFFFFD59A);
  static const Color yellowGlow = Color(0xFFFFF0C4);
  static const Color brandText = Color(0xFFC2185B);
  static const Color createLabel = Color(0xFFB0005C);
  static const Color buttonPink = Color(0xFFFF5C8D);
  static const Color buttonOrange = Color(0xFFFF9E6D);

  static LinearGradient get backgroundGradient => const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [pinkTop, pinkMid, orangeBottom],
        stops: [0.0, 0.45, 1.0],
      );

  static RadialGradient get circleButtonGradient => const RadialGradient(
        colors: [buttonPink, buttonOrange],
        center: Alignment(-0.35, -0.35),
        radius: 1.1,
      );
}
