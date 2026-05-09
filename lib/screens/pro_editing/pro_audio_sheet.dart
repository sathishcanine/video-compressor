import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../services/video_edit_service.dart';
import 'pro_audio_session.dart';
import 'pro_studio_theme.dart';

/// Mix background music; remembers last track & levels for this clip via [initialSession].
class ProAudioMixPanel extends StatefulWidget {
  const ProAudioMixPanel({
    super.key,
    required this.scrollController,
    required this.videoPath,
    this.initialSession,
    required this.onCommit,
    required this.onForgetSession,
  });

  final ScrollController scrollController;
  final String videoPath;
  final ProAudioMixSession? initialSession;
  final Future<void> Function(String outputPath, ProAudioMixSession session) onCommit;
  final VoidCallback onForgetSession;

  @override
  State<ProAudioMixPanel> createState() => _ProAudioMixPanelState();
}

class _ProAudioMixPanelState extends State<ProAudioMixPanel> {
  String? _musicPath;
  double _clipGain = 1;
  double _musicGain = 0.35;
  bool _busy = false;
  double _progress = 0;
  bool? _clipHasAudio;
  String? _musicMissingHint;
  /// Parent [initialSession] is fixed when the sheet opens; after "Clear saved" we hide remembered UI locally.
  bool _clearedRememberedUi = false;

  bool get _hasRememberedMix =>
      !_clearedRememberedUi &&
      widget.initialSession != null &&
      widget.initialSession!.clipPathAfterMix == widget.videoPath;

  @override
  void initState() {
    super.initState();
    _hydrateFromSession();
    VideoEditService.inputHasAudio(widget.videoPath).then((v) {
      if (mounted) setState(() => _clipHasAudio = v);
    });
  }

