import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:gal/gal.dart';
import 'package:image_picker/image_picker.dart';
import 'package:video_player/video_player.dart';
import 'package:video_thumbnail/video_thumbnail.dart';

import '../../widgets/compressing_progress_dialog.dart';
import '../../widgets/pick_video_panel.dart';
import '../../services/video_edit_service.dart';
import 'pro_audio_session.dart';
import 'pro_audio_sheet.dart';
import 'pro_canvas_editor_preview.dart';
import 'pro_canvas_screen.dart';
import 'pro_canvas_session.dart';
import 'pro_crop_sheet.dart';
import 'pro_edit_feature_catalog.dart';
import 'pro_editor_timeline.dart';
import 'pro_export_result_screen.dart';
import 'pro_phase3_tool_sheets.dart';
import 'pro_studio_theme.dart';
import 'pro_trim_panel.dart';

class ProVideoEditorScreen extends StatefulWidget {
  const ProVideoEditorScreen({super.key});

  @override
  State<ProVideoEditorScreen> createState() => _ProVideoEditorScreenState();
}

class _ProVideoEditorScreenState extends State<ProVideoEditorScreen> {
  final ImagePicker _picker = ImagePicker();
  File? _file;
  VideoPlayerController? _controller;
  List<Uint8List?> _thumbs = [];
  bool _clipMuted = false;

  /// Timeline trim in-point / out-point (preview + trim sheet initial range).
  Duration _timelineTrimStart = Duration.zero;
  Duration _timelineTrimEnd = Duration.zero;

  /// Paths of FFmpeg trim outputs created this session (for cleanup).
  final List<String> _createdTrimPaths = [];
  final List<String> _undoStack = [];
  final List<String> _redoStack = [];
  ProAudioMixSession? _audioMixSession;

  /// Framing from Canvas (✓); `null` = full-frame preview like before Canvas.
  ProCanvasSessionSettings? _canvasSession;

