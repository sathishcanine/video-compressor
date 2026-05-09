import 'package:flutter/material.dart';

import '../../services/video_edit_service.dart';
import 'pro_studio_theme.dart';

/// Speed 0.25×–4× (re-encode).
class ProSpeedPanel extends StatefulWidget {
  const ProSpeedPanel({
    super.key,
    required this.scrollController,
    required this.videoPath,
    required this.onApplied,
  });

  final ScrollController scrollController;
  final String videoPath;
  final Future<void> Function(String newPath) onApplied;

  @override
  State<ProSpeedPanel> createState() => _ProSpeedPanelState();
}

class _ProSpeedPanelState extends State<ProSpeedPanel> {
  double _speed = 1;
  bool _busy = false;
  double _progress = 0;

  Future<void> _apply() async {
    if ((_speed - 1).abs() < 0.02) {
      if (mounted) Navigator.pop(context);
      return;
    }
    setState(() {
      _busy = true;
      _progress = 0;
    });
    try {
      final out = await VideoEditService.applySpeed(
        inputPath: widget.videoPath,
        speed: _speed,
        onProgress: (p) {
          if (mounted) setState(() => _progress = p);
        },
      );
      if (!mounted) return;
      await widget.onApplied(out);
      if (!mounted) return;
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Speed failed: $e'), behavior: SnackBarBehavior.floating),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return _sheetChrome(
      context: context,
      scrollController: widget.scrollController,
      title: 'Speed',
      subtitle: 'Changes video pacing and audio tempo (0.25×–4×).',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '${_speed.toStringAsFixed(2)}×',
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w900),
          ),
          Slider(
            value: _speed.clamp(0.25, 4.0),
            min: 0.25,
            max: 4.0,
            divisions: 75,
            activeColor: ProStudioTheme.pinkTop,
            onChanged: _busy ? null : (v) => setState(() => _speed = v),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              TextButton(onPressed: _busy ? null : () => setState(() => _speed = 0.5), child: const Text('0.5×')),
              TextButton(onPressed: _busy ? null : () => setState(() => _speed = 1), child: const Text('1×')),
              TextButton(onPressed: _busy ? null : () => setState(() => _speed = 2), child: const Text('2×')),
            ],
          ),
          if (_busy) ...[
            const SizedBox(height: 12),
            LinearProgressIndicator(value: _progress.clamp(0, 1), backgroundColor: Colors.white12, color: ProStudioTheme.pinkTop),
          ],
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _busy ? null : _apply,
            style: FilledButton.styleFrom(backgroundColor: ProStudioTheme.pinkTop, padding: const EdgeInsets.symmetric(vertical: 16)),
            child: const Text('Apply', style: TextStyle(fontWeight: FontWeight.w900)),
          ),
        ],
      ),
    );
  }
}

class ProRotateFlipPanel extends StatefulWidget {
  const ProRotateFlipPanel({
    super.key,
    required this.scrollController,
    required this.videoPath,
    required this.onApplied,
  });

  final ScrollController scrollController;
  final String videoPath;
  final Future<void> Function(String newPath) onApplied;

  @override
  State<ProRotateFlipPanel> createState() => _ProRotateFlipPanelState();
}

class _ProRotateFlipPanelState extends State<ProRotateFlipPanel> {
  bool _busy = false;
  double _progress = 0;

  Future<void> _run(Future<String> Function(void Function(double) onProgress) fn) async {
    setState(() {
      _busy = true;
      _progress = 0;
    });
    try {
      final out = await fn((p) {
        if (mounted) setState(() => _progress = p);
      });
      if (!mounted) return;
      await widget.onApplied(out);
      if (!mounted) return;
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$e'), behavior: SnackBarBehavior.floating),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return _sheetChrome(
      context: context,
      scrollController: widget.scrollController,
      title: 'Rotate & flip',
      subtitle: 'Re-encodes video; audio is copied when possible.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _miniBtn('90° CW', () => _run((o) => VideoEditService.applyRotation(inputPath: widget.videoPath, quarterTurns: 1, onProgress: o))),
              _miniBtn('90° CCW', () => _run((o) => VideoEditService.applyRotation(inputPath: widget.videoPath, quarterTurns: -1, onProgress: o))),
              _miniBtn('180°', () => _run((o) => VideoEditService.applyRotation(inputPath: widget.videoPath, quarterTurns: 2, onProgress: o))),
              _miniBtn('Flip H', () => _run((o) => VideoEditService.applyHorizontalFlip(inputPath: widget.videoPath, onProgress: o))),
              _miniBtn('Flip V', () => _run((o) => VideoEditService.applyVerticalFlip(inputPath: widget.videoPath, onProgress: o))),
            ],
          ),
          if (_busy) ...[
            const SizedBox(height: 16),
            LinearProgressIndicator(value: _progress.clamp(0, 1), backgroundColor: Colors.white12, color: ProStudioTheme.pinkTop),
          ],
        ],
      ),
    );
  }

  Widget _miniBtn(String label, VoidCallback onTap) {
    return FilledButton.tonal(
      onPressed: _busy ? null : onTap,
      style: FilledButton.styleFrom(
        foregroundColor: Colors.white,
        backgroundColor: const Color(0xFF2A2A2A),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      ),
      child: Text(label, style: const TextStyle(fontWeight: FontWeight.w800)),
    );
  }
}

