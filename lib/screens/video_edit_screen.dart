import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:video_player/video_player.dart';

import '../theme/app_colors.dart';
import '../widgets/brand_header.dart';
import '../widgets/pick_video_panel.dart';
import '../widgets/video_info_card.dart';

class _EditTool {
  const _EditTool({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.tint,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Color tint;
}

/// Video editing hub — pick a clip and access trim, speed, filters, and more (tools roll out over time).
class VideoEditScreen extends StatefulWidget {
  const VideoEditScreen({super.key});

  @override
  State<VideoEditScreen> createState() => _VideoEditScreenState();
}

class _VideoEditScreenState extends State<VideoEditScreen> {
  static const List<_EditTool> _tools = [
    _EditTool(
      icon: Icons.content_cut_rounded,
      title: 'Trim & cut',
      subtitle: 'Drop intros, outros, or mistakes',
      tint: Color(0xFFE8E5FF),
    ),
    _EditTool(
      icon: Icons.speed_rounded,
      title: 'Speed',
      subtitle: 'Slow-mo, timelapse, and pacing',
      tint: Color(0xFFFFE8D6),
    ),
    _EditTool(
      icon: Icons.auto_fix_high_rounded,
      title: 'Filters & color',
      subtitle: 'Looks, exposure, and vibe',
      tint: Color(0xFFDFF7E4),
    ),
    _EditTool(
      icon: Icons.graphic_eq_rounded,
      title: 'Audio',
      subtitle: 'Levels, mute, and replacement track',
      tint: Color(0xFFDCEBFF),
    ),
    _EditTool(
      icon: Icons.crop_rotate_rounded,
      title: 'Crop & rotate',
      subtitle: 'Framing for Reels, Shorts, and more',
      tint: Color(0xFFFFE4EF),
    ),
    _EditTool(
      icon: Icons.text_fields_rounded,
      title: 'Text & overlays',
      subtitle: 'Titles, captions, and stickers',
      tint: Color(0xFFF4F4F6),
    ),
  ];

  final ImagePicker _picker = ImagePicker();
  File? _file;
  VideoPlayerController? _controller;

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _pickVideo() async {
    final x = await _picker.pickVideo(source: ImageSource.gallery);
    if (x == null) return;
    final file = File(x.path);
    await _swapController(file);
    if (!mounted) return;
    setState(() => _file = file);
  }

  Future<void> _swapController(File file) async {
    final old = _controller;
    final next = VideoPlayerController.file(file);
    await next.initialize();
    await next.setVolume(0);
    await next.pause();
    old?.dispose();
    _controller = next;
  }

  void _comingSoon(String label) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$label — launching in a future update.'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = _controller;
    final hasVideo = _file != null && c != null && c.value.isInitialized;

    return Scaffold(
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
              sliver: SliverToBoxAdapter(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const BrandHeader(),
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                            color: AppColors.tealAccent.withValues(alpha: 0.14),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            'NEW',
                            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                  color: AppColors.tealAccent,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 0.6,
                                ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Video editing',
                            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                  fontWeight: FontWeight.w900,
                                ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Trim, tune, and stylize clips before you compress or share.',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: AppColors.textSecondary,
                            height: 1.35,
                          ),
                    ),
                    const SizedBox(height: 22),
                    if (_file == null)
                      PickVideoPanel(
                        onPick: _pickVideo,
                        title: 'Choose a clip to edit',
                        subtitle: 'Same formats as Compress — gallery only for now',
                      )
                    else if (hasVideo)
                      VideoInfoCard(
                        controller: c,
                        file: _file!,
                        onChange: _pickVideo,
                      )
                    else
                      const Padding(
                        padding: EdgeInsets.all(32),
                        child: Center(child: CircularProgressIndicator()),
                      ),
                    if (hasVideo) ...[
                      const SizedBox(height: 24),
                      Text(
                        'Tools',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w900,
                            ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Tap a tool to open it when available.',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: AppColors.textSecondary,
                            ),
                      ),
                      const SizedBox(height: 12),
                    ],
                  ],
                ),
              ),
            ),
            if (hasVideo)
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
                sliver: SliverToBoxAdapter(
                  child: Column(
                    children: [
                      for (var i = 0; i < _tools.length; i++) ...[
                        if (i > 0) const SizedBox(height: 10),
                        _EditToolTile(
                          tool: _tools[i],
                          onTap: () => _comingSoon(_tools[i].title),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _EditToolTile extends StatelessWidget {
  const _EditToolTile({required this.tool, required this.onTap});

  final _EditTool tool;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.black.withValues(alpha: 0.06)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.03),
                blurRadius: 8,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: tool.tint,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(tool.icon, color: AppColors.primary, size: 24),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      tool.title,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      tool.subtitle,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: AppColors.textSecondary,
                            height: 1.25,
                          ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: AppColors.textSecondary.withValues(alpha: 0.45)),
            ],
          ),
        ),
      ),
    );
  }
}
