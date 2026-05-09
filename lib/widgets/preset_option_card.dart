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
    /// Wider list-style row (icon + text + pill). Use for full-width trailing cards.
    this.horizontal = false,
  });

  final CompressionPreset preset;
  final bool selected;
  final VoidCallback onTap;
  final bool horizontal;

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
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 11),
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
            clipBehavior: Clip.none,
            children: [
              if (selected)
                Positioned(
                  top: -2,
                  right: -2,
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
              Padding(
                padding: EdgeInsets.only(right: selected ? 4 : 0),
                child: horizontal ? _horizontalBody(context) : _verticalBody(context),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _iconBox() {
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: preset.iconBackground,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Center(
        child: preset.useFontAwesome
            ? FaIcon(preset.icon, size: 20, color: preset.badgeColor)
            : Icon(preset.icon, size: 22, color: preset.badgeColor),
      ),
    );
  }

  Widget _titleSubtitleColumn(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          preset.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w800,
                height: 1.15,
              ),
        ),
        const SizedBox(height: 4),
        SizedBox(
          height: 34,
          width: double.infinity,
          child: Align(
            alignment: Alignment.topLeft,
            child: Text(
              preset.subtitle,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppColors.textSecondary,
                    height: 1.2,
                    fontSize: 12,
                  ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _verticalBody(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        _iconBox(),
        const SizedBox(height: 8),
        _titleSubtitleColumn(context),
        const SizedBox(height: 8),
        _footerPill(context),
      ],
    );
  }

  Widget _horizontalBody(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        _iconBox(),
        const SizedBox(width: 10),
        Expanded(child: _titleSubtitleColumn(context)),
        const SizedBox(width: 8),
        _footerPill(context),
      ],
    );
  }

  Widget _footerPill(BuildContext context) {
    final style = Theme.of(context).textTheme.labelMedium?.copyWith(
          fontWeight: FontWeight.w800,
          fontSize: 12,
        );
    if (preset.isCustom) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: AppColors.tealAccent.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text('Configure', style: style?.copyWith(color: AppColors.tealAccent)),
      );
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: preset.badgeColor.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(preset.savingsLabel, style: style?.copyWith(color: preset.badgeColor)),
    );
  }
}
