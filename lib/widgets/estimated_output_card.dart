import 'package:flutter/material.dart';

import '../models/compression_preset.dart';
import '../models/custom_settings.dart';
import '../services/compression_encode_params.dart';
import '../services/output_size_estimate.dart';
import '../theme/app_colors.dart';

/// Shows a rough encoded file size for the chosen preset (preset selection screen).
class EstimatedOutputCard extends StatelessWidget {
  const EstimatedOutputCard({
    super.key,
    required this.preset,
    required this.custom,
    required this.duration,
    required this.sourceWidth,
    required this.sourceHeight,
    required this.sourceFileBytes,
  });

  final CompressionPreset? preset;
  final CustomCompressionSettings custom;
  final Duration duration;
  final int sourceWidth;
  final int sourceHeight;
  final int sourceFileBytes;

  static String _mb(int bytes) => (bytes / (1024 * 1024)).toStringAsFixed(1);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final text = theme.textTheme;

    if (preset == null) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.background,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.black.withValues(alpha: 0.06)),
        ),
        child: Row(
          children: [
            Icon(Icons.calculate_outlined, size: 22, color: AppColors.textSecondary.withValues(alpha: 0.7)),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Select a preset to see an estimated output size.',
                style: text.bodySmall?.copyWith(
                  color: AppColors.textSecondary,
                  fontWeight: FontWeight.w600,
                  height: 1.3,
                ),
              ),
            ),
          ],
        ),
      );
    }

    final p = preset!;
    final params = compressionParamsFor(p, custom);
    final estBytes = estimateCompressedVideoBytes(
      params: params,
      duration: duration,
      sourceWidth: sourceWidth,
      sourceHeight: sourceHeight,
      sourceFileBytes: sourceFileBytes,
    );

    final presetLine = p.isCustom
        ? 'Custom • ${custom.resolutionLabel} • ${custom.fpsLabel} • ${custom.qualityPercent.round()}% quality'
        : p.name;

    if (estBytes == null) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.background,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.black.withValues(alpha: 0.06)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _header(context),
            const SizedBox(height: 6),
            Text(
              presetLine,
              style: text.bodySmall?.copyWith(color: AppColors.textSecondary, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Text(
              'Duration isn’t available yet — open this video again or pick another file to estimate size.',
              style: text.bodySmall?.copyWith(color: AppColors.textSecondary, height: 1.35),
            ),
          ],
        ),
      );
    }

    final origMb = sourceFileBytes / (1024 * 1024);
    final estMb = estBytes / (1024 * 1024);
    final saveBytes = sourceFileBytes - estBytes;
    final savePct = sourceFileBytes > 0 ? ((saveBytes / sourceFileBytes) * 100).round().clamp(-999, 99) : 0;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.videoCardTint,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _header(context),
          const SizedBox(height: 6),
          Text(
            presetLine,
            style: text.bodySmall?.copyWith(color: AppColors.textSecondary, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _sizeColumn(
                  context,
                  label: 'Current file',
                  valueMb: origMb,
                  valueStyle: text.titleSmall?.copyWith(fontWeight: FontWeight.w900),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(bottom: 18),
                child: Icon(Icons.arrow_forward_rounded, color: AppColors.primary.withValues(alpha: 0.65), size: 22),
              ),
              Expanded(
                child: _sizeColumn(
                  context,
                  label: 'Est. output',
                  valueMb: estMb,
                  valueStyle: text.titleSmall?.copyWith(
                    fontWeight: FontWeight.w900,
                    color: AppColors.primary,
                  ),
                ),
              ),
            ],
          ),
          if (saveBytes > 0) ...[
            const SizedBox(height: 4),
            Text(
              'About ${_mb(saveBytes)} MB smaller (~$savePct% less)',
              style: text.labelLarge?.copyWith(
                color: AppColors.success,
                fontWeight: FontWeight.w800,
              ),
            ),
          ] else if (saveBytes < 0) ...[
            const SizedBox(height: 4),
            Text(
              'May be similar size or larger than the original (depends on your source).',
              style: text.labelMedium?.copyWith(
                color: AppColors.textSecondary,
                fontWeight: FontWeight.w600,
                height: 1.35,
              ),
            ),
          ],
          const SizedBox(height: 10),
          Text(
            'Estimate only — real size depends on motion and detail in your video.',
            style: text.labelSmall?.copyWith(
              color: AppColors.textSecondary.withValues(alpha: 0.85),
              height: 1.3,
            ),
          ),
        ],
      ),
    );
  }

  Widget _header(BuildContext context) {
    return Row(
      children: [
        Icon(Icons.calculate_outlined, size: 22, color: AppColors.primary),
        const SizedBox(width: 8),
        Text(
          'Estimated output size',
          style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w900),
        ),
      ],
    );
  }

  Widget _sizeColumn(
    BuildContext context, {
    required String label,
    required double valueMb,
    required TextStyle? valueStyle,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: Theme.of(context).textTheme.labelMedium?.copyWith(color: AppColors.textSecondary),
        ),
        const SizedBox(height: 2),
        Text('${valueMb.toStringAsFixed(1)} MB', style: valueStyle),
      ],
    );
  }
}
