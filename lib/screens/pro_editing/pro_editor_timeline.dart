import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

/// InShot-style timeline: scrollable filmstrip, fixed center playhead, pinch zoom,
/// white trim box with draggable handles, ruler above strip.
class ProEditorTimeline extends StatefulWidget {
  const ProEditorTimeline({
    super.key,
    required this.controller,
    required this.thumbnails,
    required this.trimStart,
    required this.trimEnd,
    required this.onTrimStartChanged,
    required this.onTrimEndChanged,
  });

  final VideoPlayerController controller;
  final List<Uint8List?> thumbnails;
  final Duration trimStart;
  final Duration trimEnd;
  final ValueChanged<Duration> onTrimStartChanged;
  final ValueChanged<Duration> onTrimEndChanged;

  @override
  State<ProEditorTimeline> createState() => _ProEditorTimelineState();
}

class _ProEditorTimelineState extends State<ProEditorTimeline> {
  static const _stripH = 60.0;
  static const _rulerH = 18.0;
  static const _timeRowH = 36.0;
  static const _playheadExtraTop = 6.0;
  static const _minKeepMs = 400;
  static const _bg = Color(0xFF1A1A1A);

  final ScrollController _scroll = ScrollController();

  /// 1.0 = entire clip fits filmstrip width; >1 zooms in (longer strip).
  double _zoom = 1.0;
  double _pinchBaseZoom = 1.0;
  double _pinchFocalScrollOffset = 0;
  double _pinchFocalFilmstripU = 0;

