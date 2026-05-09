import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import '../models/compression_preset.dart';
import '../theme/app_colors.dart';

final kCompressionPresets = <CompressionPreset>[
  CompressionPreset(
    id: 'custom',
    name: 'Custom',
    subtitle: 'Tap to configure',
    estimatedSavingsPercent: 0,
    iconBackground: const Color(0xFFD8F5F2),
    badgeColor: const Color(0xFF14B8A6),
    icon: Icons.settings_outlined,
    isCustom: true,
  ),
  CompressionPreset(
    id: 'instagram',
    name: 'Instagram Reels',
    subtitle: '1080p • 30fps • H.264',
    estimatedSavingsPercent: 40,
    iconBackground: const Color(0xFFFFE4EF),
    badgeColor: const Color(0xFFFF4D8D),
    icon: FontAwesomeIcons.instagram,
    useFontAwesome: true,
  ),
  CompressionPreset(
    id: 'whatsapp',
    name: 'WhatsApp',
    subtitle: '720p • Optimized for sharing',
    estimatedSavingsPercent: 65,
    iconBackground: const Color(0xFFDFF7E4),
    badgeColor: const Color(0xFF25D366),
    icon: FontAwesomeIcons.whatsapp,
    useFontAwesome: true,
  ),
  CompressionPreset(
    id: 'telegram',
    name: 'Telegram',
    subtitle: '720p • Fast upload speed',
    estimatedSavingsPercent: 55,
    iconBackground: const Color(0xFFDCEBFF),
    badgeColor: const Color(0xFF2AABEE),
    icon: FontAwesomeIcons.telegram,
    useFontAwesome: true,
  ),
  CompressionPreset(
    id: 'high_quality',
    name: 'High Quality',
    subtitle: '1080p • Best quality',
    estimatedSavingsPercent: 20,
    iconBackground: const Color(0xFFEDE7FF),
    badgeColor: AppColors.primary,
    icon: Icons.diamond_outlined,
  ),
  CompressionPreset(
    id: 'balanced',
    name: 'Balanced',
    subtitle: '720p • Great quality & size',
    estimatedSavingsPercent: 50,
    iconBackground: const Color(0xFFFFE8D6),
    badgeColor: const Color(0xFFF97316),
    icon: Icons.layers_outlined,
  ),
  CompressionPreset(
    id: 'max',
    name: 'Max Compress',
    subtitle: '480p • Smallest file size',
    estimatedSavingsPercent: 80,
    iconBackground: const Color(0xFFFFE4E4),
    badgeColor: const Color(0xFFEF4444),
    icon: Icons.file_download_outlined,
  ),
];
