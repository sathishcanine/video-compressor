import 'dart:async';
import 'dart:io';

import 'package:ffmpeg_kit_flutter_min_gpl/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_min_gpl/ffmpeg_kit_config.dart';
import 'package:ffmpeg_kit_flutter_min_gpl/ffprobe_kit.dart';
import 'package:ffmpeg_kit_flutter_min_gpl/return_code.dart';
import 'package:ffmpeg_kit_flutter_min_gpl/statistics.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/compression_preset.dart';
import '../models/custom_settings.dart';

class _EncodeTarget {
  const _EncodeTarget({
    required this.boxW,
    required this.boxH,
    required this.fps,
    required this.crf,
    required this.x264Preset,
    required this.audioBitrateK,
  });

  final int boxW;
  final int boxH;
  final int fps;
  final int crf;
  final String x264Preset;
  final int audioBitrateK;
}

/// FFmpeg-based compression (libx264 + AAC). Output is always MP4 in a temp file.
final class VideoCompressionService {
  VideoCompressionService._();

  static bool _statsEnabled = false;

  static Future<void> _ensureStatistics() async {
    if (_statsEnabled) return;
    await FFmpegKitConfig.enableStatistics();
    _statsEnabled = true;
  }

  /// Duration in milliseconds (for progress), or null if unknown.
  static Future<double?> probeDurationMs(String inputPath) async {
    try {
      final session = await FFprobeKit.getMediaInformation(inputPath);
      final mi = session.getMediaInformation();
      final d = mi?.getDuration();
      if (d == null) return null;
      final sec = double.tryParse(d);
      if (sec == null || sec <= 0) return null;
      return sec * 1000;
    } catch (_) {
      return null;
    }
  }

  static _EncodeTarget _targetForPreset(CompressionPreset preset, CustomCompressionSettings custom) {
    if (preset.isCustom) {
      final crf = (36 - (custom.qualityPercent / 100) * 14).round().clamp(18, 35);
      return switch (custom.resolution) {
        VideoResolutionPreset.p480 => _EncodeTarget(
            boxW: 854,
            boxH: 480,
            fps: custom.fpsValue,
            crf: crf,
            x264Preset: 'medium',
            audioBitrateK: 96,
          ),
        VideoResolutionPreset.p720 => _EncodeTarget(
            boxW: 720,
            boxH: 1280,
            fps: custom.fpsValue,
            crf: crf,
            x264Preset: 'medium',
            audioBitrateK: 128,
          ),
        VideoResolutionPreset.p1080 => _EncodeTarget(
            boxW: 1080,
            boxH: 1920,
            fps: custom.fpsValue,
            crf: crf,
            x264Preset: 'medium',
            audioBitrateK: 160,
          ),
      };
    }

    return switch (preset.id) {
      'instagram' => const _EncodeTarget(
          boxW: 1080,
          boxH: 1920,
          fps: 30,
          crf: 23,
          x264Preset: 'medium',
          audioBitrateK: 128,
        ),
      'whatsapp' => const _EncodeTarget(
          boxW: 720,
          boxH: 1280,
          fps: 30,
          crf: 28,
          x264Preset: 'faster',
          audioBitrateK: 96,
        ),
      'telegram' => const _EncodeTarget(
          boxW: 720,
          boxH: 1280,
          fps: 30,
          crf: 26,
          x264Preset: 'fast',
          audioBitrateK: 112,
        ),
      'high_quality' => const _EncodeTarget(
          boxW: 1920,
          boxH: 1080,
          fps: 30,
          crf: 18,
          x264Preset: 'slow',
          audioBitrateK: 192,
        ),
      'balanced' => const _EncodeTarget(
          boxW: 720,
          boxH: 1280,
          fps: 30,
          crf: 23,
          x264Preset: 'medium',
          audioBitrateK: 128,
        ),
      'max' => const _EncodeTarget(
          boxW: 854,
          boxH: 480,
          fps: 30,
          crf: 32,
          x264Preset: 'veryfast',
          audioBitrateK: 64,
        ),
      _ => const _EncodeTarget(
          boxW: 720,
          boxH: 1280,
          fps: 30,
          crf: 23,
          x264Preset: 'medium',
          audioBitrateK: 128,
        ),
    };
  }

  static String _vf(_EncodeTarget t) {
    return 'scale=${t.boxW}:${t.boxH}:force_original_aspect_ratio=decrease:force_divisible_by=2';
  }

  /// Runs FFmpeg; [onProgress] receives 0–1 while encoding (best-effort from stats).
  static Future<String> compress({
    required String inputPath,
    required CompressionPreset preset,
    required CustomCompressionSettings custom,
    required void Function(double progress01) onProgress,
  }) async {
    await _ensureStatistics();

    final tempDir = await getTemporaryDirectory();
    final outName = 'vidpress_${DateTime.now().millisecondsSinceEpoch}.mp4';
    final outputPath = p.join(tempDir.path, outName);

    final t = _targetForPreset(preset, custom);
    final vf = _vf(t);

    final args = <String>[
      '-y',
      '-i',
      inputPath,
      '-vf',
      vf,
      '-r',
      '${t.fps}',
      '-c:v',
      'libx264',
      '-preset',
      t.x264Preset,
      '-crf',
      '${t.crf}',
      '-c:a',
      'aac',
      '-b:a',
      '${t.audioBitrateK}k',
      '-movflags',
      '+faststart',
      outputPath,
    ];

    final durationMs = await probeDurationMs(inputPath);
    onProgress(0);

    final completer = Completer<String>();

    await FFmpegKit.executeWithArgumentsAsync(
      args,
      (session) {
        session.getReturnCode().then((rc) async {
          if (completer.isCompleted) return;
          if (ReturnCode.isSuccess(rc)) {
            onProgress(1);
            completer.complete(outputPath);
          } else {
            final logs = await session.getLogsAsString();
            completer.completeError(
              Exception(logs.isNotEmpty ? logs.split('\n').last : 'FFmpeg failed (${rc?.getValue()})'),
            );
          }
        });
      },
      null,
      (Statistics stats) {
        if (durationMs == null || durationMs <= 0) return;
        final posMs = stats.getTime();
        onProgress((posMs / durationMs).clamp(0.0, 0.99));
      },
    );

    return completer.future;
  }

  static Future<void> deleteFileIfExists(String path) async {
    try {
      final f = File(path);
      if (await f.exists()) await f.delete();
    } catch (_) {}
  }
}
