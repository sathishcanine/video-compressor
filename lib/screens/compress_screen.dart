import 'dart:io';

import 'package:flutter/material.dart';
import 'package:gal/gal.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:video_player/video_player.dart';

import '../data/history_store.dart';
import '../data/presets.dart';
import '../models/compression_preset.dart';
import '../models/custom_settings.dart';
import '../theme/app_colors.dart';
import '../widgets/brand_header.dart';
import '../widgets/compressing_progress_dialog.dart';
import '../widgets/custom_settings_sheet.dart';
import '../widgets/pick_video_panel.dart';
import '../widgets/preset_option_card.dart';
import '../widgets/video_info_card.dart';
import 'compression_result_screen.dart';

class CompressScreen extends StatefulWidget {
  const CompressScreen({super.key});

  @override
  State<CompressScreen> createState() => _CompressScreenState();
}

class _CompressScreenState extends State<CompressScreen> {
  final ImagePicker _picker = ImagePicker();
  File? _file;
  VideoPlayerController? _controller;
  CompressionPreset? _selected;
  CustomCompressionSettings _custom = CustomCompressionSettings();

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _pickVideo() async {
    final x = await _picker.pickVideo(source: ImageSource.gallery);
    if (x == null) return;
    final file = File(x.path);
    await _swapController(file);
    if (!mounted) return;
    setState(() {
      _file = file;
      _selected = null;
    });
  }

  Future<void> _swapController(File file) async {
    final old = _controller;
    final next = VideoPlayerController.file(file);
    await next.initialize();
    await next.setVolume(0);
    await next.pause();
    old?.dispose();
    _controller = next;
  }

  Future<void> _onPresetTap(CompressionPreset preset) async {
    if (preset.isCustom) {
      final updated = await showCustomSettingsSheet(context, initial: _custom);
      if (!mounted || updated == null) return;
      setState(() {
        _custom = updated;
        _selected = kCompressionPresets.firstWhere((e) => e.id == 'custom');
      });
      return;
    }
    setState(() => _selected = preset);
  }

  int _savingsPercent() {
    if (_selected?.isCustom ?? false) {
      return _custom.estimatedReductionPercent();
    }
    return _selected!.estimatedSavingsPercent;
  }

  String _presetLabelForProgress() {
    if (_selected?.isCustom ?? false) {
      return 'Custom (${_custom.resolutionLabel})';
    }
    return _selected!.name;
  }

  Future<void> _compress() async {
    if (_file == null || _controller == null || _selected == null) return;
    if (!_controller!.value.isInitialized) return;

    final preset = _selected!;
    final originalBytes = _file!.lengthSync();
    final originalMb = originalBytes / (1024 * 1024);
    final pct = _savingsPercent();
    final compressedMb = originalMb * (100 - pct) / 100;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => CompressingProgressDialog(presetLabel: _presetLabelForProgress()),
    );

    if (!mounted) return;

    final isCustom = preset.isCustom;
    final customSubtitle =
        '${_custom.resolutionLabel} • ${_custom.fpsLabel} • ${_custom.qualityPercent.round()}% quality';

    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (context) => CompressionResultScreen(
          preset: preset,
          isCustom: isCustom,
          customSubtitle: customSubtitle,
          videoPath: _file!.path,
          savingsPercent: pct,
          originalMb: originalMb,
          compressedMb: compressedMb,
          onSaveToGallery: () async {
            await Gal.putVideo(_file!.path);
          },
        ),
      ),
    );

    if (!mounted) return;
    CompressionHistory.instance.add(
      CompressionHistoryEntry(
        at: DateTime.now(),
        presetLabel: isCustom ? 'Custom' : preset.name,
        fileName: p.basename(_file!.path),
        savedPercent: pct,
        savedMb: (originalMb - compressedMb).clamp(0, double.infinity),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = _controller;
    final ready = _file != null && _selected != null && c != null && c.value.isInitialized;

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: CustomScrollView(
                slivers: [
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                    sliver: SliverToBoxAdapter(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const BrandHeader(),
                          const SizedBox(height: 22),
                          if (_file == null)
                            PickVideoPanel(onPick: _pickVideo)
                          else ...[
                            if (c != null && c.value.isInitialized)
                              VideoInfoCard(
                                controller: c,
                                file: _file!,
                                onChange: _pickVideo,
                              )
                            else
                              const Padding(
                                padding: EdgeInsets.all(32),
                                child: Center(child: CircularProgressIndicator()),
                              ),
                            const SizedBox(height: 22),
                            Text(
                              'Choose a preset',
                              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w900,
                                  ),
                            ),
                            const SizedBox(height: 12),
                          ],
                        ],
                      ),
                    ),
                  ),
                  if (_file != null)
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 100),
                      sliver: SliverGrid(
                        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          mainAxisSpacing: 12,
                          crossAxisSpacing: 12,
                          childAspectRatio: 0.78,
                        ),
                        delegate: SliverChildBuilderDelegate(
                          (context, index) {
                            final preset = kCompressionPresets[index];
                            final selected = _selected?.id == preset.id;
                            return PresetOptionCard(
                              preset: preset,
                              selected: selected,
                              onTap: () => _onPresetTap(preset),
                            );
                          },
                          childCount: kCompressionPresets.length,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            if (ready)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    ),
                    onPressed: _compress,
                    icon: const Icon(Icons.bolt_rounded, color: Colors.white),
                    label: const Text('Compress Now', style: TextStyle(fontWeight: FontWeight.w900)),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
