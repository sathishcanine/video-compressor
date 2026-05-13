import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:video_player/video_player.dart';
import 'package:video_thumbnail/video_thumbnail.dart';

import 'pro_canvas_session.dart';

/// InShot-style canvas: ratio, zoom, background, pinch, tilt.
/// Returns settings when the user taps ✓; [null] when they go back without applying.
Future<ProCanvasSessionSettings?> showProCanvasScreen(
  BuildContext context, {
  required VideoPlayerController controller,
  required String videoPath,
  ProCanvasSessionSettings? initialSession,
}) {
  return Navigator.of(context).push<ProCanvasSessionSettings?>(
    PageRouteBuilder<ProCanvasSessionSettings?>(
      opaque: true,
      pageBuilder: (context, animation, secondaryAnimation) => ProCanvasScreen(
        controller: controller,
        videoPath: videoPath,
        initialSession: initialSession,
      ),
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        return FadeTransition(opacity: animation, child: child);
      },
    ),
  );
}

class _RatioDef {
  const _RatioDef({required this.label, required this.iconKind});

  final String label;
  final String? iconKind;
}

const _kRatioDefs = <_RatioDef>[
  _RatioDef(label: 'Fit', iconKind: 'fit_screen'),
  _RatioDef(label: '1:1', iconKind: 'instagram'),
  _RatioDef(label: '4:5', iconKind: 'instagram'),
  _RatioDef(label: '9:16', iconKind: 'reels'),
  _RatioDef(label: '16:9', iconKind: 'youtube'),
  _RatioDef(label: '9:16', iconKind: 'tiktok'),
  _RatioDef(label: '3:4', iconKind: null),
  _RatioDef(label: '4:3', iconKind: null),
  _RatioDef(label: '2:3', iconKind: null),
  _RatioDef(label: '3:2', iconKind: null),
  _RatioDef(label: '2.35:1', iconKind: 'cinema'),
  _RatioDef(label: '2:1', iconKind: null),
  _RatioDef(label: '1:2', iconKind: null),
];

const _kBg = Color(0xFF1A1A1A);
const _kCard = Color(0xFF2A2A2A);
const _kCanvasBlack = Color(0xFF000000);
/// InShot-style ratio chips: tall vertical pills, strong rounding.
const _kRatioCardRadius = 14.0;

enum _CanvasBgKind { solid, blurFrame, gradient, customImage }

class ProCanvasScreen extends StatefulWidget {
  const ProCanvasScreen({
    super.key,
    required this.controller,
    required this.videoPath,
    this.initialSession,
  });

  final VideoPlayerController controller;
  final String videoPath;
  final ProCanvasSessionSettings? initialSession;

  @override
  State<ProCanvasScreen> createState() => _ProCanvasScreenState();
}

class _ProCanvasScreenState extends State<ProCanvasScreen> {
  static const _styleFile = 'vidpress_canvas_style.json';

  final ImagePicker _picker = ImagePicker();

  int _ratioIndex = 0;
  double _zoomSlider = 0.55;
  bool _fillExpandMode = false;