class ProVolumePanel extends StatefulWidget {
  const ProVolumePanel({
    super.key,
    required this.scrollController,
    required this.videoPath,
    required this.onApplied,
  });

  final ScrollController scrollController;
  final String videoPath;
  final Future<void> Function(String newPath) onApplied;

  @override
  State<ProVolumePanel> createState() => _ProVolumePanelState();
}

class _ProVolumePanelState extends State<ProVolumePanel> {
  double _gain = 1;
  bool _busy = false;
  double _progress = 0;

  Future<void> _apply() async {
    setState(() {
      _busy = true;
      _progress = 0;
    });
    try {
      final out = await VideoEditService.applyVolume(
        inputPath: widget.videoPath,
        linearGain: _gain,
        onProgress: (p) {
          if (mounted) setState(() => _progress = p);
        },
      );
      if (!mounted) return;
      await widget.onApplied(out);
      if (!mounted) return;
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$e'), behavior: SnackBarBehavior.floating),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return _sheetChrome(
      context: context,
      scrollController: widget.scrollController,
      title: 'Clip volume',
      subtitle: 'Boost or reduce loudness (requires an audio track).',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '${(_gain * 100).round()}%',
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w900),
          ),
          Slider(
            value: _gain.clamp(0, 4),
            min: 0,
            max: 4,
            divisions: 80,
            activeColor: ProStudioTheme.pinkTop,
            onChanged: _busy ? null : (v) => setState(() => _gain = v),
          ),
          if (_busy) LinearProgressIndicator(value: _progress.clamp(0, 1), backgroundColor: Colors.white12, color: ProStudioTheme.pinkTop),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _busy ? null : _apply,
            style: FilledButton.styleFrom(backgroundColor: ProStudioTheme.pinkTop, padding: const EdgeInsets.symmetric(vertical: 16)),
            child: const Text('Apply', style: TextStyle(fontWeight: FontWeight.w900)),
          ),
        ],
      ),
    );
  }
}

class ProSplitPanel extends StatefulWidget {
  const ProSplitPanel({
    super.key,
    required this.scrollController,
    required this.videoPath,
    required this.totalDuration,
    required this.splitPosition,
    required this.onApplied,
  });

  final ScrollController scrollController;
  final String videoPath;
  final Duration totalDuration;
  final Duration splitPosition;
  final Future<void> Function(String newPath) onApplied;

  @override
  State<ProSplitPanel> createState() => _ProSplitPanelState();
}

class _ProSplitPanelState extends State<ProSplitPanel> {
  bool _busy = false;
  double _progress = 0;

  String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  Future<void> _run(Future<String> Function(void Function(double) onProgress) job) async {
    setState(() {
      _busy = true;
      _progress = 0;
    });
    try {
      final out = await job((p) {
        if (mounted) setState(() => _progress = p);
      });
      if (!mounted) return;
      await widget.onApplied(out);
      if (!mounted) return;
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$e'), behavior: SnackBarBehavior.floating),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final pos = widget.splitPosition;
    final total = widget.totalDuration;
    final canSplit = pos > const Duration(milliseconds: 200) && pos < total - const Duration(milliseconds: 200);

    return _sheetChrome(
      context: context,
      scrollController: widget.scrollController,
      title: 'Split at playhead',
      subtitle: 'Keep everything before or after ${_fmt(pos)}.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!canSplit)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                'Move the playhead further from the ends to split.',
                style: TextStyle(color: Colors.amber.shade200, fontWeight: FontWeight.w600),
              ),
            ),
          if (_busy) LinearProgressIndicator(value: _progress.clamp(0, 1), backgroundColor: Colors.white12, color: ProStudioTheme.pinkTop),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: !canSplit || _busy
                ? null
                : () => _run(
                      (o) => VideoEditService.trimToNewFile(
                        inputPath: widget.videoPath,
                        start: Duration.zero,
                        end: pos,
                        onProgress: o,
                      ),
                    ),
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFF333333)),
            child: Text('Keep left (0 → ${_fmt(pos)})', style: const TextStyle(fontWeight: FontWeight.w800)),
          ),
          const SizedBox(height: 8),
          FilledButton(
            onPressed: !canSplit || _busy
                ? null
                : () => _run(
                      (o) => VideoEditService.trimToNewFile(
                        inputPath: widget.videoPath,
                        start: pos,
                        end: total,
                        onProgress: o,
                      ),
                    ),
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFF333333)),
            child: Text('Keep right (${_fmt(pos)} → end)', style: const TextStyle(fontWeight: FontWeight.w800)),
          ),
        ],
      ),
    );
  }
}

