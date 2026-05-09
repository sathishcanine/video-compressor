import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../../services/video_edit_service.dart';
import 'pro_studio_theme.dart';

String _formatTc(Duration d) {
  final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
  final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  final cs = (d.inMilliseconds.remainder(1000) ~/ 10).toString().padLeft(2, '0');
  return '$m:$s.$cs';
}

/// Bottom sheet: choose keep-range with [RangeSlider], then FFmpeg trim.
class ProTrimPanel extends StatefulWidget {
  const ProTrimPanel({
    super.key,
    required this.scrollController,
    required this.videoController,
    required this.videoPath,
    required this.onApplied,
  });

  final ScrollController scrollController;
  final VideoPlayerController videoController;
  final String videoPath;
  final Future<void> Function(String newPath) onApplied;

  @override
  State<ProTrimPanel> createState() => _ProTrimPanelState();
}

class _ProTrimPanelState extends State<ProTrimPanel> {
  late RangeValues _range;
  bool _busy = false;
  double _progress = 0;

  Duration get _total => widget.videoController.value.duration;

  @override
  void initState() {
    super.initState();
    _range = const RangeValues(0, 1);
  }

  Duration _startDur() {
    final ms = (_range.start * _total.inMilliseconds).round();
    return Duration(milliseconds: ms.clamp(0, _total.inMilliseconds));
  }

  Duration _endDur() {
    final ms = (_range.end * _total.inMilliseconds).round();
    return Duration(milliseconds: ms.clamp(0, _total.inMilliseconds));
  }

  Future<void> _apply() async {
    final start = _startDur();
    final end = _endDur();
    if (end <= start) return;
    if ((end - start).inMilliseconds < 400) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Keep at least 0.4s of video.'), behavior: SnackBarBehavior.floating),
      );
      return;
    }

    setState(() {
      _busy = true;
      _progress = 0;
    });
    try {
      final out = await VideoEditService.trimToNewFile(
        inputPath: widget.videoPath,
        start: start,
        end: end,
        onProgress: (p) {
          if (mounted) setState(() => _progress = p);
        },
      );
      if (!mounted) return;
      await widget.onApplied(out);
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Trim failed: $e'), behavior: SnackBarBehavior.floating),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final total = _total;
    if (total.inMilliseconds <= 0) {
      return const SizedBox.shrink();
    }

    final start = _startDur();
    final end = _endDur();
    final keep = end - start;

    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF1A1A1A),
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: ListView(
        controller: widget.scrollController,
        padding: EdgeInsets.fromLTRB(20, 16, 20, 16 + MediaQuery.paddingOf(context).bottom),
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
            'Trim',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                ),
          ),
          const SizedBox(height: 6),
          Text(
            'Drag handles to choose what to keep. We re-encode this segment for a clean cut.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.white60, height: 1.35),
          ),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Start  ${_formatTc(start)}', style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.w700, fontSize: 13)),
              Text('End  ${_formatTc(end)}', style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.w700, fontSize: 13)),
            ],
          ),
          const SizedBox(height: 8),
          RangeSlider(
            values: _range,
            min: 0,
            max: 1,
            divisions: 200,
            activeColor: ProStudioTheme.pinkTop,
            inactiveColor: Colors.white24,
            labels: RangeLabels(_formatTc(start), _formatTc(end)),
            onChanged: (v) {
              if (v.end - v.start < 0.02) return;
              setState(() => _range = v);
            },
          ),
          Text(
            'Keep ${_formatTc(keep)} of ${_formatTc(total)}',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 12, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _busy
                      ? null
                      : () async {
                          await widget.videoController.pause();
                          await widget.videoController.seekTo(start);
                          setState(() {});
                        },
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: const BorderSide(color: Colors.white24),
                  ),
                  child: const Text('Preview start'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton(
                  onPressed: _busy
                      ? null
                      : () async {
                          await widget.videoController.pause();
                          await widget.videoController.seekTo(end - const Duration(milliseconds: 200));
                          setState(() {});
                        },
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: const BorderSide(color: Colors.white24),
                  ),
                  child: const Text('Preview end'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (_busy) ...[
            LinearProgressIndicator(value: _progress.clamp(0, 1), backgroundColor: Colors.white12, color: ProStudioTheme.pinkTop),
            const SizedBox(height: 8),
            Text('Encoding… ${(_progress * 100).round()}%', textAlign: TextAlign.center, style: const TextStyle(color: Colors.white54, fontSize: 12)),
            const SizedBox(height: 12),
          ],
          FilledButton(
            onPressed: _busy ? null : _apply,
            style: FilledButton.styleFrom(
              backgroundColor: ProStudioTheme.pinkTop,
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
            child: const Text('Apply trim', style: TextStyle(fontWeight: FontWeight.w900)),
          ),
          const SizedBox(height: 10),
          TextButton(
            onPressed: _busy ? null : () => Navigator.pop(context),
            child: const Text('Cancel', style: TextStyle(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }
}

/// Opens the trim panel. [onApplied] receives the new temp file path.
Future<void> showProTrimSheet({
  required BuildContext context,
  required VideoPlayerController videoController,
  required String videoPath,
  required Future<void> Function(String newPath) onApplied,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) {
      return DraggableScrollableSheet(
        initialChildSize: 0.52,
        minChildSize: 0.38,
        maxChildSize: 0.9,
        expand: false,
        builder: (_, scrollController) {
          return ProTrimPanel(
            scrollController: scrollController,
            videoController: videoController,
            videoPath: videoPath,
            onApplied: onApplied,
          );
        },
      );
    },
  );
}
