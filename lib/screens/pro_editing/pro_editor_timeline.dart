import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

/// Filmstrip + playhead (InShot-style). Seeks [controller] on tap / drag.
class ProEditorTimeline extends StatefulWidget {
  const ProEditorTimeline({
    super.key,
    required this.controller,
    required this.thumbnails,
  });

  final VideoPlayerController controller;
  final List<Uint8List?> thumbnails;

  @override
  State<ProEditorTimeline> createState() => _ProEditorTimelineState();
}

class _ProEditorTimelineState extends State<ProEditorTimeline> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onVideo);
  }

  @override
  void didUpdateWidget(ProEditorTimeline oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onVideo);
      widget.controller.addListener(_onVideo);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onVideo);
    super.dispose();
  }

  void _onVideo() {
    if (mounted) setState(() {});
  }

  double get _progress01 {
    final d = widget.controller.value.duration;
    if (d.inMilliseconds <= 0) return 0;
    final p = widget.controller.value.position.inMilliseconds / d.inMilliseconds;
    return p.clamp(0.0, 1.0);
  }

  Future<void> _seekToFraction(double fx, double width) async {
    final d = widget.controller.value.duration;
    if (width <= 0 || d.inMilliseconds <= 0) return;
    final ms = ((fx / width) * d.inMilliseconds).round().clamp(0, d.inMilliseconds);
    await widget.controller.seekTo(Duration(milliseconds: ms));
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final thumbs = widget.thumbnails.isEmpty ? List<Uint8List?>.filled(6, null) : widget.thumbnails;

    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        const stripH = 54.0;

        return SizedBox(
          height: stripH + 18,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: (e) => _seekToFraction(e.localPosition.dx, w),
            onHorizontalDragUpdate: (e) => _seekToFraction(e.localPosition.dx, w),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned(
                  left: 0,
                  right: 0,
                  top: 10,
                  height: stripH,
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: const Color(0xFFFFD700), width: 1.5),
                    ),
                    clipBehavior: Clip.hardEdge,
                    child: Row(
                      children: [
                        for (var i = 0; i < thumbs.length; i++)
                          Expanded(
                            child: Container(
                              margin: EdgeInsets.only(right: i == thumbs.length - 1 ? 0 : 1),
                              color: const Color(0xFF2C2C2C),
                              child: thumbs[i] != null
                                  ? Image.memory(
                                      thumbs[i]!,
                                      fit: BoxFit.cover,
                                      height: stripH,
                                      gaplessPlayback: true,
                                    )
                                  : const ColoredBox(color: Color(0xFF2C2C2C)),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                Positioned(
                  left: (_progress01 * w).clamp(0.0, w - 2) - 1,
                  top: 4,
                  bottom: 0,
                  child: Column(
                    children: [
                      Container(
                        width: 12,
                        height: 12,
                        decoration: const BoxDecoration(
                          color: Color(0xFFFFD700),
                          shape: BoxShape.circle,
                        ),
                      ),
                      Expanded(
                        child: Container(
                          width: 2,
                          color: Colors.white,
                        ),
                      ),
                    ],
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

/// Tick labels under the filmstrip (e.g. every 2s).
class ProEditorTimeRuler extends StatelessWidget {
  const ProEditorTimeRuler({super.key, required this.duration});

  final Duration duration;

  static String _fmt(int totalSeconds) {
    final m = totalSeconds ~/ 60;
    final s = totalSeconds % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final totalSec = duration.inSeconds;
    if (totalSec <= 0) return const SizedBox.shrink();

    return LayoutBuilder(
      builder: (context, c) {
        final w = c.maxWidth;
        final children = <Widget>[];
        for (var sec = 0; sec <= totalSec; sec += 2) {
          final x = (sec / totalSec) * w;
          children.add(
            Positioned(
              left: x.clamp(0.0, w - 36),
              child: Text(
                _fmt(sec),
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.35),
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          );
        }
        return SizedBox(
          height: 16,
          width: double.infinity,
          child: Stack(children: children),
        );
      },
    );
  }
}
