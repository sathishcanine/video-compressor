import 'package:flutter/material.dart';

import '../../services/video_edit_service.dart';
import 'pro_studio_theme.dart';

class _CropPreset {
  const _CropPreset({required this.id, required this.label, required this.aspectWh});
  final String id;
  final String label;
  /// Target width/height; `null` = use source frame aspect (full frame / no crop).
  final double? aspectWh;
}

const _kPresets = <_CropPreset>[
  _CropPreset(id: 'match', label: 'Match clip', aspectWh: null),
  _CropPreset(id: '1_1', label: '1 : 1', aspectWh: 1),
  _CropPreset(id: '4_5', label: '4 : 5', aspectWh: 4 / 5),
  _CropPreset(id: '3_4', label: '3 : 4', aspectWh: 3 / 4),
  _CropPreset(id: '9_16', label: '9 : 16', aspectWh: 9 / 16),
  _CropPreset(id: '16_9', label: '16 : 9', aspectWh: 16 / 9),
  _CropPreset(id: '21_9', label: '21 : 9', aspectWh: 21 / 9),
  _CropPreset(id: '4_3', label: '4 : 3', aspectWh: 4 / 3),
];

/// Center crop with presets, zoom, and pan (FFmpeg).
class ProCropPanel extends StatefulWidget {
  const ProCropPanel({
    super.key,
    required this.scrollController,
    required this.videoPath,
    required this.fallbackWidth,
    required this.fallbackHeight,
    required this.onApplied,
  });

  final ScrollController scrollController;
  final String videoPath;
  final int fallbackWidth;
  final int fallbackHeight;
  final Future<void> Function(String newPath) onApplied;

  @override
  State<ProCropPanel> createState() => _ProCropPanelState();
}

class _ProCropPanelState extends State<ProCropPanel> {
  _CropPreset _preset = _kPresets.first;
  double _zoom = 1;
  double _panX = 0;
  double _panY = 0;
  bool _busy = false;
  double _progress = 0;
  ({int width, int height})? _probed;
  bool _probeFailed = false;

  @override
  void initState() {
    super.initState();
    VideoEditService.probeVideoStreamDimensions(widget.videoPath).then((d) {
      if (!mounted) return;
      setState(() {
        if (d != null) {
          _probed = d;
          _probeFailed = false;
        } else {
          _probeFailed = widget.fallbackWidth < 2 || widget.fallbackHeight < 2;
          if (!_probeFailed) {
            _probed = (width: widget.fallbackWidth, height: widget.fallbackHeight);
          }
        }
      });
    });
  }

  int get _iw => _probed?.width ?? 0;
  int get _ih => _probed?.height ?? 0;

  double? get _effectiveAspect {
    if (_preset.aspectWh != null) return _preset.aspectWh;
    if (_iw > 0 && _ih > 0) return _iw / _ih;
    return null;
  }

