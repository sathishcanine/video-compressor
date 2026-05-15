import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:video_player/video_player.dart';

import '../../services/video_edit_service.dart';
import 'pro_audio_session.dart';
import 'pro_canvas_editor_preview.dart';
import 'pro_canvas_session.dart';
import 'pro_studio_theme.dart';

class _TimelineAudioClip {
  _TimelineAudioClip({
    required this.id,
    required this.path,
    required this.linearGain,
  });

  final String id;
  final String path;
  double linearGain;
}

/// Full-screen audio workspace: preview, tool strip, stacked music lanes above video, pinch-zoom timeline.
class ProAudioTimelineScreen extends StatefulWidget {
  const ProAudioTimelineScreen({
    super.key,
    required this.controller,
    required this.videoPath,
    required this.thumbnails,
    required this.trimStart,
    required this.trimEnd,
    this.canvasSession,
    this.initialSession,
    required this.onCommit,
    required this.onForgetSession,
  });

  final VideoPlayerController controller;
  final String videoPath;
  final List<Uint8List?> thumbnails;
  final Duration trimStart;
  final Duration trimEnd;
  final ProCanvasSessionSettings? canvasSession;
  final ProAudioMixSession? initialSession;
  final Future<void> Function(String outputPath, ProAudioMixSession session) onCommit;
  final VoidCallback onForgetSession;

  @override
  State<ProAudioTimelineScreen> createState() => _ProAudioTimelineScreenState();
}

class _ProAudioTimelineScreenState extends State<ProAudioTimelineScreen> {
  static const _laneH = 44.0;
  static const _maxVisibleLanes = 5;
  static const _stripH = 60.0;
  static const _rulerH = 18.0;
  static const _timeRowH = 36.0;
  static const _bg = Color(0xFF1A1A1A);

  final List<_TimelineAudioClip> _clips = [];
  String? _selectedClipId;
  double _clipGain = 1;
  bool _busy = false;
  double _progress = 0;
  bool? _clipHasAudio;
  String? _activeToolId;
  bool _clearedRememberedUi = false;

  final ScrollController _hScroll = ScrollController();
  double _zoom = 1.0;
  double _pinchBaseZoom = 1.0;
  double _pinchFocalScrollOffset = 0;
  double _pinchFocalFilmstripU = 0;
  bool _programmaticScroll = false;
  double _lastViewportW = 0;
  double _lastFilmstripW = 0;
  Timer? _seekDebounce;
  bool _initialScrollDone = false;
  bool _initialScrollScheduled = false;

  bool get _hasRememberedMix =>
      !_clearedRememberedUi &&
      widget.initialSession != null &&
      widget.initialSession!.clipPathAfterMix == widget.videoPath &&
      widget.initialSession!.musicLayers.isNotEmpty;

