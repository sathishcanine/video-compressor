import 'package:flutter/material.dart';

class CompressionPreset {
  const CompressionPreset({
    required this.id,
    required this.name,
    required this.subtitle,
    required this.estimatedSavingsPercent,
    required this.iconBackground,
    required this.badgeColor,
    required this.icon,
    this.useFontAwesome = false,
    this.isCustom = false,
  });

  final String id;
  final String name;
  final String subtitle;
  final int estimatedSavingsPercent;
  final Color iconBackground;
  final Color badgeColor;
  final IconData icon;
  final bool useFontAwesome;
  final bool isCustom;

  String get savingsLabel => isCustom ? 'Configure' : '-$estimatedSavingsPercent%';
}