  _CanvasBgKind _bgKind = _CanvasBgKind.solid;
  Color _solidBg = _kCanvasBlack;
  LinearGradient _gradientBg = const LinearGradient(
    colors: [Color(0xFF1a237e), Color(0xFF4a148c)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
  File? _customBgFile;
  Uint8List? _blurThumb;
  bool _rainbowEdge = false;
  double _tiltRadians = 0;

  /// Pixel pan from centered framing (unbounded in UI; softly capped when saving).
  double _panDx = 0;
  double _panDy = 0;

  double _pinchScale = 1;
  double _gestureStartZoom = 1;
  double _gestureStartRotate = 0;
  int _scaleStartPointers = 0;

  /// After the user drags (or picks a ratio), pixel pan [_panDx]/[_panDy] is authoritative.
  /// Until then, reopening with [widget.initialSession] draws pan from session norms × layout.
  bool _hydratedPanFromSession = false;

  /// Last preview layout (for pinch / zoom bounds vs canvas).
  ({double cw, double ch, double bw, double bh, double coverS})? _frameMetrics;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onVideoTick);
    final s = widget.initialSession;
    if (s != null) {
      _ratioIndex = s.ratioIndex.clamp(0, kProCanvasRatioCount - 1);
      _zoomSlider = s.zoomSlider;
      _fillExpandMode = s.fillExpandMode;
      _pinchScale = s.pinchScale;
      _tiltRadians = s.tiltRadians;
    }
    _hydratedPanFromSession = widget.initialSession == null;
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onVideoTick);
    super.dispose();
  }

  void _onVideoTick() {
    if (mounted) setState(() {});
  }

  double get _videoAspect {
    final a = widget.controller.value.aspectRatio;
    if (a <= 0) return 16 / 9;
    return a;
  }

  double get _canvasAspect {
    return kProCanvasRatioAspects[_ratioIndex.clamp(0, kProCanvasRatioCount - 1)] ?? _videoAspect;
  }

  ProCanvasSessionSettings _captureSession() {
    final m = _frameMetrics;
    final cw = (m?.cw ?? 0) > 1e-6 ? m!.cw : 1.0;
    final ch = (m?.ch ?? 0) > 1e-6 ? m!.ch : 1.0;
    final cap = kProCanvasPanNormAbsMax;
    late final double nx;
    late final double ny;
    if (!_hydratedPanFromSession && widget.initialSession != null) {
      final s = widget.initialSession!;
      nx = s.panNormX.clamp(-cap, cap);
      ny = s.panNormY.clamp(-cap, cap);
    } else {
      nx = (_panDx / cw).clamp(-cap, cap);
      ny = (_panDy / ch).clamp(-cap, cap);
    }
    return ProCanvasSessionSettings(
      ratioIndex: _ratioIndex.clamp(0, kProCanvasRatioCount - 1),
      zoomSlider: _zoomSlider,
      fillExpandMode: _fillExpandMode,
      pinchScale: _pinchScale,
      tiltRadians: _tiltRadians,
      panNormX: nx,
      panNormY: ny,
    );
  }

  Offset _panDrawOffset(double cw, double ch) {
    final cap = kProCanvasPanNormAbsMax;
    if (!_hydratedPanFromSession && widget.initialSession != null) {
      final s = widget.initialSession!;
      return Offset(
        s.panNormX.clamp(-cap, cap) * cw,
        s.panNormY.clamp(-cap, cap) * ch,
      );
    }
    return Offset(_panDx, _panDy);
  }

  double _tiltDegreesDisplay() {
    var d = (_tiltRadians * 180 / math.pi) % 360;
    if (d < 0) d += 360;
    return d;
  }

  void _clampPinchToCanvas() {
    final m = _frameMetrics;
    if (m == null) return;
    final t = _zoomSlider.clamp(0.0, 1.0);
    final base = ProCanvasLayout.sliderBaseScale(t, m.coverS, _fillExpandMode);
    if (base <= 1e-9) return;
    final maxTotal = ProCanvasLayout.maxUniformScaleForRotatedRect(m.cw, m.ch, m.bw, m.bh, _tiltRadians);
    final maxPinch = (maxTotal * kProCanvasMaxZoomHeadroom / base).clamp(0.35, 256.0);
    if (_pinchScale > maxPinch) _pinchScale = maxPinch;
  }

  Future<void> _refreshBlurThumb() async {
    try {
      final pos = widget.controller.value.position;
      final b = await VideoThumbnail.thumbnailData(
        video: widget.videoPath,
        timeMs: pos.inMilliseconds.clamp(0, 1 << 30),
        imageFormat: ImageFormat.JPEG,
        quality: 55,
        maxWidth: 720,
      );
      if (mounted) setState(() => _blurThumb = b);
    } catch (_) {
      if (mounted) setState(() => _blurThumb = null);
    }
  }

  Future<void> _pickCustomBackground() async {
    final x = await _picker.pickImage(source: ImageSource.gallery);
    if (x == null) return;
    setState(() {
      _customBgFile = File(x.path);
      _bgKind = _CanvasBgKind.customImage;
    });
  }

  Future<void> _saveCanvasStyle() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final f = File('${dir.path}/$_styleFile');
      final map = <String, dynamic>{
        'ratioIndex': _ratioIndex,
        'zoom': _zoomSlider,
        'fillExpand': _fillExpandMode,
        'bgKind': _bgKind.name,
        'solid': _solidBg.toARGB32(),
        'rainbow': _rainbowEdge,
        'tiltDeg': _tiltDegreesDisplay(),
      };
      await f.writeAsString(const JsonEncoder.withIndent('  ').convert(map));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Saved style to ${f.path}'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Save failed: $e'), behavior: SnackBarBehavior.floating),
      );
    }
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

  void _openBackgroundPicker() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF242424),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      isScrollControlled: true,
      builder: (ctx) {
        final bottom = MediaQuery.paddingOf(ctx).bottom;
        final presets = <Color>[
          _kCanvasBlack,
          const Color(0xFF121212),
          const Color(0xFF263238),
          const Color(0xFF880E4F),
          const Color(0xFF006064),
          const Color(0xFFE65100),
          Colors.white,
        ];
        final gradients = <LinearGradient>[
          const LinearGradient(colors: [Color(0xFF0d47a1), Color(0xFF6a1b9a)]),
          const LinearGradient(
            colors: [Color(0xFF004D40), Color(0xFF33691E)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
          const LinearGradient(
            colors: [Color(0xFF4E342E), Color(0xFF3E2723)],
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
          ),
        ];
        return SafeArea(
          child: Padding(
            padding: EdgeInsets.fromLTRB(20, 12, 20, 20 + bottom),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.white24,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Canvas background',
                    style: Theme.of(ctx).textTheme.titleMedium?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                  const SizedBox(height: 12),
                  Text('Solid', style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      for (final col in presets)
                        GestureDetector(
                          onTap: () {
                            setState(() {
                              _solidBg = col;
                              _bgKind = _CanvasBgKind.solid;
                            });
                            Navigator.pop(ctx);
                          },
                          child: Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              color: col,
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white24),
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  Text('Gradients', style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      for (final g in gradients)
                        GestureDetector(
                          onTap: () {
                            setState(() {
                              _gradientBg = g;
                              _bgKind = _CanvasBgKind.gradient;
                            });
                            Navigator.pop(ctx);
                          },
                          child: Container(
                            width: 72,
                            height: 44,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(8),
                              gradient: g,
                              border: Border.all(color: Colors.white24),
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Blur (video frame)', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                    subtitle: Text(
                      'Uses a still from the current frame behind the clip.',
                      style: TextStyle(color: Colors.white.withValues(alpha: 0.45), fontSize: 12),
                    ),
                    value: _bgKind == _CanvasBgKind.blurFrame,
                    onChanged: (v) async {
                      Navigator.pop(ctx);
                      if (v) {
                        setState(() => _bgKind = _CanvasBgKind.blurFrame);
                        await _refreshBlurThumb();
                      } else {
                        setState(() => _bgKind = _CanvasBgKind.solid);
                      }
                    },
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Rainbow edge bars', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                    subtitle: Text(
                      'Colorful stripes in letterbox areas (InShot-style).',
                      style: TextStyle(color: Colors.white.withValues(alpha: 0.45), fontSize: 12),
                    ),
                    value: _rainbowEdge,
                    onChanged: (v) {
                      setState(() => _rainbowEdge = v);
                    },
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Rotation (°)',
                    style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontWeight: FontWeight.w600),
                  ),
                  SliderTheme(
                    data: SliderTheme.of(ctx).copyWith(
                      activeTrackColor: Colors.white54,
                      inactiveTrackColor: Colors.white12,
                      thumbColor: Colors.white,
                    ),
                    child: Slider(
                      value: math.min(359.99, _tiltDegreesDisplay()),
                      max: 360,
                      label: '${_tiltDegreesDisplay().round()}°',
                      onChanged: (deg) => setState(() {
                        _tiltRadians = deg * math.pi / 180.0;
                        _clampPinchToCanvas();
                      }),
                    ),
                  ),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: () => setState(() {
                        _tiltRadians = 0;
                        _clampPinchToCanvas();
                      }),
                      child: const Text('Reset tilt'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _ratioIcon(String? kind, {required bool selected, double size = 16}) {
    final on = selected ? Colors.black87 : Colors.white;
    switch (kind) {
      case 'fit_screen':
        return Icon(Icons.fit_screen_rounded, size: size, color: on);
      case 'instagram':
        return Icon(FontAwesomeIcons.instagram, size: size * 0.85, color: on);
      case 'youtube':
        return Icon(FontAwesomeIcons.youtube, size: size * 0.85, color: on);
      case 'tiktok':
        return Icon(FontAwesomeIcons.tiktok, size: size * 0.85, color: on);
      case 'reels':
        return Icon(Icons.auto_awesome_rounded, size: size, color: on);
      case 'cinema':
        return Icon(Icons.movie_creation_rounded, size: size, color: on);
      default:
        return SizedBox(width: size, height: size);
    }
  }

  Widget _expandFitToggleIcon() {
    return Transform.rotate(
      angle: math.pi / 4,
      child: Icon(
        Icons.compare_arrows_rounded,
        color: _fillExpandMode ? Colors.white : Colors.white.withValues(alpha: 0.82),
        size: 26,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    final ready = c.value.isInitialized;
    final canvasAr = _canvasAspect;
    final videoAr = _videoAspect;

    return Scaffold(
      backgroundColor: _kBg,
      body: Column(
        children: [
          SizedBox(height: MediaQuery.paddingOf(context).top),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final max = Size(constraints.maxWidth, constraints.maxHeight);
                final box = ProCanvasLayout.canvasBox(max, canvasAr);
                final cw = box.w;
                final ch = box.h;
                final contain = ProCanvasLayout.containVideo(cw, ch, videoAr);
                final coverS = ProCanvasLayout.coverScale(cw, ch, contain.bw, contain.bh);
                _frameMetrics = (cw: cw, ch: ch, bw: contain.bw, bh: contain.bh, coverS: coverS);
                final t = _zoomSlider.clamp(0.0, 1.0);
                final scale = ProCanvasLayout.clampedVideoScale(
                  cw: cw,
                  ch: ch,
                  videoAr: videoAr,
                  tiltRad: _tiltRadians,
                  zoomSlider01: t,
                  fillExpandMode: _fillExpandMode,
                  pinchScale: _pinchScale,
                );
                final maxTotal = ProCanvasLayout.maxUniformScaleForRotatedRect(
                  cw,
                  ch,
                  contain.bw,
                  contain.bh,
                  _tiltRadians,
                );
                final maxZoom = maxTotal * kProCanvasMaxZoomHeadroom;
                final showPinchHint = scale < maxZoom * 0.98 || (!_fillExpandMode && t < 0.92);

                final panOffset = _panDrawOffset(cw, ch);

                return Center(
                  child: ClipRect(
                    clipBehavior: Clip.hardEdge,
                    child: SizedBox(
                      width: cw,
                      height: ch,
                      child: Stack(
                        clipBehavior: Clip.hardEdge,
                        children: [
                        Positioned.fill(child: _buildBackdrop(cw, ch)),
                        if (_rainbowEdge) const Positioned.fill(child: _RainbowLetterboxOverlay()),
                        if (_bgKind == _CanvasBgKind.blurFrame && _blurThumb != null)
                          Positioned.fill(
                            child: ImageFiltered(
                              imageFilter: ImageFilter.blur(sigmaX: 28, sigmaY: 28),
                              child: Image.memory(
                                _blurThumb!,
                                fit: BoxFit.cover,
                                gaplessPlayback: true,
                              ),
                            ),
                          ),
                        Positioned.fill(
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onScaleStart: (d) {
                              _gestureStartZoom = _pinchScale;
                              _gestureStartRotate = _tiltRadians;
                              _scaleStartPointers = d.pointerCount;
                            },
                            onScaleUpdate: (d) {
                              setState(() {
                                final m = _frameMetrics;
                                if (m == null) return;
                                final tt = _zoomSlider.clamp(0.0, 1.0);
                                final base = ProCanvasLayout.sliderBaseScale(tt, m.coverS, _fillExpandMode);
                                if (_scaleStartPointers == 1 && d.pointerCount == 1) {
                                  final cap = kProCanvasPanNormAbsMax;
                                  if (!_hydratedPanFromSession && widget.initialSession != null) {
                                    final s = widget.initialSession!;
                                    _panDx = s.panNormX.clamp(-cap, cap) * m.cw;
                                    _panDy = s.panNormY.clamp(-cap, cap) * m.ch;
                                    _hydratedPanFromSession = true;
                                  }
                                  _panDx = (_panDx + d.focalPointDelta.dx).clamp(-cap * m.cw, cap * m.cw);
                                  _panDy = (_panDy + d.focalPointDelta.dy).clamp(-cap * m.ch, cap * m.ch);
                                  return;
                                }
                                _tiltRadians = _gestureStartRotate + d.rotation;
                                final maxPinch = (ProCanvasLayout.maxUniformScaleForRotatedRect(
                                          m.cw, m.ch, m.bw, m.bh, _tiltRadians) *
                                      kProCanvasMaxZoomHeadroom /
                                      base)
                                    .clamp(0.35, 256.0);
                                _pinchScale = (_gestureStartZoom * d.scale).clamp(0.35, maxPinch);
                              });
                            },
                            onScaleEnd: (_) {
                              setState(() {
                                _clampPinchToCanvas();
                              });
                            },
                            child: Center(
                              child: Transform.translate(
                                offset: panOffset,
                                child: Transform.rotate(
                                  angle: _tiltRadians,
                                  child: Transform.scale(
                                    scale: scale,
                                    alignment: Alignment.center,
                                    child: SizedBox(
                                      width: contain.bw,
                                      height: contain.bh,
                                      child: ClipRRect(
                                        borderRadius: BorderRadius.circular(2),
                                        child: ready
                                            ? FittedBox(
                                                fit: BoxFit.contain,
                                                child: SizedBox(
                                                  width: videoAr * 100,
                                                  height: 100,
                                                  child: VideoPlayer(c),
                                                ),
                                              )
                                            : const ColoredBox(color: Colors.black),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                        Positioned(
                          top: 8,
                          left: 8,
                          child: IconButton(
                            visualDensity: VisualDensity.compact,
                            onPressed: _openBackgroundPicker,
                            icon: Icon(Icons.edit_rounded, color: Colors.white.withValues(alpha: 0.75), size: 22),
                          ),
                        ),
                        if (showPinchHint)
                          Positioned(
                            left: 0,
                            right: 0,
                            bottom: 10,
                            child: Text(
                              'Pinch or slide zoom right · drag anywhere to move the video freely.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.85),
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                      ],
                    ),
                    ),
                  ),
                );
              },
            ),
          ),
          _bottomChrome(),
        ],
      ),
    );
  }

  Widget _buildBackdrop(double cw, double ch) {
    switch (_bgKind) {
      case _CanvasBgKind.solid:
        return ColoredBox(color: _solidBg);
      case _CanvasBgKind.gradient:
        return DecoratedBox(
          decoration: BoxDecoration(gradient: _gradientBg),
        );
      case _CanvasBgKind.customImage:
        if (_customBgFile != null) {
          return Image.file(
            _customBgFile!,
            fit: BoxFit.cover,
            width: cw,
            height: ch,
            errorBuilder: (context, error, stackTrace) => const ColoredBox(color: _kCanvasBlack),
          );
        }
        return const ColoredBox(color: _kCanvasBlack);
      case _CanvasBgKind.blurFrame:
        return ColoredBox(color: Colors.black.withValues(alpha: 0.35));
    }
  }

  Widget _bottomChrome() {
    final c = widget.controller;
    final ready = c.value.isInitialized;
    final playing = ready && c.value.isPlaying;

    return SafeArea(
      top: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(0, 8, 4, 4),
            child: Row(
              children: [
                IconButton(
                  onPressed: () => Navigator.of(context).pop<ProCanvasSessionSettings?>(null),
                  icon: Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white.withValues(alpha: 0.92), size: 18),
                ),
                const Expanded(
                  child: Text(
                    'Canvas',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 17,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: ready ? (playing ? 'Pause' : 'Play') : null,
                  onPressed: ready ? _togglePlay : null,
                  icon: Icon(
                    playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                    color: ready ? Colors.white : Colors.white24,
                    size: 28,
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.of(context).pop<ProCanvasSessionSettings?>(_captureSession()),
                  icon: const Icon(Icons.check_rounded, color: Colors.white, size: 28),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 12, 8),
            child: Row(
              children: [
                IconButton(
                  tooltip: 'Custom background image',
                  onPressed: _pickCustomBackground,
                  icon: const Icon(Icons.upload_rounded, color: Colors.white),
                ),
                IconButton(
                  tooltip: 'Save canvas style',
                  onPressed: _saveCanvasStyle,
                  icon: const Icon(Icons.download_rounded, color: Colors.white),
                ),
                Expanded(
                  child: SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      trackHeight: 3,
                      activeTrackColor: Colors.white38,
                      inactiveTrackColor: Colors.white12,
                      thumbColor: Colors.white,
                      overlayShape: SliderComponentShape.noOverlay,
                    ),
                    child: Slider(
                      value: _zoomSlider.clamp(0.0, 1.0),
                      onChanged: (v) => setState(() {
                        _zoomSlider = v;
                        _clampPinchToCanvas();
                      }),
                    ),
                  ),
                ),
                IconButton(
                  tooltip: _fillExpandMode ? 'Fill mode (expand)' : 'Fit mode',
                  onPressed: () => setState(() {
                    _fillExpandMode = !_fillExpandMode;
                    _clampPinchToCanvas();
                  }),
                  icon: _expandFitToggleIcon(),
                ),
              ],
            ),
          ),
          SizedBox(
            height: ProCanvasLayout.chipMaxH + 14,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
              itemCount: _kRatioDefs.length,
              itemBuilder: (context, i) {
                final d = _kRatioDefs[i];
                final selected = i == _ratioIndex;
                final aspect = kProCanvasRatioAspects[i];
                final sz = ProCanvasLayout.ratioChipOuterSize(aspect, _videoAspect);
                final cellW = math.max(sz.w, 44.0) + 6;
                return Padding(
                  padding: const EdgeInsets.only(right: 10),
                  child: SizedBox(
                    width: cellW,
                    height: ProCanvasLayout.chipMaxH + 8,
                    child: Align(
                      alignment: Alignment.bottomCenter,
                      child: Material(
                        color: selected ? Colors.white : _kCard,
                        borderRadius: BorderRadius.circular(_kRatioCardRadius),
                        clipBehavior: Clip.antiAlias,
                        child: InkWell(
                          onTap: () {
                            setState(() {
                              _ratioIndex = i;
                              _panDx = 0;
                              _panDy = 0;
                              _hydratedPanFromSession = true;
                              _clampPinchToCanvas();
                            });
                          },
                          splashColor: selected ? Colors.black12 : Colors.white12,
                          highlightColor: selected ? Colors.black12 : Colors.white10,
                          child: SizedBox(
                            width: sz.w,
                            height: sz.h,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 5),
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                alignment: Alignment.center,
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    _ratioIcon(d.iconKind, selected: selected, size: 20),
                                    const SizedBox(height: 5),
                                    Text(
                                      d.label,
                                      textAlign: TextAlign.center,
                                      maxLines: 2,
                                      style: TextStyle(
                                        color: selected ? Colors.black87 : Colors.white,
                                        fontWeight: FontWeight.w600,
                                        fontSize: 11,
                                        height: 1.05,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _RainbowLetterboxOverlay extends StatelessWidget {
  const _RainbowLetterboxOverlay();

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _RainbowBarPainter(),
      child: const SizedBox.expand(),
    );
  }
}

class _RainbowBarPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final stripe = 4.0;
    final bandH = size.height * 0.14;
    void drawBand(double top) {
      var x = 0.0;
      var i = 0;
      while (x < size.width) {
        final paint = Paint()
          ..color = HSVColor.fromAHSV(1, (i * 18.0) % 360, 0.85, 1).toColor();
        canvas.drawRect(Rect.fromLTWH(x, top, stripe, bandH), paint);
        x += stripe;
        i++;
      }
    }

    drawBand(0);
    drawBand(size.height - bandH);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
