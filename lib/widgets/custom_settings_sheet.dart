import 'package:flutter/material.dart';

import '../models/custom_settings.dart';
import '../theme/app_colors.dart';

Future<CustomCompressionSettings?> showCustomSettingsSheet(
  BuildContext context, {
  required CustomCompressionSettings initial,
}) {
  return showModalBottomSheet<CustomCompressionSettings>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) {
      return CustomSettingsSheet(initial: initial);
    },
  );
}

class CustomSettingsSheet extends StatefulWidget {
  const CustomSettingsSheet({super.key, required this.initial});

  final CustomCompressionSettings initial;

  @override
  State<CustomSettingsSheet> createState() => _CustomSettingsSheetState();
}

class _CustomSettingsSheetState extends State<CustomSettingsSheet> {
  late CustomCompressionSettings _s;

  @override
  void initState() {
    super.initState();
    _s = widget.initial.copyWith();
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.paddingOf(context).bottom;
    final reduction = _s.estimatedReductionPercent();
    final bitrate = _s.estimatedBitrateMbps();
    final spec = '${_s.resolutionLabel} ${_s.fpsLabel}';

    return DraggableScrollableSheet(
      initialChildSize: 0.92,
      minChildSize: 0.55,
      maxChildSize: 0.95,
      builder: (context, scrollController) {
        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
          ),
          child: ListView(
            controller: scrollController,
            padding: EdgeInsets.fromLTRB(20, 12, 20, 20 + bottom),
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: Colors.black12,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
              Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: const Color(0xFFBAE6FD),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.settings_rounded, color: Colors.white, size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Custom Settings',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.summaryBorder, width: 1.4),
                  color: const Color(0xFFF0FDFA),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: _summaryCol(
                        context,
                        title: '~$reduction% Size Reduction',
                        titleColor: AppColors.success,
                      ),
                    ),
                    Container(width: 1, height: 36, color: Colors.black12),
                    Expanded(
                      child: _summaryCol(
                        context,
                        title: '$bitrate Target Bitrate',
                        titleColor: const Color(0xFF2563EB),
                      ),
                    ),
                    Container(width: 1, height: 36, color: Colors.black12),
                    Expanded(
                      child: _summaryCol(
                        context,
                        title: spec,
                        titleColor: Colors.black,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 22),
              _sectionLabel(context, Icons.open_in_full_rounded, 'Resolution'),
              const SizedBox(height: 10),
              _segmented(
                options: const ['480p', '720p', '1080p'],
                selectedIndex: _s.resolution.index,
                onChanged: (i) => setState(() => _s.resolution = VideoResolutionPreset.values[i]),
              ),
              const SizedBox(height: 6),
              Text(
                _s.resolutionCaption(),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.textSecondary),
              ),
              const SizedBox(height: 22),
              Row(
                children: [
                  Text(
                    'Quality',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
                  ),
                  const Spacer(),
                  Text(
                    '${_s.qualityPercent.round()}%',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: AppColors.primary,
                        ),
                  ),
                ],
              ),
              SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  activeTrackColor: AppColors.primary,
                  inactiveTrackColor: AppColors.primary.withValues(alpha: 0.15),
                  thumbColor: AppColors.primary,
                  overlayColor: AppColors.primary.withValues(alpha: 0.12),
                ),
                child: Slider(
                  value: _s.qualityPercent,
                  min: 10,
                  max: 100,
                  divisions: 90,
                  onChanged: (v) => setState(() => _s.qualityPercent = v),
                ),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('10%', style: Theme.of(context).textTheme.labelSmall),
                  Text('100%', style: Theme.of(context).textTheme.labelSmall),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                _s.qualityCaption(),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.textSecondary),
              ),
              const SizedBox(height: 22),
              _sectionLabel(context, Icons.movie_filter_outlined, 'Frame Rate'),
              const SizedBox(height: 10),
              _segmented(
                options: const ['24fps', '30fps', '60fps'],
                selectedIndex: _s.fps.index,
                onChanged: (i) => setState(() => _s.fps = VideoFpsPreset.values[i]),
              ),
              const SizedBox(height: 6),
              Text(
                _s.fpsCaption(),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.textSecondary),
              ),
              const SizedBox(height: 22),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.tealAccent,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                  onPressed: () => Navigator.pop(context, _s.copyWith()),
                  icon: const Icon(Icons.check_circle_outline_rounded, color: Colors.white),
                  label: const Text(
                    'APPLY SETTINGS',
                    style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: 0.2),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _sectionLabel(BuildContext context, IconData icon, String text) {
    return Row(
      children: [
        Icon(icon, size: 18, color: AppColors.textSecondary),
        const SizedBox(width: 8),
        Text(
          text,
          style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
        ),
      ],
    );
  }

  Widget _summaryCol(BuildContext context, {required String title, required Color titleColor}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Text(
        title,
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
              fontWeight: FontWeight.w800,
              color: titleColor,
              height: 1.2,
            ),
      ),
    );
  }

  Widget _segmented({
    required List<String> options,
    required int selectedIndex,
    required ValueChanged<int> onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          for (var i = 0; i < options.length; i++)
            Expanded(
              child: GestureDetector(
                onTap: () => onChanged(i),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                    color: i == selectedIndex ? AppColors.tealAccent : Colors.transparent,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    options[i],
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      color: i == selectedIndex ? Colors.white : Colors.black87,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