class ProReversePanel extends StatefulWidget {
  const ProReversePanel({
    super.key,
    required this.scrollController,
    required this.videoPath,
    required this.onApplied,
  });

  final ScrollController scrollController;
  final String videoPath;
  final Future<void> Function(String newPath) onApplied;

  @override
  State<ProReversePanel> createState() => _ProReversePanelState();
}

class _ProReversePanelState extends State<ProReversePanel> {
  bool _busy = false;
  double _progress = 0;

  Future<void> _apply() async {
    setState(() {
      _busy = true;
      _progress = 0;
    });
    try {
      final out = await VideoEditService.applyReverse(
        inputPath: widget.videoPath,
        onProgress: (p) {
          if (mounted) setState(() => _progress = p);
        },
      );
      if (!mounted) return;
      await widget.onApplied(out);
      if (!mounted) return;
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$e'), behavior: SnackBarBehavior.floating),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return _sheetChrome(
      context: context,
      scrollController: widget.scrollController,
      title: 'Reverse',
      subtitle: 'Plays the whole clip backwards. Can be slow and memory-heavy on long videos.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_busy) LinearProgressIndicator(value: _progress.clamp(0, 1), backgroundColor: Colors.white12, color: ProStudioTheme.pinkTop),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _busy ? null : _apply,
            style: FilledButton.styleFrom(backgroundColor: ProStudioTheme.pinkTop, padding: const EdgeInsets.symmetric(vertical: 16)),
            child: const Text('Reverse entire clip', style: TextStyle(fontWeight: FontWeight.w900)),
          ),
        ],
      ),
    );
  }
}

Widget _sheetChrome({
  required BuildContext context,
  required ScrollController scrollController,
  required String title,
  required String subtitle,
  required Widget child,
}) {
  return Container(
    decoration: const BoxDecoration(
      color: Color(0xFF1A1A1A),
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    child: ListView(
      controller: scrollController,
      padding: EdgeInsets.fromLTRB(20, 16, 20, 16 + MediaQuery.paddingOf(context).bottom),
      children: [
        Center(
          child: Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2)),
          ),
        ),
        const SizedBox(height: 16),
        Text(title, style: Theme.of(context).textTheme.titleLarge?.copyWith(color: Colors.white, fontWeight: FontWeight.w900)),
        const SizedBox(height: 6),
        Text(subtitle, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.white60, height: 1.35)),
        const SizedBox(height: 20),
        child,
        const SizedBox(height: 8),
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel', style: TextStyle(fontWeight: FontWeight.w700))),
      ],
    ),
  );
}

Future<void> showProPhase3Sheet({
  required BuildContext context,
  required Widget Function(ScrollController sc) builder,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) {
      return DraggableScrollableSheet(
        initialChildSize: 0.48,
        minChildSize: 0.32,
        maxChildSize: 0.9,
        expand: false,
        builder: (_, scrollController) => builder(scrollController),
      );
    },
  );
}

void showProSpeedSheet(BuildContext context, String path, Future<void> Function(String) onApplied) {
  showProPhase3Sheet(
    context: context,
    builder: (sc) => ProSpeedPanel(scrollController: sc, videoPath: path, onApplied: onApplied),
  );
}

void showProRotateFlipSheet(BuildContext context, String path, Future<void> Function(String) onApplied) {
  showProPhase3Sheet(
    context: context,
    builder: (sc) => ProRotateFlipPanel(scrollController: sc, videoPath: path, onApplied: onApplied),
  );
}

void showProVolumeSheet(BuildContext context, String path, Future<void> Function(String) onApplied) {
  showProPhase3Sheet(
    context: context,
    builder: (sc) => ProVolumePanel(scrollController: sc, videoPath: path, onApplied: onApplied),
  );
}

void showProSplitSheet(
  BuildContext context, {
  required String path,
  required Duration total,
  required Duration playhead,
  required Future<void> Function(String) onApplied,
}) {
  showProPhase3Sheet(
    context: context,
    builder: (sc) => ProSplitPanel(
      scrollController: sc,
      videoPath: path,
      totalDuration: total,
      splitPosition: playhead,
      onApplied: onApplied,
    ),
  );
}

void showProReverseSheet(BuildContext context, String path, Future<void> Function(String) onApplied) {
  showProPhase3Sheet(
    context: context,
    builder: (sc) => ProReversePanel(scrollController: sc, videoPath: path, onApplied: onApplied),
  );
}