  ({int x, int y, int w, int h})? _computeRect() {
    final a = _effectiveAspect;
    if (a == null || _iw < 2 || _ih < 2) return null;
    try {
      return VideoEditService.computeCenterCropRectangle(
        iw: _iw,
        ih: _ih,
        aspectWidthOverHeight: a,
        zoom: _zoom,
        panX: _panX,
        panY: _panY,
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> _apply() async {
    final rect = _computeRect();
    if (rect == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not compute crop.'), behavior: SnackBarBehavior.floating),
      );
      return;
    }
    if (VideoEditService.isCropNoOp(iw: _iw, ih: _ih, x: rect.x, y: rect.y, w: rect.w, h: rect.h)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Output matches the full frame — pick another ratio or zoom in.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    setState(() {
      _busy = true;
      _progress = 0;
    });
    try {
      final out = await VideoEditService.applyCrop(
        inputPath: widget.videoPath,
        x: rect.x,
        y: rect.y,
        width: rect.w,
        height: rect.h,
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
        SnackBar(content: Text('Crop failed: $e'), behavior: SnackBarBehavior.floating),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final rect = _computeRect();
    final ready = _iw >= 2 && _ih >= 2 && rect != null;
    final pct = (_progress * 100).round().clamp(0, 100);

    return PopScope(
      canPop: !_busy,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && _busy) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Crop in progress — please wait.'), behavior: SnackBarBehavior.floating),
          );
        }
      },
      child: Container(
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
                decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2)),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Crop',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(color: Colors.white, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 6),
            Text(
              'Center crop to a social or film aspect ratio, then zoom and pan before encoding. '
              'Uses pixel dimensions from the file (rotation may differ from preview). Audio is copied when possible. Long clips take time — keep the app open.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.white60, height: 1.35),
            ),
            const SizedBox(height: 14),
            if (_probeFailed)
              Text(
                'Could not read video size. Reload the clip or pick another file.',
                style: TextStyle(color: Colors.red.shade200, fontWeight: FontWeight.w600),
              )
            else if (_probed == null)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Center(child: CircularProgressIndicator(color: ProStudioTheme.pinkTop)),
              )
            else ...[
              Text(
                'Source $_iw × $_ih px',
                style: TextStyle(color: Colors.white.withValues(alpha: 0.65), fontWeight: FontWeight.w700, fontSize: 13),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final p in _kPresets)
                    ChoiceChip(
                      label: Text(p.label, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12)),
                      selected: _preset.id == p.id,
                      onSelected: _busy
                          ? null
                          : (v) {
                              if (v) setState(() => _preset = p);
                            },
                      selectedColor: ProStudioTheme.pinkTop.withValues(alpha: 0.35),
                      backgroundColor: const Color(0xFF2A2A2A),
                      labelStyle: TextStyle(color: _preset.id == p.id ? Colors.white : Colors.white70),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'Zoom ${_zoom.toStringAsFixed(2)}×',
                style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.w800, fontSize: 13),
              ),
              Slider(
                value: _zoom.clamp(1, 3),
                min: 1,
                max: 3,
                divisions: 40,
                activeColor: ProStudioTheme.pinkTop,
                onChanged: !ready || _busy ? null : (v) => setState(() => _zoom = v),
              ),
              Text(
                'Pan ↔ ${_panX.toStringAsFixed(2)}',
                style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.w800, fontSize: 13),
              ),
              Slider(
                value: _panX.clamp(-1, 1),
                min: -1,
                max: 1,
                divisions: 40,
                activeColor: ProStudioTheme.pinkTop,
                onChanged: !ready || _busy ? null : (v) => setState(() => _panX = v),
              ),
              Text(
                'Pan ↕ ${_panY.toStringAsFixed(2)}',
                style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.w800, fontSize: 13),
              ),
              Slider(
                value: _panY.clamp(-1, 1),
                min: -1,
                max: 1,
                divisions: 40,
                activeColor: ProStudioTheme.pinkTop,
                onChanged: !ready || _busy ? null : (v) => setState(() => _panY = v),
              ),
              if (rect != null)
                Container(
                  width: double.infinity,
                  margin: const EdgeInsets.only(top: 8),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF252525),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.white12),
                  ),
                  child: Text(
                    'Output region: ${rect.w} × ${rect.h} at (${rect.x}, ${rect.y})',
                    style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.w600, fontSize: 13),
                  ),
                ),
            ],
            if (_busy) ...[
              const SizedBox(height: 12),
              LinearProgressIndicator(
                value: _progress <= 0.02 ? null : _progress.clamp(0, 1),
                backgroundColor: Colors.white12,
                color: ProStudioTheme.pinkTop,
                minHeight: 8,
              ),
              const SizedBox(height: 6),
              Text(
                _progress >= 0.99 ? 'Finishing…' : (_progress <= 0.02 ? 'Starting…' : 'Encoding crop — $pct%'),
                style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 12),
              ),
            ],
            const SizedBox(height: 16),
            FilledButton(
              onPressed: !ready || _busy ? null : _apply,
              style: FilledButton.styleFrom(
                backgroundColor: ProStudioTheme.pinkTop,
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              child: const Text('Apply crop', style: TextStyle(fontWeight: FontWeight.w900)),
            ),
            TextButton(
              onPressed: _busy ? null : () => Navigator.pop(context),
              child: const Text('Close', style: TextStyle(fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      ),
    );
  }
}

Future<void> showProCropSheet(
  BuildContext context, {
  required String videoPath,
  required int fallbackWidth,
  required int fallbackHeight,
  required Future<void> Function(String newPath) onApplied,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    isDismissible: false,
    enableDrag: false,
    builder: (ctx) {
      return DraggableScrollableSheet(
        initialChildSize: 0.72,
        minChildSize: 0.5,
        maxChildSize: 0.94,
        expand: false,
        builder: (_, sc) => ProCropPanel(
          scrollController: sc,
          videoPath: videoPath,
          fallbackWidth: fallbackWidth,
          fallbackHeight: fallbackHeight,
          onApplied: onApplied,
        ),
      );
    },
  );
}
