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
import 'compression_encode_params.dart';

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

  static String _vf(CompressionEncodeParams t) {
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

    final t = compressionParamsFor(preset, custom);
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
