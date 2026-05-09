import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:video_player/video_player.dart';

import '../theme/app_colors.dart';

class VideoInfoCard extends StatelessWidget {
  const VideoInfoCard({
    super.key,
    required this.controller,
    required this.file,
    required this.onChange,
  });

  final VideoPlayerController controller;
  final File file;
  final VoidCallback onChange;

  String _formatDuration(Duration d) {
    final total = d.inSeconds;
    final m = total ~/ 60;
    final s = total % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final size = controller.value.size;
    final res = '${size.width.toInt()}×${size.height.toInt()}';
    final duration = controller.value.duration;
    final bytes = file.lengthSync();
    final mb = (bytes / (1024 * 1024)).toStringAsFixed(1);
    final ext = p.extension(file.path).replaceFirst('.', '').toUpperCase();
    final name = p.basename(file.path);

    final sw = size.width;
    final sh = size.height;
    final bool isPortrait = sw > 0 && sh > 0 && sh > sw;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.videoCardTint,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final w = constraints.maxWidth;
                if (sw == 0 || sh == 0) {
                  return AspectRatio(
                    aspectRatio: 16 / 9,
                    child: _previewStack(controller, res, duration),
                  );
                }
                final videoAr = sw / sh;
                final fullHeight = w / videoAr;
                final h = isPortrait ? fullHeight * 0.5 : fullHeight;
                return SizedBox(
                  width: w,
                  height: h,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      ColoredBox(color: Colors.black.withValues(alpha: 0.2)),
                      FittedBox(
                        fit: BoxFit.contain,
                        child: SizedBox(
                          width: sw,
                          height: sh,
                          child: VideoPlayer(controller),
                        ),
                      ),
                      Center(
                        child: Container(
                          width: 56,
                          height: 56,
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.35),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 36),
                        ),
                      ),
                      Positioned(
                        top: 10,
                        left: 10,
                        child: _pill(res),
                      ),
                      Positioned(
                        right: 10,
                        bottom: 10,
                        child: _pill(_formatDuration(duration), icon: Icons.schedule_rounded),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 12),
          Text(
            name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _metaChip(context, Icons.sd_storage_outlined, '$mb MB'),
              const SizedBox(width: 8),
              _metaChip(context, Icons.movie_filter_outlined, ext.isEmpty ? 'VIDEO' : ext),
              const Spacer(),
              TextButton.icon(
                onPressed: onChange,
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.primary,
                  backgroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                icon: const Icon(Icons.swap_horiz_rounded, size: 18),
                label: const Text('Change', style: TextStyle(fontWeight: FontWeight.w700)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _previewStack(VideoPlayerController controller, String res, Duration duration) {
    return Stack(
      fit: StackFit.expand,
      children: [
        VideoPlayer(controller),
        Center(
          child: Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.35),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 36),
          ),
        ),
        Positioned(
          top: 10,
          left: 10,
          child: _pill(res),
        ),
        Positioned(
          right: 10,
          bottom: 10,
          child: _pill(_formatDuration(duration), icon: Icons.schedule_rounded),
        ),
      ],
    );
  }

  Widget _pill(String text, {IconData? icon}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: Colors.white),
            const SizedBox(width: 4),
          ],
          Text(
            text,
            style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }

  Widget _metaChip(BuildContext context, IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: AppColors.textSecondary),
          const SizedBox(width: 6),
          Text(
            label,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: Colors.black87,
                ),
          ),
        ],
      ),
    );
  }
}