  @override
  void didUpdateWidget(covariant ProAudioMixPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialSession != widget.initialSession || oldWidget.videoPath != widget.videoPath) {
      _clearedRememberedUi = false;
      _hydrateFromSession();
    }
  }

  void _hydrateFromSession() {
    final s = widget.initialSession;
    if (s != null && s.clipPathAfterMix == widget.videoPath) {
      final path = s.musicPath;
      final ok = File(path).existsSync();
      setState(() {
        _musicPath = ok ? path : null;
        _clipGain = s.clipLinearGain;
        _musicGain = s.musicLinearGain;
        _musicMissingHint = ok ? null : 'The saved music file is no longer on this device. Pick it again or choose another.';
      });
    } else {
      setState(() {
        _musicPath = null;
        _clipGain = 1;
        _musicGain = 0.35;
        _musicMissingHint = null;
      });
    }
  }

  void _forgetRemembered() {
    setState(() {
      _clearedRememberedUi = true;
      _musicPath = null;
      _clipGain = 1;
      _musicGain = 0.35;
      _musicMissingHint = null;
    });
    widget.onForgetSession();
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
    setState(() {
      _musicPath = path;
      _musicMissingHint = null;
    });
  }

  /// Next mix index for this export (1 = first blend on this file lineage in the editor).
  int _committedMixIndex() {
    final prev = widget.initialSession;
    if (prev == null || prev.clipPathAfterMix != widget.videoPath) return 1;
    return prev.mixIndex + 1;
  }

  Future<void> _apply() async {
    final music = _musicPath;
    if (music == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Pick a music file first.'), behavior: SnackBarBehavior.floating),
      );
      return;
    }
    if (!File(music).existsSync()) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('That file was moved or deleted. Pick another.'), behavior: SnackBarBehavior.floating),
      );
      return;
    }

    setState(() {
      _busy = true;
      _progress = 0;
    });
    try {
      final out = await VideoEditService.mixBackgroundMusic(
        videoPath: widget.videoPath,
        musicPath: music,
        clipLinearGain: _clipGain,
        musicLinearGain: _musicGain,
        onProgress: (p) {
          if (mounted) setState(() => _progress = p);
        },
      );
      if (!mounted) return;
      final session = ProAudioMixSession(
        musicPath: music,
        clipLinearGain: _clipGain,
        musicLinearGain: _musicGain,
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

  @override
  Widget build(BuildContext context) {
    final music = _musicPath;
    final label = music == null ? 'Tap to choose a song or bed' : p.basename(music);
    final pct = (_progress * 100).round().clamp(0, 100);
    final nextPass = _committedMixIndex();

    return PopScope(
      canPop: !_busy,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && _busy) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Mix in progress — wait for it to finish.'),
              behavior: SnackBarBehavior.floating,
            ),
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
              _hasRememberedMix ? 'Audio — continue your mix' : 'Audio — background music',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(color: Colors.white, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 6),
            Text(
              _hasRememberedMix
                  ? 'Your last track and levels are restored. Adjust and apply again, or pick a different file.'
                  : 'Blend a music bed with your clip. Original and music levels are independent. Long clips can take a while — keep the app open.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.white60, height: 1.35),
            ),
            if (_hasRememberedMix) ...[
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF252018),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFFFD700).withValues(alpha: 0.35)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'This clip already includes a music blend. Applying again mixes your current soundtrack with the song below — like another layer. Use Undo ↶ to step back before stacking.',
                      style: TextStyle(
                        color: Colors.amber.shade100,
                        height: 1.35,
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Next apply = mix pass #$nextPass.',
                      style: TextStyle(color: Colors.white.withValues(alpha: 0.75), fontSize: 12, height: 1.3),
                    ),
                  ],
                ),
              ),
            ],
            if (_musicMissingHint != null) ...[
              const SizedBox(height: 12),
              Text(_musicMissingHint!, style: TextStyle(color: Colors.red.shade200, fontWeight: FontWeight.w600, fontSize: 13)),
            ],
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: _busy ? null : _pickMusic,
              icon: const Icon(Icons.audio_file_rounded, color: Colors.white),
              label: Text(
                label,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
              ),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: Colors.white24),
                padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
              ),
            ),
            if (_hasRememberedMix) ...[
              const SizedBox(height: 8),
              TextButton.icon(
                onPressed: _busy ? null : _forgetRemembered,
                icon: Icon(Icons.restart_alt_rounded, color: Colors.white.withValues(alpha: 0.85)),
                label: Text(
                  'Clear saved song & levels',
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontWeight: FontWeight.w700),
                ),
              ),
            ],
            if (_clipHasAudio == false) ...[
              const SizedBox(height: 14),
              Text(
                'This clip has no speech or camera audio — only the music track will be in the export.',
                style: TextStyle(color: Colors.amber.shade200, fontWeight: FontWeight.w600, fontSize: 13, height: 1.3),
              ),
            ],
            const SizedBox(height: 20),
            if (_clipHasAudio != false) ...[
              Text(
                'Original clip ${(_clipGain * 100).round()}%',
                style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.w800, fontSize: 13),
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
            Text(
              'Music ${(_musicGain * 100).round()}%',
              style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.w800, fontSize: 13),
            ),
            Slider(
              value: _musicGain.clamp(0, 4),
              min: 0,
              max: 4,
              divisions: 80,
              activeColor: ProStudioTheme.pinkTop,
              onChanged: _busy ? null : (v) => setState(() => _musicGain = v),
            ),
            if (_busy) ...[
              const SizedBox(height: 10),
              LinearProgressIndicator(
                value: _progress <= 0.02 ? null : _progress.clamp(0, 1),
                backgroundColor: Colors.white12,
                color: ProStudioTheme.pinkTop,
                minHeight: 8,
              ),
              const SizedBox(height: 8),
              Text(
                _progress >= 0.99
                    ? 'Finishing…'
                    : (_progress <= 0.02 ? 'Starting audio encode…' : 'Mixing audio — $pct% (video may be copied first; retry re-encodes picture if needed)'),
                style: TextStyle(color: Colors.white.withValues(alpha: 0.55), fontSize: 12, height: 1.3),
              ),
            ],
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _busy ? null : _apply,
              style: FilledButton.styleFrom(
                backgroundColor: ProStudioTheme.pinkTop,
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              child: Text(
                _hasRememberedMix ? 'Apply mix again' : 'Apply mix',
                style: const TextStyle(fontWeight: FontWeight.w900),
              ),
            ),
            const SizedBox(height: 8),
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

Future<void> showProAudioSheet(
  BuildContext context, {
  required String videoPath,
  required ProAudioMixSession? initialSession,
  required Future<void> Function(String outputPath, ProAudioMixSession session) onCommit,
  required VoidCallback onForgetSession,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    isDismissible: false,
    enableDrag: false,
    builder: (ctx) {
      return DraggableScrollableSheet(
        initialChildSize: 0.62,
        minChildSize: 0.45,
        maxChildSize: 0.94,
        expand: false,
        builder: (_, sc) => ProAudioMixPanel(
          scrollController: sc,
          videoPath: videoPath,
          initialSession: initialSession,
          onCommit: onCommit,
          onForgetSession: onForgetSession,
        ),
      );
    },
  );
}