  bool _programmaticScroll = false;
  bool _draggingTrimHandle = false;
  double _lastViewportW = 0;
  double _lastFilmstripW = 0;
  Timer? _seekDebounce;
  bool _initialScrollDone = false;
  bool _initialScrollScheduled = false;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onVideo);
    _scroll.addListener(_onScrollSeek);
  }

  @override
  void didUpdateWidget(ProEditorTimeline oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onVideo);
      widget.controller.addListener(_onVideo);
      _zoom = 1.0;
      _initialScrollDone = false;
      _initialScrollScheduled = false;
      WidgetsBinding.instance.addPostFrameCallback((_) => _syncScrollToPosition(jump: true));
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onVideo);
    _scroll.removeListener(_onScrollSeek);
    _seekDebounce?.cancel();
    _scroll.dispose();
    super.dispose();
  }

  Duration get _total => widget.controller.value.duration;

  int get _totalMs => _total.inMilliseconds;

  double _filmstripWidth(double viewportW) {
    if (viewportW <= 0 || _totalMs <= 0) return viewportW;
    return math.max(viewportW, viewportW * _zoom);
  }

  /// Time at fixed center playhead (scroll offset = distance into filmstrip from start).
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

  void _onScrollSeek() {
    if (_programmaticScroll) return;
    if (mounted) setState(() {});
    if (_draggingTrimHandle) return;
    final w = _lastFilmstripW;
    if (w <= 0) return;
    _seekDebounce?.cancel();
    _seekDebounce = Timer(const Duration(milliseconds: 45), () {
      if (!mounted || !_scroll.hasClients) return;
      _seekToScrollOffset(_scroll.offset, w);
    });
  }

  void _syncScrollToPosition({bool jump = false}) {
    final w = _lastFilmstripW;
    final v = _lastViewportW;
    if (w <= 0 || v <= 0 || _totalMs <= 0) return;
    final pos = widget.controller.value.position.inMilliseconds.clamp(0, _totalMs);
    final target = (pos / _totalMs) * w;
    if (!_scroll.hasClients) return;
    final clamped = target.clamp(0.0, _scroll.position.maxScrollExtent);
    _programmaticScroll = true;
    if (jump) {
      _scroll.jumpTo(clamped);
    } else {
      if ((clamped - _scroll.offset).abs() > 1.5) {
        _scroll.jumpTo(clamped);
      }
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
    if (!_draggingTrimHandle && widget.controller.value.isPlaying) {
      _syncScrollToPosition();
    }
    if (mounted) setState(() {});
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

  /// Major labels every 2s at default zoom; subdivide when zoomed in.
  static int _rulerMajorStepSec(double filmstripW, double viewportW, int totalMs) {
    if (totalMs <= 0) return 2;
    final secVisible = (totalMs / 1000) * (viewportW / filmstripW);
    if (secVisible <= 8) return 1;
    if (secVisible <= 20) return 2;
    if (secVisible <= 45) return 5;
    return 10;
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
      if (!_scroll.hasClients) return;
      _programmaticScroll = true;
      _scroll.jumpTo(newScroll.clamp(0.0, _scroll.position.maxScrollExtent));
      _programmaticScroll = false;
    });
  }

  Future<void> _onTapStrip(TapUpDetails d, double viewportW, double filmstripW) async {
    if (filmstripW <= 0 || _totalMs <= 0) return;
    if (!_scroll.hasClients) return;
    if (d.localPosition.dy < _rulerH) return;
    final localX = d.localPosition.dx.clamp(0.0, filmstripW);
    final maxS = _scroll.position.maxScrollExtent;
    final targetScroll = localX.clamp(0.0, maxS);
    _programmaticScroll = true;
    _scroll.jumpTo(targetScroll);
    _programmaticScroll = false;
    await _seekToScrollOffset(targetScroll, filmstripW);
  }

  void _dragTrimStart(double deltaDx, double filmstripW) {
    if (filmstripW <= 0 || _totalMs <= 0) return;
    final deltaMs = (deltaDx / filmstripW * _totalMs).round();
    final nextMs = (widget.trimStart.inMilliseconds + deltaMs)
        .clamp(0, widget.trimEnd.inMilliseconds - _minKeepMs);
    widget.onTrimStartChanged(Duration(milliseconds: nextMs));
  }

  void _dragTrimEnd(double deltaDx, double filmstripW) {
    if (filmstripW <= 0 || _totalMs <= 0) return;
    final deltaMs = (deltaDx / filmstripW * _totalMs).round();
    final nextMs = (widget.trimEnd.inMilliseconds + deltaMs)
        .clamp(widget.trimStart.inMilliseconds + _minKeepMs, _totalMs);
    widget.onTrimEndChanged(Duration(milliseconds: nextMs));
  }

  @override
  Widget build(BuildContext context) {
    final thumbs = widget.thumbnails.isEmpty ? List<Uint8List?>.filled(6, null) : widget.thumbnails;

    return LayoutBuilder(
      builder: (context, constraints) {
        final v = constraints.maxWidth;
        final total = _total;
        final totalMs = total.inMilliseconds;
        final w = _filmstripWidth(v);
        _lastViewportW = v;
        _lastFilmstripW = w;

        if (!_initialScrollDone && !_initialScrollScheduled && totalMs > 0) {
          _initialScrollScheduled = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _initialScrollScheduled = false;
            if (!mounted || !_scroll.hasClients) return;
            _initialScrollDone = true;
            _syncScrollToPosition(jump: true);
          });
        }

        if (v <= 0) return const SizedBox.shrink();

        if (totalMs <= 0) {
          return Container(
            color: _bg,
            height: _rulerH + _stripH + _timeRowH + 8,
            alignment: Alignment.center,
            child: Text(
              'No duration',
              style: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 12),
            ),
          );
        }

        final pad = v / 2;
        final contentW = v + w;
        final majorStep = _rulerMajorStepSec(w, v, totalMs);

        final trimDur = widget.trimEnd - widget.trimStart;

        return GestureDetector(
          onScaleStart: (d) {
            if (d.pointerCount < 2) return;
            _pinchBaseZoom = _zoom;
            final localX = d.localFocalPoint.dx;
            final focalScroll = _scroll.hasClients ? _scroll.offset : 0.0;
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
                SizedBox(
                  height: _playheadExtraTop + _rulerH + _stripH,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Positioned.fill(
                        child: AbsorbPointer(
                          absorbing: _draggingTrimHandle,
                          child: NotificationListener<ScrollNotification>(
                            onNotification: (n) {
                              if (n is ScrollEndNotification && !_programmaticScroll) {
                                _seekDebounce?.cancel();
                                _seekToScrollOffset(_scroll.offset, w);
                              }
                              return false;
                            },
                            child: SingleChildScrollView(
                              controller: _scroll,
                              scrollDirection: Axis.horizontal,
                              physics: const BouncingScrollPhysics(
                                parent: AlwaysScrollableScrollPhysics(),
                              ),
                              child: SizedBox(
                                width: contentW,
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    SizedBox(width: pad),
                                    SizedBox(
                                      width: w,
                                      child: GestureDetector(
                                        behavior: HitTestBehavior.translucent,
                                        onTapUp: (d) => _onTapStrip(d, v, w),
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.stretch,
                                          children: [
                                            SizedBox(
                                              height: _rulerH,
                                              child: CustomPaint(
                                                painter: _ScrollingRulerPainter(
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
                                                    _TrimWhiteFrame(
                                                      filmstripWidth: w,
                                                      stripHeight: _stripH,
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
                                    ),
                                    SizedBox(width: pad),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      Positioned.fill(
                        child: IgnorePointer(
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Container(
                                width: 18,
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    begin: Alignment.centerLeft,
                                    end: Alignment.centerRight,
                                    colors: [
                                      _bg,
                                      _bg.withValues(alpha: 0),
                                    ],
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
                                    colors: [
                                      _bg,
                                      _bg.withValues(alpha: 0),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      Positioned(
                        left: v / 2 - 5,
                        top: _playheadExtraTop,
                        width: 10,
                        height: _rulerH + _stripH,
                        child: const _CenterPlayhead(),
                      ),
                      // Overlay trim handles (hit-test above scroll; absorb scroll while dragging)
                      _OverlayTrimHandle(
                        viewportWidth: v,
                        filmstripWidth: w,
                        scrollOffset: _scroll.hasClients ? _scroll.offset : 0,
                        trimTime: widget.trimStart,
                        total: total,
                        stripTop: _playheadExtraTop + _rulerH,
                        stripHeight: _stripH,
                        onDragStart: () => setState(() => _draggingTrimHandle = true),
                        onDragEnd: () => setState(() => _draggingTrimHandle = false),
                        onDrag: (dx) => _dragTrimStart(dx, w),
                      ),
                      _OverlayTrimHandle(
                        viewportWidth: v,
                        filmstripWidth: w,
                        scrollOffset: _scroll.hasClients ? _scroll.offset : 0,
                        trimTime: widget.trimEnd,
                        total: total,
                        stripTop: _playheadExtraTop + _rulerH,
                        stripHeight: _stripH,
                        onDragStart: () => setState(() => _draggingTrimHandle = true),
                        onDragEnd: () => setState(() => _draggingTrimHandle = false),
                        onDrag: (dx) => _dragTrimEnd(dx, w),
                      ),
                    ],
                  ),
                ),
                SizedBox(
                  height: _timeRowH,
                  child: Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Positioned(
                          right: 0,
                          top: 0,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                _formatMmSsTenths(total),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w800,
                                  height: 1.0,
                                  fontFeatures: [FontFeature.tabularFigures()],
                                ),
                              ),
                              Text(
                                'Trim ${_formatMmSsTenths(trimDur)}',
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.45),
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  fontFeatures: const [FontFeature.tabularFigures()],
                                ),
                              ),
                            ],
                          ),
                        ),
                        Positioned(
                          left: (v / 2 - 40).clamp(0.0, v - 80),
                          width: 80,
                          child: Text(
                            _formatMmSsTenths(_timeAtScrollOffset(_scroll.hasClients ? _scroll.offset : 0, w)),
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                              height: 1.0,
                              fontFeatures: [FontFeature.tabularFigures()],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _CenterPlayhead extends StatelessWidget {
  const _CenterPlayhead();

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
          Positioned(left: 0, top: 0, bottom: 0, width: x0, child: ColoredBox(color: Colors.black.withValues(alpha: 0.5))),
        if (x1 < filmstripWidth)
          Positioned(left: x1, top: 0, bottom: 0, right: 0, child: ColoredBox(color: Colors.black.withValues(alpha: 0.5))),
      ],
    );
  }
}

class _TrimWhiteFrame extends StatelessWidget {
  const _TrimWhiteFrame({
    required this.filmstripWidth,
    required this.stripHeight,
    required this.trimStart,
    required this.trimEnd,
    required this.total,
  });

  final double filmstripWidth;
  final double stripHeight;
  final Duration trimStart;
  final Duration trimEnd;
  final Duration total;

  @override
  Widget build(BuildContext context) {
    final tm = total.inMilliseconds;
    if (tm <= 0 || filmstripWidth <= 0) return const SizedBox.shrink();
    final x0 = (trimStart.inMilliseconds / tm) * filmstripWidth;
    final x1 = (trimEnd.inMilliseconds / tm) * filmstripWidth;
    final bw = (x1 - x0).clamp(12.0, filmstripWidth);
    return Positioned(
      left: x0,
      top: 0,
      width: bw,
      height: stripHeight,
      child: IgnorePointer(
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: Colors.white, width: 2),
          ),
        ),
      ),
    );
  }
}

class _ScrollingRulerPainter extends CustomPainter {
  _ScrollingRulerPainter({
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
  bool shouldRepaint(covariant _ScrollingRulerPainter oldDelegate) {
    return oldDelegate.filmstripWidth != filmstripWidth ||
        oldDelegate.duration != duration ||
        oldDelegate.majorEverySec != majorEverySec;
  }
}

class _OverlayTrimHandle extends StatelessWidget {
  const _OverlayTrimHandle({
    required this.viewportWidth,
    required this.filmstripWidth,
    required this.scrollOffset,
    required this.trimTime,
    required this.total,
    required this.stripTop,
    required this.stripHeight,
    required this.onDragStart,
    required this.onDragEnd,
    required this.onDrag,
  });

  final double viewportWidth;
  final double filmstripWidth;
  final double scrollOffset;
  final Duration trimTime;
  final Duration total;
  final double stripTop;
  final double stripHeight;
  final VoidCallback onDragStart;
  final VoidCallback onDragEnd;
  final void Function(double deltaDx) onDrag;

  @override
  Widget build(BuildContext context) {
    final tm = total.inMilliseconds;
    if (tm <= 0 || filmstripWidth <= 0) return const SizedBox.shrink();
    final u = (trimTime.inMilliseconds / tm) * filmstripWidth;
    final screenX = viewportWidth / 2 + u - scrollOffset;
    const hitW = 28.0;
    const barW = 11.0;
    final left = (screenX - hitW / 2).clamp(0.0, viewportWidth - hitW);

    return Positioned(
      left: left,
      top: stripTop,
      width: hitW,
      height: stripHeight,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragStart: (_) => onDragStart(),
        onHorizontalDragEnd: (_) => onDragEnd(),
        onHorizontalDragCancel: onDragEnd,
        onHorizontalDragUpdate: (d) => onDrag(d.delta.dx),
        child: Center(
          child: Container(
            width: barW,
            height: stripHeight * 0.78,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(4),
              boxShadow: [
                BoxShadow(color: Colors.black.withValues(alpha: 0.4), blurRadius: 4, offset: const Offset(0, 1)),
              ],
            ),
            alignment: Alignment.center,
            child: Container(
              width: 2,
              height: stripHeight * 0.28,
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.55),
                borderRadius: BorderRadius.circular(1),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