  @override
  void dispose() {
    final keep = <String>{
      ..._undoStack,
      ..._redoStack,
      if (_file != null) _file!.path,
    };
    for (final path in _createdTrimPaths) {
      if (!keep.contains(path)) {
        VideoEditService.deleteFileIfExists(path);
      }
    }
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _pickVideo() async {
    final x = await _picker.pickVideo(source: ImageSource.gallery);
    if (x == null) return;
    final file = File(x.path);
    for (final path in _createdTrimPaths) {
      await VideoEditService.deleteFileIfExists(path);
    }
    _createdTrimPaths.clear();
    _undoStack.clear();
    _redoStack.clear();
    _audioMixSession = null;
    _canvasSession = null;
    await _swap(file);
    if (!mounted) return;
    setState(() => _file = file);
  }

  Future<void> _swap(File file) async {
    final old = _controller;
    final next = VideoPlayerController.file(file);
    await next.initialize();
    await next.setVolume(_clipMuted ? 0 : 1);
    await next.pause();
    old?.dispose();
    _controller = next;
    _timelineTrimStart = Duration.zero;
    _timelineTrimEnd = next.value.duration;
    await _regenerateThumbs(file.path, next.value.duration);
    if (mounted) setState(() {});
  }

  Future<void> _regenerateThumbs(String path, Duration duration) async {
    const n = 6;
    if (duration.inMilliseconds <= 0) {
      setState(() => _thumbs = List<Uint8List?>.filled(n, null));
      return;
    }
    final out = <Uint8List?>[];
    for (var i = 0; i < n; i++) {
      final ms = ((duration.inMilliseconds * (i + 0.5)) / n).round();
      try {
        final b = await VideoThumbnail.thumbnailData(
          video: path,
          timeMs: ms,
          imageFormat: ImageFormat.JPEG,
          quality: 42,
          maxWidth: 200,
        );
        out.add(b);
      } catch (_) {
        out.add(null);
      }
    }
    if (mounted) setState(() => _thumbs = out);
  }

  void _toggleMute() {
    final c = _controller;
    if (c == null || !c.value.isInitialized) return;
    setState(() {
      _clipMuted = !_clipMuted;
      c.setVolume(_clipMuted ? 0 : 1);
    });
  }

  Future<void> _togglePlay() async {
    final c = _controller;
    if (c == null || !c.value.isInitialized) return;
    if (c.value.isPlaying) {
      await c.pause();
    } else {
      await c.play();
    }
    setState(() {});
  }

  void _openFullscreen() {
    final c = _controller;
    if (c == null || !c.value.isInitialized) return;
    showDialog<void>(
      context: context,
      useSafeArea: false,
      barrierColor: Colors.black,
      builder: (ctx) {
        return Dialog.fullscreen(
          backgroundColor: Colors.black,
          child: Stack(
            fit: StackFit.expand,
            children: [
              Center(
                child: AspectRatio(
                  aspectRatio: c.value.aspectRatio == 0 ? 16 / 9 : c.value.aspectRatio,
                  child: VideoPlayer(c),
                ),
              ),
              Positioned(
                top: MediaQuery.paddingOf(ctx).top + 8,
                left: 8,
                child: IconButton(
                  onPressed: () => Navigator.pop(ctx),
                  icon: const Icon(Icons.close_rounded, color: Colors.white, size: 28),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _pushUndoCheckpoint() {
    final path = _file?.path;
    if (path == null) return;
    _undoStack.add(path);
    _redoStack.clear();
  }

  Future<void> _undo() async {
    if (_undoStack.isEmpty) return;
    final cur = _file?.path;
    if (cur != null) _redoStack.add(cur);
    final prev = _undoStack.removeLast();
    await _swap(File(prev));
    if (!mounted) return;
    setState(() {
      _file = File(prev);
      _audioMixSession = invalidateAudioSessionIfStale(_audioMixSession, prev);
    });
  }

  Future<void> _redo() async {
    if (_redoStack.isEmpty) return;
    final cur = _file?.path;
    if (cur != null) _undoStack.add(cur);
    final next = _redoStack.removeLast();
    await _swap(File(next));
    if (!mounted) return;
    setState(() {
      _file = File(next);
      _audioMixSession = invalidateAudioSessionIfStale(_audioMixSession, next);
    });
  }

  Future<void> _commitEncodedOutput(String newPath) async {
    _pushUndoCheckpoint();
    _createdTrimPaths.add(newPath);
    await _swap(File(newPath));
    if (!mounted) return;
    setState(() {
      _file = File(newPath);
      _audioMixSession = invalidateAudioSessionIfStale(_audioMixSession, newPath);
    });
  }

  Future<void> _commitAudioMixOutput(String outputPath, ProAudioMixSession session) async {
    _pushUndoCheckpoint();
    _createdTrimPaths.add(outputPath);
    await _swap(File(outputPath));
    if (!mounted) return;
    setState(() {
      _file = File(outputPath);
      _audioMixSession = session;
    });
  }

  Future<void> _openTrim() async {
    final c = _controller;
    final f = _file;
    if (c == null || f == null || !c.value.isInitialized) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Load a video and wait for it to finish loading.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return;
    }
    final d = c.value.duration;
    RangeValues? initial;
    if (d.inMilliseconds > 0) {
      initial = RangeValues(
        (_timelineTrimStart.inMilliseconds / d.inMilliseconds).clamp(0.0, 1.0),
        (_timelineTrimEnd.inMilliseconds / d.inMilliseconds).clamp(0.0, 1.0),
      );
    }
    await showProTrimSheet(
      context: context,
      videoController: c,
      videoPath: f.path,
      initialTrimRange: initial,
      onApplied: (newPath) => _commitEncodedOutput(newPath),
    );
  }

  void _onRibbonTool(String id, String label) {
    final c = _controller;
    final f = _file;
    final ready = f != null && c != null && c.value.isInitialized;

    switch (id) {
      case 'trim':
      case 'precut':
        _openTrim();
        return;
      case 'replace':
        _pickVideo();
        return;
      case 'canvas':
        if (!ready) {
          _snackVideoNotReady();
          return;
        }
        showProCanvasScreen(
          context,
          controller: c,
          videoPath: f.path,
          initialSession: _canvasSession,
        ).then((applied) {
          if (!mounted) return;
          if (applied != null) setState(() => _canvasSession = applied);
        });
        return;
      case 'audio':
        if (!ready) {
          _snackVideoNotReady();
          return;
        }
        showProAudioSheet(
          context,
          videoPath: f.path,
          initialSession: _audioMixSession,
          onCommit: _commitAudioMixOutput,
          onForgetSession: () {
            if (mounted) setState(() => _audioMixSession = null);
          },
        );
        return;
      case 'speed':
        if (!ready) {
          _snackVideoNotReady();
          return;
        }
        showProSpeedSheet(context, f.path, _commitEncodedOutput);
        return;
      case 'rotate':
      case 'flip':
        if (!ready) {
          _snackVideoNotReady();
          return;
        }
        showProRotateFlipSheet(context, f.path, _commitEncodedOutput);
        return;
      case 'volume':
        if (!ready) {
          _snackVideoNotReady();
          return;
        }
        showProVolumeSheet(context, f.path, _commitEncodedOutput);
        return;
      case 'crop':
        if (!ready) {
          _snackVideoNotReady();
          return;
        }
        final sz = c.value.size;
        final fw = sz.width.round().clamp(2, 16384);
        final fh = sz.height.round().clamp(2, 16384);
        showProCropSheet(
          context,
          videoPath: f.path,
          fallbackWidth: fw,
          fallbackHeight: fh,
          onApplied: _commitEncodedOutput,
        );
        return;
      case 'split':
        if (!ready) {
          _snackVideoNotReady();
          return;
        }
        showProSplitSheet(
          context,
          path: f.path,
          total: c.value.duration,
          playhead: c.value.position,
          onApplied: _commitEncodedOutput,
        );
        return;
      case 'reverse':
        if (!ready) {
          _snackVideoNotReady();
          return;
        }
        showProReverseSheet(context, f.path, _commitEncodedOutput);
        return;
      case 'duplicate':
        if (!ready) {
          _snackVideoNotReady();
          return;
        }
        _duplicateClip();
        return;
      case 'delete':
        _confirmLeaveEditor();
        return;
      default:
        _comingSoonSheet(id, label);
    }
  }

  void _snackVideoNotReady() {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Video is still loading. Try again in a moment.'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _duplicateClip() async {
    final f = _file;
    if (f == null) return;
    try {
      final out = await VideoEditService.duplicateToTemp(f.path);
      await _commitEncodedOutput(out);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Duplicate failed: $e'), behavior: SnackBarBehavior.floating),
      );
    }
  }

  Future<void> _confirmLeaveEditor() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF2A2A2A),
        title: const Text('Leave editor?', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
        content: const Text(
          'You will return to the previous screen. Pick the video again to continue editing.',
          style: TextStyle(color: Colors.white70, height: 1.35),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: ProStudioTheme.pinkTop),
            child: const Text('Leave'),
          ),
        ],
      ),
    );
    if (ok == true && mounted) Navigator.of(context).pop();
  }

  Future<void> _appendClip() async {
    final f = _file;
    final c = _controller;
    if (f == null || c == null || !c.value.isInitialized) return;
    final x = await _picker.pickVideo(source: ImageSource.gallery);
    if (x == null) return;
    final secondPath = x.path;
    if (!mounted) return;
    final outPath = await showDialog<String?>(
      context: context,
      barrierDismissible: false,
      builder: (_) => CompressingProgressDialog(
        title: 'Joining clips',
        presetLabel: 'FFmpeg concat',
        job: (setProgress) => VideoEditService.concatTwoClips(
          firstPath: f.path,
          secondPath: secondPath,
          onProgress: setProgress,
        ),
      ),
    );
    if (!mounted || outPath == null || outPath.isEmpty) return;
    await _commitEncodedOutput(outPath);
  }

  void _openExportSheet() {
    final f = _file;
    if (f == null) return;
    final hasCanvas = _canvasSession != null;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF1E1E1E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Export',
                style: Theme.of(ctx).textTheme.titleLarge?.copyWith(color: Colors.white, fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 8),
              Text(
                hasCanvas
                    ? 'Save copies to Photos with canvas applied. View export opens a preview where you can play and share.'
                    : 'Save adds the clip to Photos. View export opens a preview where you can play and share.',
                style: Theme.of(ctx).textTheme.bodySmall?.copyWith(color: Colors.white60, height: 1.35),
              ),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: () async {
                  Navigator.pop(ctx);
                  final outPath = await _encodeForExportIfNeeded();
                  if (!mounted) return;
                  if (outPath == null) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Could not prepare export.'),
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                    return;
                  }
                  try {
                    await Gal.putVideo(outPath);
                    if (!mounted) return;
                    final isTemp = outPath != f.path;
                    await Navigator.of(context).push<void>(
                      MaterialPageRoute<void>(
                        builder: (_) => ProExportResultScreen(
                          videoPath: outPath,
                          deleteOnDispose: isTemp,
                          savedToGallery: true,
                        ),
                      ),
                    );
                  } catch (e) {
                    if (outPath != f.path) {
                      await VideoEditService.deleteFileIfExists(outPath);
                    }
                    if (!mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Could not save: $e'), behavior: SnackBarBehavior.floating),
                    );
                  }
                },
                icon: const Icon(Icons.download_rounded),
                label: const Text('Save to gallery'),
                style: FilledButton.styleFrom(backgroundColor: ProStudioTheme.pinkTop, padding: const EdgeInsets.symmetric(vertical: 14)),
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: () async {
                  Navigator.pop(ctx);
                  final outPath = await _encodeForExportIfNeeded();
                  if (!mounted) return;
                  if (outPath == null) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Could not prepare export.'),
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                    return;
                  }
                  final isTemp = outPath != f.path;
                  await Navigator.of(context).push<void>(
                    MaterialPageRoute<void>(
                      builder: (_) => ProExportResultScreen(
                        videoPath: outPath,
                        deleteOnDispose: isTemp,
                        savedToGallery: false,
                      ),
                    ),
                  );
                },
                icon: const Icon(Icons.slideshow_rounded, color: Colors.white),
                label: const Text('View export', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Colors.white24),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Returns a path to an MP4 for gallery/share: re-encoded when canvas is active, else the source [File] path.
  Future<String?> _encodeForExportIfNeeded() async {
    final f = _file;
    final c = _controller;
    if (f == null) return null;
    final session = _canvasSession;
    if (session == null || c == null || !c.value.isInitialized) {
      return f.path;
    }
    await c.pause();
    if (mounted) setState(() {});
    await Future<void>.delayed(const Duration(milliseconds: 80));
    if (!mounted) return null;
    final out = await showDialog<String?>(
      context: context,
      barrierDismissible: false,
      builder: (_) => CompressingProgressDialog(
        title: 'Applying canvas',
        presetLabel: 'Canvas framing (H.264)',
        job: (setProgress) => VideoEditService.applyCanvasComposition(
          inputPath: f.path,
          session: session,
          videoAspect: ProCanvasLayout.videoAspect(c),
          onProgress: setProgress,
        ),
      ),
    );
    if (out == null || out.isEmpty) return null;
    return out;
  }

  void _comingSoonSheet(String id, String label) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF1E1E1E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      isScrollControlled: true,
      builder: (ctx) {
        final bottom = MediaQuery.paddingOf(ctx).bottom;
        return Padding(
          padding: EdgeInsets.fromLTRB(24, 16, 24, 20 + bottom),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2)),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  label,
                  style: Theme.of(ctx).textTheme.titleLarge?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                      ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Not in this version',
                  style: Theme.of(ctx).textTheme.labelLarge?.copyWith(
                        color: ProStudioTheme.pinkTop,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.3,
                      ),
                ),
                const SizedBox(height: 14),
                Text(
                  proRibbonComingSoonMessage(id),
                  style: Theme.of(ctx).textTheme.bodyMedium?.copyWith(
                        color: Colors.white.withValues(alpha: 0.88),
                        height: 1.45,
                      ),
                ),
                const SizedBox(height: 18),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFF2A2418),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFFFD700).withValues(alpha: 0.35)),
                  ),
                  child: Text(
                    kProEditorAvailableNowLine,
                    style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                          color: const Color(0xFFFFE08A),
                          height: 1.45,
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () => Navigator.pop(ctx),
                    style: FilledButton.styleFrom(
                      backgroundColor: ProStudioTheme.pinkTop,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: const Text('Got it', style: TextStyle(fontWeight: FontWeight.w800)),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = _controller;
    final ready = _file != null && c != null && c.value.isInitialized;

    return Scaffold(
      backgroundColor: const Color(0xFF0B0B0B),
      body: Column(
        children: [
          SizedBox(height: MediaQuery.paddingOf(context).top),
          _topBar(context, ready),
          _adBannerPlaceholder(),
          Expanded(
            child: ready
                ? Column(
                    children: [
                      Expanded(
                        child: _canvasSession != null
                            ? ProCanvasEditorPreview(
                                controller: c,
                                session: _canvasSession!,
                                onTap: _togglePlay,
                              )
                            : GestureDetector(
                                onTap: _togglePlay,
                                child: Container(
                                  width: double.infinity,
                                  color: Colors.black,
                                  child: Stack(
                                    fit: StackFit.expand,
                                    children: [
                                      Center(
                                        child: AspectRatio(
                                          aspectRatio: c.value.aspectRatio == 0 ? 16 / 9 : c.value.aspectRatio,
                                          child: VideoPlayer(c),
                                        ),
                                      ),
                                      Positioned(
                                        right: 10,
                                        bottom: 10,
                                        child: Text(
                                          'VidPress',
                                          style: TextStyle(
                                            color: Colors.white.withValues(alpha: 0.55),
                                            fontWeight: FontWeight.w800,
                                            fontSize: 13,
                                            shadows: const [
                                              Shadow(blurRadius: 4, color: Colors.black54),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                      ),
                      _playbackBar(c),
                      _ribbon(),
                      _timelineBlock(c),
                    ],
                  )
                : Padding(
                    padding: const EdgeInsets.all(20),
                    child: PickVideoPanel(
                      onPick: _pickVideo,
                      title: 'Pick a video',
                      subtitle: 'Pro editor — InShot-style workflow',
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _topBar(BuildContext context, bool ready) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 20),
          ),
          IconButton(
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Zoom / help — coming soon.'), behavior: SnackBarBehavior.floating),
              );
            },
            icon: Icon(Icons.zoom_in_rounded, color: Colors.white.withValues(alpha: 0.92)),
          ),
          const Spacer(),
          TextButton(
            onPressed: ready ? _openExportSheet : null,
            child: Text(
              'Export',
              style: TextStyle(
                color: ready ? Colors.white : Colors.white24,
                fontWeight: FontWeight.w900,
                fontSize: 16,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _adBannerPlaceholder() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
      child: Container(
        height: 48,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          color: const Color(0xFF1A1A1A),
          border: Border.all(color: Colors.white12),
        ),
        child: Text(
          'Promo slot — plug native ad here',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.35),
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  Widget _playbackBar(VideoPlayerController c) {
    return Container(
      height: 48,
      color: const Color(0xFF121212),
      child: Row(
        children: [
          IconButton(
            onPressed: _undoStack.isNotEmpty ? _undo : null,
            icon: Icon(
              Icons.undo_rounded,
              color: _undoStack.isNotEmpty ? Colors.white : Colors.white.withValues(alpha: 0.2),
            ),
          ),
          IconButton(
            onPressed: _redoStack.isNotEmpty ? _redo : null,
            icon: Icon(
              Icons.redo_rounded,
              color: _redoStack.isNotEmpty ? Colors.white : Colors.white.withValues(alpha: 0.2),
            ),
          ),
          Expanded(
            child: Center(
              child: _ProPlaybackTimecode(controller: c),
            ),
          ),
          IconButton(
            iconSize: 40,
            onPressed: _togglePlay,
            icon: Icon(
              c.value.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
              color: Colors.white,
            ),
          ),
          IconButton(
            onPressed: _openFullscreen,
            icon: Icon(Icons.open_in_full_rounded, color: Colors.white.withValues(alpha: 0.85)),
          ),
        ],
      ),
    );
  }

  Widget _ribbon() {
    return SizedBox(
      height: 96,
      child: ColoredBox(
        color: const Color(0xFF101010),
        child: ListView.builder(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          itemCount: kProInShotRibbonTools.length,
          itemBuilder: (context, i) {
            final t = kProInShotRibbonTools[i];
            return Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (t.showDividerBefore)
                  Padding(
                    padding: const EdgeInsets.only(left: 6, right: 10),
                    child: Container(
                      width: 1,
                      height: 52,
                      color: Colors.white24,
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.only(right: 14),
                  child: InkWell(
                    onTap: () => _onRibbonTool(t.id, t.label),
                    borderRadius: BorderRadius.circular(12),
                    child: SizedBox(
                      width: 64,
                      child: Column(
                        children: [
                          Icon(t.icon, color: Colors.white, size: 28),
                          const SizedBox(height: 6),
                          Text(
                            t.label,
                            textAlign: TextAlign.center,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.75),
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              height: 1.1,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _timelineBlock(VideoPlayerController c) {
    return Container(
      width: double.infinity,
      color: const Color(0xFF1A1A1A),
      padding: const EdgeInsets.fromLTRB(8, 6, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [

          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Material(
                color: Colors.red,
                borderRadius: BorderRadius.circular(8),
                child: InkWell(
                  onTap: _appendClip,
                  borderRadius: BorderRadius.circular(8),
                  child: const SizedBox(
                    width: 48,
                    height: 48,
                    child: Icon(Icons.add_rounded, color: Colors.white, size: 28),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 52,
                child: InkWell(
                  onTap: _toggleMute,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _clipMuted ? Icons.volume_off_rounded : Icons.volume_up_rounded,
                        color: Colors.white70,
                        size: 22,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Mute clip',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.55),
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                          height: 1.15,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ProEditorTimeline(
                  controller: c,
                  thumbnails: _thumbs,
                  trimStart: _timelineTrimStart,
                  trimEnd: _timelineTrimEnd,
                  onTrimStartChanged: (v) => setState(() => _timelineTrimStart = v),
                  onTrimEndChanged: (v) => setState(() => _timelineTrimEnd = v),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ProPlaybackTimecode extends StatefulWidget {
  const _ProPlaybackTimecode({required this.controller});

  final VideoPlayerController controller;

  @override
  State<_ProPlaybackTimecode> createState() => _ProPlaybackTimecodeState();
}

class _ProPlaybackTimecodeState extends State<_ProPlaybackTimecode> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_tick);
  }

  @override
  void didUpdateWidget(covariant _ProPlaybackTimecode oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_tick);
      widget.controller.addListener(_tick);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_tick);
    super.dispose();
  }

  void _tick() {
    if (mounted) setState(() {});
  }

  static String _fmt(Duration d) {
    String two(int n) => n.toString().padLeft(2, '0');
    final m = d.inMinutes.remainder(60);
    final s = d.inSeconds.remainder(60);
    return '${two(m)}:${two(s)}';
  }

  @override
  Widget build(BuildContext context) {
    final v = widget.controller.value;
    if (!v.isInitialized) return const SizedBox.shrink();
    return Text(
      '${_fmt(v.position)} / ${_fmt(v.duration)}',
      maxLines: 1,
      overflow: TextOverflow.fade,
      softWrap: false,
      style: TextStyle(
        color: Colors.white.withValues(alpha: 0.88),
        fontSize: 12,
        fontWeight: FontWeight.w700,
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
    );
  }
}
