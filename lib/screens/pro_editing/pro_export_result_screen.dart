import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:video_player/video_player.dart';
import 'package:video_thumbnail/video_thumbnail.dart';

import '../../services/video_edit_service.dart';
import 'pro_studio_theme.dart';

/// Shown after a successful export (pushed on top of the editor so you can go back).
class ProExportResultScreen extends StatefulWidget {
  const ProExportResultScreen({
    super.key,
    required this.videoPath,
    required this.deleteOnDispose,
    this.savedToGallery = false,
  });

  final String videoPath;
  final bool deleteOnDispose;

  /// When true, show a short confirmation line (save path already wrote to Photos).
  final bool savedToGallery;

  @override
  State<ProExportResultScreen> createState() => _ProExportResultScreenState();
}

class _ProExportResultScreenState extends State<ProExportResultScreen> {
  Uint8List? _thumb;
  bool _thumbFailed = false;

  @override
  void initState() {
    super.initState();
    _loadThumb();
  }

  @override
  void dispose() {
    if (widget.deleteOnDispose) {
      final p = widget.videoPath;
      Future<void>.delayed(const Duration(milliseconds: 400), () {
        VideoEditService.deleteFileIfExists(p);
      });
    }
    super.dispose();
  }

  Future<void> _loadThumb() async {
    try {
      final b = await VideoThumbnail.thumbnailData(
        video: widget.videoPath,
        timeMs: 400,
        imageFormat: ImageFormat.JPEG,
        quality: 72,
        maxWidth: 720,
      );
      if (mounted) setState(() => _thumb = b);
    } catch (_) {
      if (mounted) setState(() => _thumbFailed = true);
    }
  }

  Future<void> _openFullscreenPlay() async {
    await showDialog<void>(
      context: context,
      useSafeArea: false,
      barrierColor: Colors.black,
      builder: (ctx) => _ExportFullscreenPlayer(path: widget.videoPath),
    );
  }

  Future<void> _share() async {
    try {
      await Share.shareXFiles([XFile(widget.videoPath)], text: 'Edited with VidPress');
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Share failed: $e'), behavior: SnackBarBehavior.floating),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B0B0B),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0B0B0B),
        foregroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text(
          'Export',
          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
        ),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.savedToGallery)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text(
                'Saved to your gallery.',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.65),
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text(
                'Your export is ready. Play below or share.',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.65),
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: Material(
                color: const Color(0xFF1A1A1A),
                borderRadius: BorderRadius.circular(16),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: _openFullscreenPlay,
                  child: Stack(
                    fit: StackFit.expand,
                    alignment: Alignment.center,
                    children: [
                      if (_thumb != null)
                        Image.memory(
                          _thumb!,
                          fit: BoxFit.contain,
                          gaplessPlayback: true,
                        )
                      else if (_thumbFailed)
                        Icon(Icons.videocam_off_rounded, size: 56, color: Colors.white.withValues(alpha: 0.35))
                      else
                        const Center(child: CircularProgressIndicator(color: Colors.white54)),
                      Positioned(
                        bottom: 0,
                        left: 0,
                        right: 0,
                        height: 120,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                Colors.transparent,
                                Colors.black.withValues(alpha: 0.55),
                              ],
                            ),
                          ),
                        ),
                      ),
                      Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Material(
                            color: Colors.white.withValues(alpha: 0.22),
                            shape: const CircleBorder(),
                            child: IconButton(
                              iconSize: 52,
                              onPressed: _openFullscreenPlay,
                              icon: const Icon(Icons.play_arrow_rounded, color: Colors.white),
                            ),
                          ),
                          const SizedBox(height: 14),
                          Text(
                            'Tap to play',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.9),
                              fontWeight: FontWeight.w700,
                              fontSize: 15,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
              child: FilledButton.icon(
                onPressed: _share,
                icon: const Icon(Icons.share_rounded),
                label: const Text('Share', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                style: FilledButton.styleFrom(
                  backgroundColor: ProStudioTheme.pinkTop,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ExportFullscreenPlayer extends StatefulWidget {
  const _ExportFullscreenPlayer({required this.path});

  final String path;

  @override
  State<_ExportFullscreenPlayer> createState() => _ExportFullscreenPlayerState();
}

class _ExportFullscreenPlayerState extends State<_ExportFullscreenPlayer> {
  late final VideoPlayerController _controller;

  void _onVideoTick() {
    if (mounted) setState(() {});
  }

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.file(File(widget.path));
    _controller.initialize().then((_) async {
      if (!mounted) return;
      _controller.addListener(_onVideoTick);
      setState(() {});
      await _controller.play();
    });
  }

  @override
  void dispose() {
    _controller.removeListener(_onVideoTick);
    _controller.dispose();
    super.dispose();
  }

  Future<void> _close() async {
    await _controller.pause();
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final ready = _controller.value.isInitialized;
    final ar = _controller.value.aspectRatio == 0 ? 16 / 9 : _controller.value.aspectRatio;

    return Dialog.fullscreen(
      backgroundColor: Colors.black,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (ready)
            Center(
              child: AspectRatio(
                aspectRatio: ar,
                child: VideoPlayer(_controller),
              ),
            )
          else
            const Center(child: CircularProgressIndicator(color: Colors.white54)),
          Positioned(
            top: MediaQuery.paddingOf(context).top + 8,
            left: 8,
            child: IconButton(
              onPressed: _close,
              icon: const Icon(Icons.close_rounded, color: Colors.white, size: 28),
            ),
          ),
          if (ready)
            Positioned(
              bottom: MediaQuery.paddingOf(context).bottom + 24,
              left: 0,
              right: 0,
              child: Center(
                child: Material(
                  color: Colors.white.withValues(alpha: 0.22),
                  shape: const CircleBorder(),
                  child: IconButton(
                    iconSize: 44,
                    onPressed: () async {
                      if (_controller.value.isPlaying) {
                        await _controller.pause();
                      } else {
                        await _controller.play();
                      }
                      setState(() {});
                    },
                    icon: Icon(
                      _controller.value.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                      color: Colors.white,
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
