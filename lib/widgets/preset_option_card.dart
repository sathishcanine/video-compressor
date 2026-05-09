import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import '../models/compression_preset.dart';
import '../theme/app_colors.dart';

class PresetOptionCard extends StatelessWidget {
  const PresetOptionCard({
    super.key,
    required this.preset,
    required this.selected,
    required this.onTap,
  });

  final CompressionPreset preset;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: selected ? const Color(0xFF2563EB) : Colors.black.withValues(alpha: 0.06),
              width: selected ? 2 : 1,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Stack(
            children: [
              if (selected)
                Positioned(
                  top: 0,
                  right: 0,
                  child: Container(
                    width: 22,
                    height: 22,
                    decoration: const BoxDecoration(
                      color: Color(0xFFEF4444),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.check_rounded, color: Colors.white, size: 14),
                  ),
                ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: preset.iconBackground,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Center(
                      child: preset.useFontAwesome
                          ? FaIcon(preset.icon, size: 22, color: preset.badgeColor)
                          : Icon(preset.icon, size: 24, color: preset.badgeColor),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    preset.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    preset.subtitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppColors.textSecondary,
                          height: 1.25,
                        ),
                  ),
                  const Spacer(),
                  if (preset.isCustom)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: AppColors.tealAccent.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          'Configure',
                          style: Theme.of(context).textTheme.labelLarge?.copyWith(
                                color: AppColors.tealAccent,
                                fontWeight: FontWeight.w800,
                              ),
                        ),
                      ),
                    )
                  else
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: preset.badgeColor.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        preset.savingsLabel,
                        style: Theme.of(context).textTheme.labelLarge?.copyWith(
                              color: preset.badgeColor,
                              fontWeight: FontWeight.w800,
                            ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
