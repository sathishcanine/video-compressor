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
import '../services/video_compression_service.dart';
import '../theme/app_colors.dart';
import '../widgets/brand_header.dart';
import '../widgets/compressing_progress_dialog.dart';
import '../widgets/custom_settings_sheet.dart';
import '../widgets/estimated_output_card.dart';
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

  int _savingsPercentFromSizes(int originalBytes, int compressedBytes) {
    if (originalBytes <= 0) return 0;
    return (((originalBytes - compressedBytes) / originalBytes) * 100).round().clamp(0, 99);
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

    final outputPath = await showDialog<String?>(
      context: context,
      barrierDismissible: false,
      builder: (_) => CompressingProgressDialog(
        presetLabel: _presetLabelForProgress(),
        job: (setProgress) => VideoCompressionService.compress(
          inputPath: _file!.path,
          preset: preset,
          custom: _custom,
          onProgress: setProgress,
        ),
      ),
    );

    if (!mounted) return;
    if (outputPath == null || outputPath.isEmpty) return;

    final compressedBytes = File(outputPath).lengthSync();
    final compressedMb = compressedBytes / (1024 * 1024);
    final pct = _savingsPercentFromSizes(originalBytes, compressedBytes);

    final isCustom = preset.isCustom;
    final customSubtitle =
        '${_custom.resolutionLabel} • ${_custom.fpsLabel} • ${_custom.qualityPercent.round()}% quality';

    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (context) => CompressionResultScreen(
          preset: preset,
          isCustom: isCustom,
          customSubtitle: customSubtitle,
          originalVideoPath: _file!.path,
          videoPath: outputPath,
          savingsPercent: pct,
          originalMb: originalMb,
          compressedMb: compressedMb,
          onSaveToGallery: () async {
            await Gal.putVideo(outputPath);
          },
        ),
      ),
    );

    await VideoCompressionService.deleteFileIfExists(outputPath);

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
                            if (c != null && c.value.isInitialized) ...[
                              VideoInfoCard(
                                controller: c,
                                file: _file!,
                                onChange: _pickVideo,
                              ),
                              const SizedBox(height: 22),
                              Text(
                                'Choose a preset',
                                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                      fontWeight: FontWeight.w900,
                                    ),
                              ),
                              const SizedBox(height: 12),
                              EstimatedOutputCard(
                                preset: _selected,
                                custom: _custom,
                                duration: c.value.duration,
                                sourceWidth: c.value.size.width.round(),
                                sourceHeight: c.value.size.height.round(),
                                sourceFileBytes: _file!.lengthSync(),
                              ),
                              const SizedBox(height: 16),
                            ] else
                              const Padding(
                                padding: EdgeInsets.all(32),
                                child: Center(child: CircularProgressIndicator()),
                              ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  if (_file != null)
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 100),
                      sliver: SliverToBoxAdapter(
                        child: LayoutBuilder(
                          builder: (context, constraints) {
                            const gap = 12.0;
                            final rawW = constraints.maxWidth;
                            final maxW = rawW.isFinite && rawW > 0
                                ? rawW
                                : MediaQuery.sizeOf(context).width - 40;
                            final cellW = (maxW - gap) / 2;
                            final custom = kCompressionPresets.firstWhere((p) => p.isCustom);
                            final rest = kCompressionPresets.where((p) => !p.isCustom).toList();
                            final rows = <Widget>[];

                            rows.add(
                              Padding(
                                padding: const EdgeInsets.only(bottom: gap),
                                child: PresetOptionCard(
                                  preset: custom,
                                  selected: _selected?.id == custom.id,
                                  onTap: () => _onPresetTap(custom),
                                  horizontal: true,
                                ),
                              ),
                            );

                            for (var i = 0; i < rest.length; i += 2) {
                              final isPair = i + 1 < rest.length;
                              if (isPair) {
                                rows.add(
                                  Padding(
                                    padding: const EdgeInsets.only(bottom: gap),
                                    child: Row(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        SizedBox(
                                          width: cellW,
                                          child: PresetOptionCard(
                                            preset: rest[i],
                                            selected: _selected?.id == rest[i].id,
                                            onTap: () => _onPresetTap(rest[i]),
                                          ),
                                        ),
                                        SizedBox(width: gap),
                                        SizedBox(
                                          width: cellW,
                                          child: PresetOptionCard(
                                            preset: rest[i + 1],
                                            selected: _selected?.id == rest[i + 1].id,
                                            onTap: () => _onPresetTap(rest[i + 1]),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              } else {
                                rows.add(
                                  Padding(
                                    padding: const EdgeInsets.only(bottom: gap),
                                    child: PresetOptionCard(
                                      preset: rest[i],
                                      selected: _selected?.id == rest[i].id,
                                      onTap: () => _onPresetTap(rest[i]),
                                      horizontal: true,
                                    ),
                                  ),
                                );
                              }
                            }

                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: rows,
                            );
                          },
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