  @override
  void initState() {
    super.initState();
    _hydrateFromSession();
    widget.controller.addListener(_onVideo);
    _hScroll.addListener(_onHorizontalScroll);
    VideoEditService.inputHasAudio(widget.videoPath).then((v) {
      if (mounted) setState(() => _clipHasAudio = v);
    });
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onVideo);
    _hScroll.removeListener(_onHorizontalScroll);
    _seekDebounce?.cancel();
    _hScroll.dispose();
    super.dispose();
  }

  void _hydrateFromSession() {
    final s = widget.initialSession;
    if (s != null && s.clipPathAfterMix == widget.videoPath && s.musicLayers.isNotEmpty) {
      final next = <_TimelineAudioClip>[];
      for (final layer in s.musicLayers) {
        if (File(layer.path).existsSync()) {
          next.add(_TimelineAudioClip(
            id: '${next.length}_${layer.path.hashCode}',
            path: layer.path,
            linearGain: layer.linearGain,
          ));
        }
      }
      _clips
        ..clear()
        ..addAll(next);
      _clipGain = s.clipLinearGain;
      _selectedClipId = _clips.isEmpty ? null : _clips.last.id;
    } else {
      _clips.clear();
      _selectedClipId = null;
      _clipGain = 1;
    }
  }

  Duration get _total => widget.controller.value.duration;
  int get _totalMs => _total.inMilliseconds;

  double _filmstripWidth(double viewportW) {
    if (viewportW <= 0 || _totalMs <= 0) return viewportW;
    return math.max(viewportW, viewportW * _zoom);
  }

  Duration _timeAtScrollOffset(double scrollOffset, double filmstripW) {
    if (filmstripW <= 0 || _totalMs <= 0) return Duration.zero;
    final u = scrollOffset.clamp(0.0, filmstripW);
    return Duration(milliseconds: (u / filmstripW * _totalMs).round().clamp(0, _totalMs));
  }

  Future<void> _seekToScrollOffset(double scrollOffset, double filmstripW) async {
    final t = _timeAtScrollOffset(scrollOffset, filmstripW);
    await widget.controller.seekTo(t);
    if (mounted) setState(() {});
  }

  void _onHorizontalScroll() {
    if (_programmaticScroll) return;
    if (mounted) setState(() {});
    final w = _lastFilmstripW;
    if (w <= 0) return;
    _seekDebounce?.cancel();
    _seekDebounce = Timer(const Duration(milliseconds: 45), () {
      if (!mounted || !_hScroll.hasClients) return;
      _seekToScrollOffset(_hScroll.offset, w);
    });
  }

  void _syncScrollToPosition({bool jump = false}) {
    final w = _lastFilmstripW;
    final v = _lastViewportW;
    if (w <= 0 || v <= 0 || _totalMs <= 0) return;
    final pos = widget.controller.value.position.inMilliseconds.clamp(0, _totalMs);
    final target = (pos / _totalMs) * w;
    if (!_hScroll.hasClients) return;
    final clamped = target.clamp(0.0, _hScroll.position.maxScrollExtent);
    _programmaticScroll = true;
    if (jump || (clamped - _hScroll.offset).abs() > 1.5) {
      _hScroll.jumpTo(clamped);
    }
    _programmaticScroll = false;
  }

  void _onVideo() {
    final c = widget.controller;
    if (!c.value.isInitialized) {
      if (mounted) setState(() {});
      return;
    }
    if (_totalMs <= 0) {
      if (mounted) setState(() {});
      return;
    }
    final ts = widget.trimStart;
    final te = widget.trimEnd;
    if (c.value.isPlaying) {
      final p = c.value.position;
      if (p.inMilliseconds < ts.inMilliseconds) {
        c.seekTo(ts);
      } else if (p.inMilliseconds >= te.inMilliseconds) {
        c.pause();
        c.seekTo(te);
      }
    }
    if (c.value.isPlaying) {
      _syncScrollToPosition();
    }
    if (mounted) setState(() {});
  }

  void _applyPinchZoom(double newZoom, double viewportW, double filmstripW) {
    final z = newZoom.clamp(1.0, 10.0);
    if ((z - _zoom).abs() < 0.001) return;
    final oldW = filmstripW;
    final newW = math.max(viewportW, viewportW * z);
    if (oldW <= 0 || newW <= 0 || _totalMs <= 0) {
      setState(() => _zoom = z);
      return;
    }
    final focalU = _pinchFocalFilmstripU.clamp(0.0, oldW);
    final focalFrac = focalU / oldW;
    final newScroll = focalFrac * newW - (viewportW / 2 - _pinchFocalScrollOffset);
    setState(() => _zoom = z);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_hScroll.hasClients) return;
      _programmaticScroll = true;
      _hScroll.jumpTo(newScroll.clamp(0.0, _hScroll.position.maxScrollExtent));
      _programmaticScroll = false;
    });
  }

  Future<void> _onTapStrip(TapUpDetails d, double viewportW, double filmstripW) async {
    if (filmstripW <= 0 || _totalMs <= 0) return;
    if (!_hScroll.hasClients) return;
    if (d.localPosition.dy < _rulerH) return;
    final localX = d.localPosition.dx.clamp(0.0, filmstripW);
    final maxS = _hScroll.position.maxScrollExtent;
    final targetScroll = localX.clamp(0.0, maxS);
    _programmaticScroll = true;
    _hScroll.jumpTo(targetScroll);
    _programmaticScroll = false;
    await _seekToScrollOffset(targetScroll, filmstripW);
  }

  static String _formatMmSsTenths(Duration d) {
    final m = d.inMinutes;
    final sDec = (d.inMilliseconds % 60000) / 1000.0;
    final sStr = sDec.toStringAsFixed(1);
    final dot = sStr.indexOf('.');
    final intPart = dot >= 0 ? sStr.substring(0, dot) : sStr;
    final decPart = dot >= 0 ? sStr.substring(dot + 1) : '0';
    return '$m:${intPart.padLeft(2, '0')}.$decPart';
  }

  static String _rulerLabelMmSs(int totalSeconds) {
    final m = totalSeconds ~/ 60;
    final s = totalSeconds % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  static int _rulerMajorStepSec(double filmstripW, double viewportW, int totalMs) {
    if (totalMs <= 0) return 2;
    final secVisible = (totalMs / 1000) * (viewportW / filmstripW);
    if (secVisible <= 8) return 1;
    if (secVisible <= 20) return 2;
    if (secVisible <= 45) return 5;
    return 10;
  }

  Future<void> _togglePlay() async {
    final c = widget.controller;
    if (!c.value.isInitialized) return;
    if (c.value.isPlaying) {
      await c.pause();
    } else {
      await c.play();
    }
    setState(() {});
  }

  Future<void> _pickMusic() async {
    final r = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['mp3', 'm4a', 'aac', 'wav', 'ogg', 'flac'],
      withData: false,
    );
    if (r == null || r.files.isEmpty) return;
    final path = r.files.single.path;
    if (path == null || path.isEmpty) return;
    final id = '${DateTime.now().microsecondsSinceEpoch}';
    setState(() {
      _clips.add(_TimelineAudioClip(id: id, path: path, linearGain: 0.35));
      _selectedClipId = id;
    });
  }

  void _deleteSelected() {
    final id = _selectedClipId;
    if (id == null) return;
    setState(() {
      _clips.removeWhere((c) => c.id == id);
      _selectedClipId = _clips.isEmpty ? null : _clips.last.id;
    });
  }

  void _volumeSelected() {
    final id = _selectedClipId;
    if (id == null) return;
    _TimelineAudioClip? clip;
    for (final c in _clips) {
      if (c.id == id) {
        clip = c;
        break;
      }
    }
    if (clip == null) return;
    final clipRef = clip;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF242424),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) {
        var g = clipRef.linearGain;
        return StatefulBuilder(
          builder: (ctx, setModal) {
            return Padding(
              padding: EdgeInsets.fromLTRB(20, 16, 20, 16 + MediaQuery.paddingOf(ctx).bottom),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    p.basename(clipRef.path),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 16),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Track volume ${(g * 100).round()}%',
                    style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontWeight: FontWeight.w700),
                  ),
                  Slider(
                    value: g.clamp(0, 4),
                    min: 0,
                    max: 4,
                    divisions: 80,
                    activeColor: ProStudioTheme.pinkTop,
                    onChanged: (v) {
                      setModal(() => g = v);
                      setState(() => clipRef.linearGain = v);
                    },
                  ),
                  FilledButton(
                    onPressed: () => Navigator.pop(ctx),
                    style: FilledButton.styleFrom(backgroundColor: ProStudioTheme.pinkTop),
                    child: const Text('Done', style: TextStyle(fontWeight: FontWeight.w900)),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  void _stubTool(String name) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$name — coming soon'), behavior: SnackBarBehavior.floating),
    );
  }

  int _committedMixIndex() {
    final prev = widget.initialSession;
    if (prev == null || prev.clipPathAfterMix != widget.videoPath) return 1;
    return prev.mixIndex + 1;
  }

  Future<void> _applyMix() async {
    if (_clips.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Add music from the Music button first.'), behavior: SnackBarBehavior.floating),
      );
      return;
    }
    for (final c in _clips) {
      if (!File(c.path).existsSync()) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('A track file is missing. Remove it or pick again.'), behavior: SnackBarBehavior.floating),
        );
        return;
      }
    }

    setState(() {
      _busy = true;
      _progress = 0;
    });
    try {
      final layers = _clips.map((c) => (path: c.path, linearGain: c.linearGain)).toList(growable: false);
      final out = await VideoEditService.mixBackgroundMusicLayers(
        videoPath: widget.videoPath,
        clipLinearGain: _clipGain,
        musicLayers: layers,
        onProgress: (p) {
          if (mounted) setState(() => _progress = p);
        },
      );
      if (!mounted) return;
      final session = ProAudioMixSession(
        musicLayers: _clips
            .map((c) => ProAudioMusicLayer(path: c.path, linearGain: c.linearGain))
            .toList(growable: false),
        clipLinearGain: _clipGain,
        clipPathAfterMix: out,
        mixIndex: _committedMixIndex(),
      );
      await widget.onCommit(out, session);
      if (!mounted) return;
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Audio mix failed: $e'), behavior: SnackBarBehavior.floating),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _clearRemembered() {
    setState(() {
      _clearedRememberedUi = true;
      _clips.clear();
      _selectedClipId = null;
      _clipGain = 1;
    });
    widget.onForgetSession();
  }

  Widget _audioToolChip({
    required String id,
    required IconData icon,
    required String label,
    required bool enabled,
    required VoidCallback? onTap,
  }) {
    final active = _activeToolId == id;
    final color = !enabled
        ? Colors.white24
        : active
            ? ProStudioTheme.pinkTop
            : Colors.white.withValues(alpha: 0.88);
    return Padding(
      padding: const EdgeInsets.only(right: 14),
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(12),
        child: SizedBox(
          width: 64,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: color, size: 26),
              const SizedBox(height: 4),
              Text(
                label,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w700, height: 1.1),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    final ready = c.value.isInitialized;
    final thumbs = widget.thumbnails.isEmpty ? List<Uint8List?>.filled(6, null) : widget.thumbnails;

    return PopScope(
      canPop: !_busy,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && _busy) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Mix in progress — wait for it to finish.'), behavior: SnackBarBehavior.floating),
          );
        }
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF0B0B0B),
        body: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(6, 4, 6, 0),
                child: Row(
                  children: [
                    IconButton(
                      onPressed: _busy ? null : () => Navigator.pop(context),
                      icon: Icon(Icons.close_rounded, color: Colors.white.withValues(alpha: 0.9)),
                    ),
                    const Expanded(
                      child: Text(
                        'Audio',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 17),
                      ),
                    ),
                    IconButton(
                      onPressed: _busy ? null : _applyMix,
                      icon: const Icon(Icons.check_rounded, color: Colors.white, size: 28),
                    ),
                  ],
                ),
              ),
              Expanded(
                flex: 5,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(8, 0, 8, 4),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: ColoredBox(
                      color: Colors.black,
                      child: ready
                          ? (widget.canvasSession != null
                              ? ProCanvasEditorPreview(
                                  controller: c,
                                  session: widget.canvasSession!,
                                  onTap: _togglePlay,
                                )
                              : GestureDetector(
                                  onTap: _togglePlay,
                                  child: Center(
                                    child: AspectRatio(
                                      aspectRatio: c.value.aspectRatio == 0 ? 16 / 9 : c.value.aspectRatio,
                                      child: VideoPlayer(c),
                                    ),
                                  ),
                                ))
                          : const Center(child: CircularProgressIndicator(color: ProStudioTheme.pinkTop)),
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    IconButton(
                      onPressed: _busy ? null : _togglePlay,
                      icon: Icon(
                        c.value.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                        color: Colors.white,
                        size: 36,
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(
                height: 88,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  children: [
                    _audioToolChip(
                      id: 'music',
                      icon: Icons.library_music_rounded,
                      label: 'Music',
                      enabled: !_busy,
                      onTap: () {
                        setState(() => _activeToolId = 'music');
                        _pickMusic();
                      },
                    ),
                    _audioToolChip(
                      id: 'record',
                      icon: Icons.mic_rounded,
                      label: 'Record',
                      enabled: !_busy,
                      onTap: () => _stubTool('Record'),
                    ),
                    _audioToolChip(
                      id: 'volume',
                      icon: Icons.volume_up_rounded,
                      label: 'Volume',
                      enabled: !_busy && _selectedClipId != null,
                      onTap: _volumeSelected,
                    ),
                    _audioToolChip(
                      id: 'delete',
                      icon: Icons.delete_outline_rounded,
                      label: 'Delete',
                      enabled: !_busy && _selectedClipId != null,
                      onTap: _deleteSelected,
                    ),
                  ],
                ),
              ),
              if (_hasRememberedMix) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 0, 14, 6),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Layers from your last mix are shown. Clear to start empty.',
                          style: TextStyle(color: Colors.amber.shade200, fontSize: 12, fontWeight: FontWeight.w600),
                        ),
                      ),
                      TextButton(
                        onPressed: _busy ? null : _clearRemembered,
                        child: const Text('Clear', style: TextStyle(fontWeight: FontWeight.w800)),
                      ),
                    ],
                  ),
                ),
              ],
              if (_clipHasAudio == false)
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 0, 14, 6),
                  child: Text(
                    'This clip has no camera audio — export uses your music tracks only.',
                    style: TextStyle(color: Colors.amber.shade200, fontWeight: FontWeight.w600, fontSize: 12, height: 1.3),
                  ),
                ),
              if (_clipHasAudio != false)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Original clip ${(_clipGain * 100).round()}%',
                        style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.w800, fontSize: 12),
                      ),
                      Slider(
                        value: _clipGain.clamp(0, 4),
                        min: 0,
                        max: 4,
                        divisions: 80,
                        activeColor: ProStudioTheme.pinkTop,
                        onChanged: (_busy || _clipHasAudio != true) ? null : (v) => setState(() => _clipGain = v),
                      ),
                    ],
                  ),
                ),
              if (_busy) ...[
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Column(
                    children: [
                      LinearProgressIndicator(
                        value: _progress <= 0.02 ? null : _progress.clamp(0, 1),
                        backgroundColor: Colors.white12,
                        color: ProStudioTheme.pinkTop,
                        minHeight: 6,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Mixing…',
                        style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ],
              Expanded(
                flex: 4,
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    return _buildTimelineArea(constraints.maxWidth, thumbs);
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTimelineArea(double viewportW, List<Uint8List?> thumbs) {
    final total = _total;
    final totalMs = total.inMilliseconds;
    final v = viewportW;
    final w = _filmstripWidth(v);
    _lastViewportW = v;
    _lastFilmstripW = w;

    if (!_initialScrollDone && !_initialScrollScheduled && totalMs > 0 && v > 0) {
      _initialScrollScheduled = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _initialScrollScheduled = false;
        if (!mounted || !_hScroll.hasClients) return;
        _initialScrollDone = true;
        _syncScrollToPosition(jump: true);
      });
    }

    if (v <= 0 || totalMs <= 0) {
      return Container(
        color: _bg,
        alignment: Alignment.center,
        child: Text('Timeline unavailable', style: TextStyle(color: Colors.white.withValues(alpha: 0.4))),
      );
    }

    final pad = v / 2;
    final contentW = v + w;
    final majorStep = _rulerMajorStepSec(w, v, totalMs);
    final n = _clips.length;
    final audioContentH = n == 0 ? _laneH : n * _laneH;
    final audioViewportH = math.min(audioContentH, _maxVisibleLanes * _laneH);
    final needsAudioScroll = audioContentH > _maxVisibleLanes * _laneH;

    final laneColumn = Column(
      key: ValueKey('lanes_${n}_$w'),
      children: List.generate(math.max(1, n), (index) {
        if (n == 0) {
          return SizedBox(
            height: _laneH,
            child: Center(
              child: Text(
                'Tap Music to add a track',
                style: TextStyle(color: Colors.white.withValues(alpha: 0.35), fontWeight: FontWeight.w600, fontSize: 12),
              ),
            ),
          );
        }
        final clip = _clips[index];
        final selected = clip.id == _selectedClipId;
        return GestureDetector(
          onTap: () => setState(() => _selectedClipId = clip.id),
          child: Container(
            height: _laneH,
            margin: const EdgeInsets.only(bottom: 4),
            decoration: BoxDecoration(
              color: const Color(0xFF6B4FB8),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: selected ? Colors.white : Colors.white24, width: selected ? 2.5 : 1),
            ),
            alignment: Alignment.centerLeft,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: CustomPaint(
              painter: _DashedLinePainter(color: Colors.white.withValues(alpha: 0.35)),
              child: Text(
                p.basename(clip.path),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 12),
              ),
            ),
          ),
        );
      }),
    );

    final audioRegion = SizedBox(
      height: audioViewportH,
      child: needsAudioScroll
          ? Scrollbar(
              thumbVisibility: true,
              child: SingleChildScrollView(
                physics: const ClampingScrollPhysics(),
                child: SizedBox(width: w, child: laneColumn),
              ),
            )
          : SingleChildScrollView(
              physics: const NeverScrollableScrollPhysics(),
              child: SizedBox(width: w, child: laneColumn),
            ),
    );

    return GestureDetector(
      onScaleStart: (d) {
        if (d.pointerCount < 2) return;
        _pinchBaseZoom = _zoom;
        final localX = d.localFocalPoint.dx;
        final focalScroll = _hScroll.hasClients ? _hScroll.offset : 0.0;
        _pinchFocalScrollOffset = localX;
        _pinchFocalFilmstripU = (focalScroll + localX - v / 2).clamp(0.0, w);
      },
      onScaleUpdate: (d) {
        if (d.pointerCount < 2) return;
        _applyPinchZoom(_pinchBaseZoom * d.scale, v, w);
      },
      child: Container(
        color: _bg,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Positioned.fill(
                    child: NotificationListener<ScrollNotification>(
                      onNotification: (n) {
                        if (n is ScrollEndNotification && !_programmaticScroll) {
                          _seekDebounce?.cancel();
                          _seekToScrollOffset(_hScroll.offset, w);
                        }
                        return false;
                      },
                      child: SingleChildScrollView(
                        controller: _hScroll,
                        scrollDirection: Axis.horizontal,
                        physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
                        child: SizedBox(
                          width: contentW,
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              SizedBox(width: pad),
                              SizedBox(
                                width: w,
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.stretch,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    audioRegion,
                                    const SizedBox(height: 6),
                                    GestureDetector(
                                      behavior: HitTestBehavior.translucent,
                                      onTapUp: (d) => _onTapStrip(d, v, w),
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.stretch,
                                        children: [
                                          SizedBox(
                                            height: _rulerH,
                                            child: CustomPaint(
                                              painter: _AudioRulerPainter(
                                                filmstripWidth: w,
                                                duration: total,
                                                majorEverySec: majorStep,
                                                labelForSec: _rulerLabelMmSs,
                                              ),
                                              size: Size(w, _rulerH),
                                            ),
                                          ),
                                          SizedBox(
                                            height: _stripH,
                                            child: ClipRRect(
                                              borderRadius: BorderRadius.circular(4),
                                              child: Stack(
                                                fit: StackFit.expand,
                                                children: [
                                                  _FilmstripRow(
                                                    filmstripWidth: w,
                                                    stripHeight: _stripH,
                                                    thumbnails: thumbs,
                                                    duration: total,
                                                  ),
                                                  _TrimDimOverlay(
                                                    filmstripWidth: w,
                                                    trimStart: widget.trimStart,
                                                    trimEnd: widget.trimEnd,
                                                    total: total,
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              SizedBox(width: pad),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  Positioned.fill(
                    child: IgnorePointer(
                      child: Row(
                        children: [
                          Container(
                            width: 18,
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.centerLeft,
                                end: Alignment.centerRight,
                                colors: [_bg, _bg.withValues(alpha: 0)],
                              ),
                            ),
                          ),
                          const Spacer(),
                          Container(
                            width: 18,
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.centerRight,
                                end: Alignment.centerLeft,
                                colors: [_bg, _bg.withValues(alpha: 0)],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Positioned(
                    left: v / 2 - 5,
                    top: 0,
                    width: 10,
                    height: audioViewportH + 6 + _rulerH + _stripH,
                    child: const _CenterPlayheadColumn(),
                  ),
                ],
              ),
            ),
            SizedBox(
              height: _timeRowH,
              child: Stack(
                children: [
                  Positioned(
                    right: 8,
                    top: 0,
                    child: Text(
                      _formatMmSsTenths(total),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        fontFeatures: [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                  Positioned(
                    left: (v / 2 - 40).clamp(0.0, v - 80),
                    width: 80,
                    child: Text(
                      _formatMmSsTenths(_timeAtScrollOffset(_hScroll.hasClients ? _hScroll.offset : 0, w)),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        fontFeatures: [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DashedLinePainter extends CustomPainter {
  _DashedLinePainter({required this.color});
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final y = size.height / 2;
    const dash = 6.0;
    const gap = 4.0;
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1;
    var x = 0.0;
    while (x < size.width) {
      canvas.drawLine(Offset(x, y), Offset(math.min(x + dash, size.width), y), paint);
      x += dash + gap;
    }
  }

  @override
  bool shouldRepaint(covariant _DashedLinePainter oldDelegate) => oldDelegate.color != color;
}

class _CenterPlayheadColumn extends StatelessWidget {
  const _CenterPlayheadColumn();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        CustomPaint(
          size: const Size(10, 7),
          painter: _PlayheadTrianglePainter(),
        ),
        Expanded(
          child: Center(
            child: Container(width: 2, height: double.infinity, color: Colors.white),
          ),
        ),
      ],
    );
  }
}

class _PlayheadTrianglePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final paint = Paint()..color = Colors.white;
    final path = Path()
      ..moveTo(w / 2, 0)
      ..lineTo(0, size.height)
      ..lineTo(w, size.height)
      ..close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _FilmstripRow extends StatelessWidget {
  const _FilmstripRow({
    required this.filmstripWidth,
    required this.stripHeight,
    required this.thumbnails,
    required this.duration,
  });

  final double filmstripWidth;
  final double stripHeight;
  final List<Uint8List?> thumbnails;
  final Duration duration;

  @override
  Widget build(BuildContext context) {
    final n = math.max(8, (filmstripWidth / 56).ceil()).clamp(8, 160);
    final cellW = filmstripWidth / n;
    final ms = duration.inMilliseconds;
    return Row(
      children: List.generate(n, (i) {
        final tMs = ms > 0 ? (((i + 0.5) / n) * ms).round() : 0;
        final bin = ms > 0 ? ((tMs / ms) * thumbnails.length).floor().clamp(0, thumbnails.length - 1) : 0;
        final img = thumbnails[bin];
        return SizedBox(
          width: cellW,
          height: stripHeight,
          child: img != null
              ? Image.memory(img, fit: BoxFit.cover, gaplessPlayback: true)
              : const ColoredBox(color: Color(0xFF2C2C2C)),
        );
      }),
    );
  }
}

class _TrimDimOverlay extends StatelessWidget {
  const _TrimDimOverlay({
    required this.filmstripWidth,
    required this.trimStart,
    required this.trimEnd,
    required this.total,
  });

  final double filmstripWidth;
  final Duration trimStart;
  final Duration trimEnd;
  final Duration total;

  @override
  Widget build(BuildContext context) {
    final tm = total.inMilliseconds;
    if (tm <= 0 || filmstripWidth <= 0) return const SizedBox.shrink();
    final x0 = (trimStart.inMilliseconds / tm) * filmstripWidth;
    final x1 = (trimEnd.inMilliseconds / tm) * filmstripWidth;
    return Stack(
      fit: StackFit.expand,
      children: [
        if (x0 > 0)
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            width: x0,
            child: ColoredBox(color: Colors.black.withValues(alpha: 0.5)),
          ),
        if (x1 < filmstripWidth)
          Positioned(
            left: x1,
            top: 0,
            bottom: 0,
            right: 0,
            child: ColoredBox(color: Colors.black.withValues(alpha: 0.5)),
          ),
      ],
    );
  }
}

class _AudioRulerPainter extends CustomPainter {
  _AudioRulerPainter({
    required this.filmstripWidth,
    required this.duration,
    required this.majorEverySec,
    required this.labelForSec,
  });

  final double filmstripWidth;
  final Duration duration;
  final int majorEverySec;
  final String Function(int totalSeconds) labelForSec;

  @override
  void paint(Canvas canvas, Size size) {
    final w = filmstripWidth;
    final totalMs = duration.inMilliseconds;
    if (w <= 0 || totalMs <= 0) return;
    final totalSec = (totalMs / 1000).ceil().clamp(1, 8640000);

    final minorPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.22)
      ..strokeWidth = 1;
    final majorPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.35)
      ..strokeWidth = 1;
    const baseY = 2.0;
    final lineStep = totalSec > 2000
        ? 15
        : (totalSec > 600
            ? 5
            : (totalSec > 180 ? 2 : 1));

    for (var sec = 0; sec <= totalSec; sec += lineStep) {
      final x = (sec / totalSec) * w;
      final isMajor = sec % majorEverySec == 0;
      if (isMajor) {
        canvas.drawLine(Offset(x, baseY), Offset(x, baseY + 6), majorPaint);
      } else {
        canvas.drawLine(Offset(x, baseY), Offset(x, baseY + 4), minorPaint);
      }
    }

    final tp = TextPainter(textDirection: TextDirection.ltr);
    for (var sec = 0; sec <= totalSec; sec += majorEverySec) {
      final x = (sec / totalSec) * w;
      final label = labelForSec(sec);
      tp.text = TextSpan(
        text: label,
        style: TextStyle(
          color: Colors.white.withValues(alpha: 0.38),
          fontSize: 10,
          fontWeight: FontWeight.w600,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      );
      tp.layout();
      final lx = (x - tp.width / 2).clamp(0.0, w - tp.width);
      tp.paint(canvas, Offset(lx, baseY + 7));
    }
  }

  @override
  bool shouldRepaint(covariant _AudioRulerPainter oldDelegate) {
    return oldDelegate.filmstripWidth != filmstripWidth ||
        oldDelegate.duration != duration ||
        oldDelegate.majorEverySec != majorEverySec;
  }
}
