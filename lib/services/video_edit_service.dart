import 'dart:async';
import 'dart:developer' as developer;
import 'dart:io';
import 'dart:math' as math;

import 'package:ffmpeg_kit_flutter_min_gpl/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_min_gpl/ffmpeg_kit_config.dart';
import 'package:ffmpeg_kit_flutter_min_gpl/ffprobe_kit.dart';
import 'package:ffmpeg_kit_flutter_min_gpl/return_code.dart';
import 'package:ffmpeg_kit_flutter_min_gpl/statistics.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'video_compression_service.dart';
import '../screens/pro_editing/pro_canvas_session.dart';

/// FFmpeg helpers for Pro editing (trim, future: filters, etc.).
final class VideoEditService {
  VideoEditService._();

  static bool _statsEnabled = false;

  static Future<void> _ensureStatistics() async {
    if (_statsEnabled) return;
    await FFmpegKitConfig.enableStatistics();
    _statsEnabled = true;
  }

  /// Re-encodes the segment [start, end) to a new MP4 in temp (frame-accurate, reliable).
  static Future<String> trimToNewFile({
    required String inputPath,
    required Duration start,
    required Duration end,
    required void Function(double progress01) onProgress,
  }) async {
    if (end <= start) {
      throw ArgumentError('Trim end must be after start');
    }
    await _ensureStatistics();

    final tempDir = await getTemporaryDirectory();
    final outPath = p.join(tempDir.path, 'vidpress_trim_${DateTime.now().millisecondsSinceEpoch}.mp4');

    final startSec = start.inMilliseconds / 1000.0;
    final durationSec = (end - start).inMilliseconds / 1000.0;
    final trimMs = (end - start).inMilliseconds.toDouble();

    final args = <String>[
      '-y',
      '-ss',
      startSec.toStringAsFixed(3),
      '-i',
      inputPath,
      '-t',
      durationSec.toStringAsFixed(3),
      '-c:v',
      'libx264',
      '-preset',
      'veryfast',
      '-crf',
      '20',
      '-c:a',
      'aac',
      '-b:a',
      '128k',
      '-movflags',
      '+faststart',
      outPath,
    ];

    onProgress(0);
    final completer = Completer<String>();

    await FFmpegKit.executeWithArgumentsAsync(
      args,
      (session) {
        session.getReturnCode().then((rc) async {
          if (completer.isCompleted) return;
          if (ReturnCode.isSuccess(rc)) {
            onProgress(1);
            completer.complete(outPath);
          } else {
            final logs = await session.getLogsAsString();
            completer.completeError(
              Exception(logs.isNotEmpty ? logs.split('\n').last : 'FFmpeg trim failed (${rc?.getValue()})'),
            );
          }
        });
      },
      null,
      (Statistics stats) {
        if (trimMs <= 0) return;
        final posMs = stats.getTime();
        onProgress((posMs / trimMs).clamp(0.0, 0.99));
      },
    );

    return completer.future;
  }

  /// Appends [secondPath] after [firstPath]. If only one clip has audio, the other
  /// gets a silent stereo track for the length of its video (44100 Hz) so concat works.
  static Future<String> concatTwoClips({
    required String firstPath,
    required String secondPath,
    required void Function(double progress01) onProgress,
  }) async {
    final has1 = await inputHasAudio(firstPath);
    final has2 = await inputHasAudio(secondPath);
    final outHasAudio = has1 || has2;

    await _ensureStatistics();
    final d1 = await VideoCompressionService.probeDurationMs(firstPath) ?? 0;
    final d2 = await VideoCompressionService.probeDurationMs(secondPath) ?? 0;
    final totalMs = (d1 + d2).toDouble();

    final t1 = (d1 / 1000.0).clamp(0.001, 864000.0);
    final t2 = (d2 / 1000.0).clamp(0.001, 864000.0);

    final tempDir = await getTemporaryDirectory();
    final outPath = p.join(tempDir.path, 'vidpress_join_${DateTime.now().millisecondsSinceEpoch}.mp4');

    final String filterComplex;
    if (!outHasAudio) {
      filterComplex =
          '[0:v]format=yuv420p[v0];[1:v]format=yuv420p[v1];[v0][v1]concat=n=2:v=1:a=0[outv]';
    } else if (has1 && has2) {
      filterComplex = '[0:v]format=yuv420p[v0];[0:a]aresample=44100,aformat=channel_layouts=stereo[a0];'
          '[1:v]format=yuv420p[v1];[1:a]aresample=44100,aformat=channel_layouts=stereo[a1];'
          '[v0][a0][v1][a1]concat=n=2:v=1:a=1[outv][outa]';
    } else if (has1) {
      filterComplex = '[0:v]format=yuv420p[v0];[0:a]aresample=44100,aformat=channel_layouts=stereo[a0];'
          '[1:v]format=yuv420p[v1];'
          'anullsrc=r=44100:cl=stereo,atrim=end=${t2.toStringAsFixed(3)},asetpts=PTS-STARTPTS[a1];'
          '[v0][a0][v1][a1]concat=n=2:v=1:a=1[outv][outa]';
    } else {
      filterComplex = '[0:v]format=yuv420p[v0];'
          'anullsrc=r=44100:cl=stereo,atrim=end=${t1.toStringAsFixed(3)},asetpts=PTS-STARTPTS[a0];'
          '[1:v]format=yuv420p[v1];[1:a]aresample=44100,aformat=channel_layouts=stereo[a1];'
          '[v0][a0][v1][a1]concat=n=2:v=1:a=1[outv][outa]';
    }

    final args = <String>[
      '-y',
      '-i',
      firstPath,
      '-i',
      secondPath,
      '-filter_complex',
      filterComplex,
      '-map',
      '[outv]',
      if (outHasAudio) ...['-map', '[outa]'],
      '-c:v',
      'libx264',
      '-preset',
      'veryfast',
      '-crf',
      '20',
      if (outHasAudio) ...['-c:a', 'aac', '-b:a', '128k'] else '-an',
      '-movflags',
      '+faststart',
      outPath,
    ];

    onProgress(0);
    final completer = Completer<String>();

    await FFmpegKit.executeWithArgumentsAsync(
      args,
      (session) {
        session.getReturnCode().then((rc) async {
          if (completer.isCompleted) return;
          if (ReturnCode.isSuccess(rc)) {
            onProgress(1);
            completer.complete(outPath);
          } else {
            final logs = await session.getLogsAsString();
            completer.completeError(
              Exception(logs.isNotEmpty ? logs.split('\n').last : 'FFmpeg concat failed (${rc?.getValue()})'),
            );
          }
        });
      },
      null,
      (Statistics stats) {
        if (totalMs <= 0) return;
        final posMs = stats.getTime();
        onProgress((posMs / totalMs).clamp(0.0, 0.99));
      },
    );

    return completer.future;
  }

  static Future<bool> inputHasAudio(String path) async {
    try {
      final session = await FFprobeKit.getMediaInformation(path);
      final mi = session.getMediaInformation();
      if (mi == null) return false;
      for (final s in mi.getStreams()) {
        if (s.getType() == 'audio') return true;
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  /// First video stream width/height in pixels (coded size), or null.
  static Future<({int width, int height})?> probeVideoStreamDimensions(String path) async {
    try {
      final session = await FFprobeKit.getMediaInformation(path);
      final mi = session.getMediaInformation();
      if (mi == null) return null;
      for (final s in mi.getStreams()) {
        if (s.getType() == 'video') {
          final w = s.getWidth();
          final h = s.getHeight();
          if (w != null && h != null && w >= 2 && h >= 2) {
            return (width: w, height: h);
          }
        }
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  /// Center crop to [aspectWidthOverHeight] (e.g. 9/16 → 0.5625). [zoom] ≥ 1 zooms in (smaller window).
  /// [panX]/[panY] in [-1,1] nudge the window before clamping to frame bounds.
  static ({int x, int y, int w, int h}) computeCenterCropRectangle({
    required int iw,
    required int ih,
    required double aspectWidthOverHeight,
    required double zoom,
    double panX = 0,
    double panY = 0,
  }) {
    if (iw < 2 || ih < 2) {
      throw ArgumentError('Invalid frame size');
    }
    final a = aspectWidthOverHeight;
    if (a <= 0 || !a.isFinite) {
      throw ArgumentError('Invalid aspect ratio');
    }
    final z = zoom.clamp(1.0, 3.0);
    final px = panX.clamp(-1.0, 1.0);
    final py = panY.clamp(-1.0, 1.0);

    final srcAr = iw / ih;
    double maxW;
    double maxH;
    double bx;
    double by;
    if (srcAr > a) {
      maxH = ih.toDouble();
      maxW = maxH * a;
      bx = (iw - maxW) / 2;
      by = 0;
    } else {
      maxW = iw.toDouble();
      maxH = maxW / a;
      bx = 0;
      by = (ih - maxH) / 2;
    }

    var cropW = maxW / z;
    var cropH = maxH / z;
    cropH = cropW / a;
    if (cropH > maxH / z + 1e-6) {
      cropH = maxH / z;
      cropW = cropH * a;
    }

    var cx = bx + (maxW - cropW) / 2 + px * 0.22 * iw;
    var cy = by + (maxH - cropH) / 2 + py * 0.22 * ih;

    final maxCx = (iw - cropW).clamp(0.0, double.infinity);
    final maxCy = (ih - cropH).clamp(0.0, double.infinity);
    cx = cx.clamp(0.0, maxCx);
    cy = cy.clamp(0.0, maxCy);

    var xi = (cx / 2).floor() * 2;
    var yi = (cy / 2).floor() * 2;
    var wi = (cropW / 2).floor() * 2;
    var hi = (cropH / 2).floor() * 2;

    if (wi < 2) wi = 2;
    if (hi < 2) hi = 2;
    if (wi > iw) wi = iw & ~1;
    if (hi > ih) hi = ih & ~1;

    if (xi + wi > iw) xi = (((iw - wi) ~/ 2) ~/ 2) * 2;
    if (yi + hi > ih) yi = (((ih - hi) ~/ 2) ~/ 2) * 2;
    xi = (xi.clamp(0, iw - 2).toInt() ~/ 2) * 2;
    yi = (yi.clamp(0, ih - 2).toInt() ~/ 2) * 2;
    if (xi + wi > iw) wi = ((iw - xi) / 2).floor() * 2;
    if (yi + hi > ih) hi = ((ih - yi) / 2).floor() * 2;
    if (wi < 2 || hi < 2) {
      throw StateError('Crop dimensions too small for this zoom/aspect');
    }
    return (x: xi, y: yi, w: wi, h: hi);
  }

  /// True when crop is effectively the full frame (no meaningful change).
  static bool isCropNoOp({
    required int iw,
    required int ih,
    required int x,
    required int y,
    required int w,
    required int h,
  }) {
    return x <= 2 && y <= 2 && w >= iw - 4 && h >= ih - 4;
  }

  /// Pixel-accurate crop; re-encodes H.264, copies AAC when present.
  static Future<String> applyCrop({
    required String inputPath,
    required int x,
    required int y,
    required int width,
    required int height,
    required void Function(double progress01) onProgress,
  }) async {
    if (width < 2 || height < 2 || x < 0 || y < 0) {
      throw ArgumentError('Invalid crop rectangle');
    }
    final dims = await probeVideoStreamDimensions(inputPath);
    if (dims != null) {
      if (x + width > dims.width || y + height > dims.height) {
        throw ArgumentError('Crop extends outside the video frame');
      }
    }
    final durMs = await VideoCompressionService.probeDurationMs(inputPath) ?? 0;
    final hasAudio = await inputHasAudio(inputPath);
    return _encodeToTemp(
      inputPath: inputPath,
      encodeArgs: [
        '-vf',
        'crop=$width:$height:$x:$y',
        '-c:v',
        'libx264',
        '-preset',
        'veryfast',
        '-crf',
        '20',
        if (hasAudio) ...['-c:a', 'copy'] else '-an',
        '-movflags',
        '+faststart',
      ],
      progressDenomMs: durMs,
      onProgress: onProgress,
    );
  }

  static String _audioAtempoChain(double speed) {
    final parts = <String>[];
    var r = speed;
    while (r > 2.0 + 1e-9) {
      parts.add('atempo=2.0');
      r /= 2.0;
    }
    while (r < 0.5 - 1e-9) {
      parts.add('atempo=0.5');
      r /= 0.5;
    }
    parts.add('atempo=${r.toStringAsFixed(5)}');
    return parts.join(',');
  }

  /// Picks a useful line from FFmpeg logs; avoids generic footers like "Conversion failed!".
  static String _ffmpegUserFacingMessage(String logsRaw, Object? returnCode) {
    final logs = logsRaw.trim();
    final fallback = 'FFmpeg failed (code $returnCode)';
    if (logs.isEmpty) return fallback;

    final lines = logs
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();
    if (lines.isEmpty) return fallback;

    bool isGenericFooter(String lower) =>
        lower == 'conversion failed!' ||
        lower.startsWith('press [q] to stop') ||
        lower == 'exiting normally, received signal 2.';

    for (var i = lines.length - 1; i >= 0; i--) {
      final line = lines[i];
      final lower = line.toLowerCase();
      if (isGenericFooter(lower)) continue;
      if (lower.contains('error') ||
          lower.contains('invalid') ||
          lower.contains('failed to') ||
          lower.contains('could not') ||
          lower.contains('unknown encoder') ||
          lower.contains('padded dimensions') ||
          lower.contains('reinitializing filters')) {
        return line.length > 220 ? '${line.substring(0, 217)}…' : line;
      }
    }

    for (var i = lines.length - 1; i >= 0; i--) {
      final lower = lines[i].toLowerCase();
      if (!isGenericFooter(lower)) {
        final line = lines[i];
        return line.length > 220 ? '${line.substring(0, 217)}…' : line;
      }
    }

    return fallback;
  }

  static void _logFfmpegFailure({
    required List<String> args,
    required Object? returnCode,
    required String logs,
    required String message,
  }) {
    void chunk(String header, String body) {
      const max = 3800;
      if (body.length <= max) {
        developer.log('$header$body', name: 'VidPress.FFmpeg');
        return;
      }
      developer.log('$header(len=${body.length})', name: 'VidPress.FFmpeg');
      for (var i = 0; i < body.length; i += max) {
        final end = math.min(i + max, body.length);
        developer.log(body.substring(i, end), name: 'VidPress.FFmpeg');
      }
    }

    developer.log('FAILED rc=$returnCode | $message', name: 'VidPress.FFmpeg');
    chunk('ARGS ', args.join(' '));
    final t = logs.trim();
    chunk('LOGS ', t.isEmpty ? '(empty)' : t);
  }

  static Future<String> _encodeToTemp({
    required String inputPath,
    required List<String> encodeArgs,
    required double progressDenomMs,
    required void Function(double progress01) onProgress,
  }) async {
    await _ensureStatistics();
    final tempDir = await getTemporaryDirectory();
    final outPath = p.join(tempDir.path, 'vidpress_edit_${DateTime.now().millisecondsSinceEpoch}.mp4');
    final args = <String>['-y', '-i', inputPath, ...encodeArgs, outPath];

    onProgress(0);
    final completer = Completer<String>();

    await FFmpegKit.executeWithArgumentsAsync(
      args,
      (session) {
        session.getReturnCode().then((rc) async {
          if (completer.isCompleted) return;
          if (ReturnCode.isSuccess(rc)) {
            onProgress(1);
            completer.complete(outPath);
          } else {
            final logs = await session.getLogsAsString();
            final msg = _ffmpegUserFacingMessage(logs, rc?.getValue());
            _logFfmpegFailure(args: args, returnCode: rc?.getValue(), logs: logs, message: msg);
            completer.completeError(Exception(msg));
          }
        });
      },
      null,
      (Statistics stats) {
        if (progressDenomMs <= 0) return;
        final posMs = stats.getTime();
        onProgress((posMs / progressDenomMs).clamp(0.0, 0.99));
      },
    );

    return completer.future;
  }

  /// [speed] = playback multiplier (2.0 = double speed, 0.5 = half).
  static Future<String> applySpeed({
    required String inputPath,
    required double speed,
    required void Function(double progress01) onProgress,
  }) async {
    if (speed < 0.25 || speed > 4.0) {
      throw ArgumentError('Speed must be between 0.25 and 4');
    }
    final durMs = await VideoCompressionService.probeDurationMs(inputPath) ?? 0;
    final outDurMs = durMs / speed;

    final setpts = (1.0 / speed).toStringAsFixed(6);
    final hasAudio = await inputHasAudio(inputPath);

    final List<String> encodeArgs;
    if (hasAudio) {
      final aChain = _audioAtempoChain(speed);
      encodeArgs = [
        '-filter_complex',
        '[0:v]setpts=$setpts*PTS[v];[0:a]$aChain[a]',
        '-map',
        '[v]',
        '-map',
        '[a]',
        '-c:v',
        'libx264',
        '-preset',
        'veryfast',
        '-crf',
        '20',
        '-c:a',
        'aac',
        '-b:a',
        '128k',
        '-movflags',
        '+faststart',
      ];
    } else {
      encodeArgs = [
        '-vf',
        'setpts=$setpts*PTS',
        '-c:v',
        'libx264',
        '-preset',
        'veryfast',
        '-crf',
        '20',
        '-an',
        '-movflags',
        '+faststart',
      ];
    }

    return _encodeToTemp(
      inputPath: inputPath,
      encodeArgs: encodeArgs,
      progressDenomMs: outDurMs > 0 ? outDurMs : durMs,
      onProgress: onProgress,
    );
  }

  /// [quarterTurns]: 1 = 90° CW, -1 = 90° CCW, 2 = 180°.
  static Future<String> applyRotation({
    required String inputPath,
    required int quarterTurns,
    required void Function(double progress01) onProgress,
  }) async {
    final vf = switch (quarterTurns) {
      1 => 'transpose=1',
      -1 => 'transpose=2',
      2 => 'transpose=1,transpose=1',
      _ => throw ArgumentError('quarterTurns must be 1, -1, or 2'),
    };
    final durMs = await VideoCompressionService.probeDurationMs(inputPath) ?? 0;
    return _encodeToTemp(
      inputPath: inputPath,
      encodeArgs: [
        '-vf',
        vf,
        '-c:v',
        'libx264',
        '-preset',
        'veryfast',
        '-crf',
        '20',
        '-c:a',
        'copy',
        '-movflags',
        '+faststart',
      ],
      progressDenomMs: durMs,
      onProgress: onProgress,
    );
  }

  static Future<String> applyHorizontalFlip({
    required String inputPath,
    required void Function(double progress01) onProgress,
  }) async {
    final durMs = await VideoCompressionService.probeDurationMs(inputPath) ?? 0;
    return _encodeToTemp(
      inputPath: inputPath,
      encodeArgs: [
        '-vf',
        'hflip',
        '-c:v',
        'libx264',
        '-preset',
        'veryfast',
        '-crf',
        '20',
        '-c:a',
        'copy',
        '-movflags',
        '+faststart',
      ],
      progressDenomMs: durMs,
      onProgress: onProgress,
    );
  }

  static Future<String> applyVerticalFlip({
    required String inputPath,
    required void Function(double progress01) onProgress,
  }) async {
    final durMs = await VideoCompressionService.probeDurationMs(inputPath) ?? 0;
    return _encodeToTemp(
      inputPath: inputPath,
      encodeArgs: [
        '-vf',
        'vflip',
        '-c:v',
        'libx264',
        '-preset',
        'veryfast',
        '-crf',
        '20',
        '-c:a',
        'copy',
        '-movflags',
        '+faststart',
      ],
      progressDenomMs: durMs,
      onProgress: onProgress,
    );
  }

  /// Linear gain (1.0 = original, 2.0 = double loudness). Clamped 0–4 for safety.
  static Future<String> applyVolume({
    required String inputPath,
    required double linearGain,
    required void Function(double progress01) onProgress,
  }) async {
    final g = linearGain.clamp(0.0, 4.0);
    final durMs = await VideoCompressionService.probeDurationMs(inputPath) ?? 0;
    final hasAudio = await inputHasAudio(inputPath);
    if (!hasAudio) {
      throw StateError('This clip has no audio track');
    }
    return _encodeToTemp(
      inputPath: inputPath,
      encodeArgs: [
        '-af',
        'volume=${g.toStringAsFixed(3)}',
        '-c:v',
        'copy',
        '-c:a',
        'aac',
        '-b:a',
        '192k',
        '-movflags',
        '+faststart',
      ],
      progressDenomMs: durMs,
      onProgress: onProgress,
    );
  }

  /// Full reverse (CPU-heavy on long clips).
  static Future<String> applyReverse({
    required String inputPath,
    required void Function(double progress01) onProgress,
  }) async {
    final durMs = await VideoCompressionService.probeDurationMs(inputPath) ?? 0;
    final hasAudio = await inputHasAudio(inputPath);
    final encodeArgs = hasAudio
        ? <String>[
            '-filter_complex',
            '[0:v]reverse[v];[0:a]areverse[a]',
            '-map',
            '[v]',
            '-map',
            '[a]',
            '-c:v',
            'libx264',
            '-preset',
            'veryfast',
            '-crf',
            '20',
            '-c:a',
            'aac',
            '-b:a',
            '128k',
            '-movflags',
            '+faststart',
          ]
        : <String>[
            '-vf',
            'reverse',
            '-c:v',
            'libx264',
            '-preset',
            'veryfast',
            '-crf',
            '20',
            '-an',
            '-movflags',
            '+faststart',
          ];

    return _encodeToTemp(
      inputPath: inputPath,
      encodeArgs: encodeArgs,
      progressDenomMs: durMs,
      onProgress: onProgress,
    );
  }

  /// Mixes a background music file under the clip. Audio is re-encoded to AAC.
  /// Tries stream-copy for video first; on failure, retries with H.264 re-encode.
  ///
  /// [clipLinearGain] / [musicLinearGain] are linear multipliers (1.0 = unchanged / nominal).
  /// If the clip has no audio, output is music only (trimmed / padded to video length).
  static Future<String> mixBackgroundMusic({
    required String videoPath,
    required String musicPath,
    required double clipLinearGain,
    required double musicLinearGain,
    required void Function(double progress01) onProgress,
  }) async {
    final vDurMs = await VideoCompressionService.probeDurationMs(videoPath) ?? 0;
    if (vDurMs <= 0) {
      throw StateError('Could not read video duration');
    }
    final mDurMs = await VideoCompressionService.probeDurationMs(musicPath) ?? 0;
    if (mDurMs <= 0) {
      throw StateError('Could not read music duration or file has no audio');
    }
    final hasClipAudio = await inputHasAudio(videoPath);
    if (!await inputHasAudio(musicPath)) {
      throw StateError('The selected file has no audio track');
    }

    await _ensureStatistics();
    final tempDir = await getTemporaryDirectory();
    final outPath = p.join(tempDir.path, 'vidpress_audio_mix_${DateTime.now().millisecondsSinceEpoch}.mp4');

    final vSec = (vDurMs / 1000.0).clamp(0.01, 864000.0);
    final musicLenSec = (mDurMs / 1000.0).clamp(0.001, 864000.0);
    final trimMusicSec = musicLenSec < vSec ? musicLenSec : vSec;
    final vSecStr = vSec.toStringAsFixed(3);
    final trimMusicStr = trimMusicSec.toStringAsFixed(3);
    final cg = clipLinearGain.clamp(0.0, 4.0);
    final mg = musicLinearGain.clamp(0.0, 4.0);

    final String filterComplex;
    if (hasClipAudio) {
      filterComplex = '[0:a]aformat=channel_layouts=stereo,aresample=48000,asetpts=PTS-STARTPTS[va];'
          '[1:a]aformat=channel_layouts=stereo,aresample=48000,atrim=end=$trimMusicStr,asetpts=PTS-STARTPTS,apad=whole_dur=$vSecStr[ma];'
          '[va]volume=${cg.toStringAsFixed(3)}[vag];'
          '[ma]volume=${mg.toStringAsFixed(3)}[mag];'
          '[vag][mag]amix=inputs=2:duration=first:normalize=0[outa]';
    } else {
      filterComplex = '[1:a]aformat=channel_layouts=stereo,aresample=48000,atrim=end=$trimMusicStr,asetpts=PTS-STARTPTS,apad=whole_dur=$vSecStr[ma];'
          '[ma]volume=${mg.toStringAsFixed(3)}[outa]';
    }

    onProgress(0);
    try {
      return await _runAudioMixJob(
        videoPath: videoPath,
        musicPath: musicPath,
        filterComplex: filterComplex,
        outPath: outPath,
        progressDenomMs: vDurMs.toDouble(),
        onProgress: onProgress,
        copyVideo: true,
      );
    } catch (_) {
      await deleteFileIfExists(outPath);
      onProgress(0);
      return await _runAudioMixJob(
        videoPath: videoPath,
        musicPath: musicPath,
        filterComplex: filterComplex,
        outPath: outPath,
        progressDenomMs: vDurMs.toDouble(),
        onProgress: onProgress,
        copyVideo: false,
      );
    }
  }

  static Future<String> _runAudioMixJob({
    required String videoPath,
    required String musicPath,
    required String filterComplex,
    required String outPath,
    required double progressDenomMs,
    required void Function(double progress01) onProgress,
    required bool copyVideo,
  }) async {
    final videoCodec = copyVideo
        ? <String>['-c:v', 'copy']
        : <String>[
            '-c:v',
            'libx264',
            '-preset',
            'veryfast',
            '-crf',
            '20',
          ];

    final args = <String>[
      '-y',
      '-i',
      videoPath,
      '-i',
      musicPath,
      '-filter_complex',
      filterComplex,
      '-map',
      '0:v',
      '-map',
      '[outa]',
      ...videoCodec,
      '-c:a',
      'aac',
      '-b:a',
      '192k',
      '-movflags',
      '+faststart',
      outPath,
    ];

    final completer = Completer<String>();

    await FFmpegKit.executeWithArgumentsAsync(
      args,
      (session) {
        session.getReturnCode().then((rc) async {
          if (completer.isCompleted) return;
          if (ReturnCode.isSuccess(rc)) {
            onProgress(1);
            completer.complete(outPath);
          } else {
            final logs = await session.getLogsAsString();
            completer.completeError(
              Exception(logs.isNotEmpty ? logs.split('\n').last : 'Audio mix failed (${rc?.getValue()})'),
            );
          }
        });
      },
      null,
      (Statistics stats) {
        if (progressDenomMs <= 0) return;
        final posMs = stats.getTime();
        onProgress((posMs / progressDenomMs).clamp(0.0, 0.99));
      },
    );

    return completer.future;
  }

  static int _evenDimension(int x) {
    if (x < 2) return 2;
    return (x ~/ 2) * 2;
  }

  /// Encodes a new MP4 with canvas framing (aspect, zoom, fill, rotation) matching [ProCanvasLayout].
  ///
  /// Copies [inputPath] to a temp file first so FFmpeg does not read the same path the
  /// [VideoPlayer] may have open (avoids intermittent failures on repeat export).
  static Future<String> applyCanvasComposition({
    required String inputPath,
    required ProCanvasSessionSettings session,
    required double videoAspect,
    required void Function(double progress01) onProgress,
  }) async {
    final tempDir = await getTemporaryDirectory();
    final ext = p.extension(inputPath);
    final safeExt = ext.isNotEmpty ? ext : '.mp4';
    final srcCopy = p.join(
      tempDir.path,
      'vidpress_canvas_src_${DateTime.now().millisecondsSinceEpoch}$safeExt',
    );
    try {
      await File(inputPath).copy(srcCopy);
      final dims = await probeVideoStreamDimensions(srcCopy);
      final iw = dims?.width ?? 0;
      final ih = dims?.height ?? 0;
      // Match [ProCanvasEditorPreview] / canvas UI: use display aspect from the player.
      // Coded probe w/h often differs when rotation metadata is applied only in the player,
      // which breaks scale/pad vs decoded frames for fixed ratios like 9:16.
      final layoutAr = (videoAspect > 0 && videoAspect.isFinite)
          ? videoAspect
          : ((iw >= 2 && ih >= 2) ? iw / ih : 16 / 9);
      final canvasAr = session.resolvedCanvasAspect(layoutAr);

      const maxLong = 1920;
      late final int outW;
      late final int outH;
      if (canvasAr >= 1.0) {
        outW = _evenDimension(maxLong);
        outH = _evenDimension((maxLong / canvasAr).round());
      } else {
        outH = _evenDimension(maxLong);
        outW = _evenDimension((maxLong * canvasAr).round());
      }

      final cw = outW.toDouble();
      final ch = outH.toDouble();
      final contain = ProCanvasLayout.containVideo(cw, ch, layoutAr);
      final scaleF = ProCanvasLayout.clampedVideoScale(
        cw: cw,
        ch: ch,
        videoAr: layoutAr,
        tiltRad: session.tiltRadians,
        zoomSlider01: session.zoomSlider,
        fillExpandMode: session.fillExpandMode,
        pinchScale: session.pinchScale,
      );
      final fit = ProCanvasLayout.fittedVideoInContain(contain.bw, contain.bh, layoutAr);
      var sw = _evenDimension((fit.rw * scaleF).round());
      var sh = _evenDimension((fit.rh * scaleF).round());
      sw = math.max(2, sw);
      sh = math.max(2, sh);

      final tilt = session.tiltRadians;
      final bb = ProCanvasLayout.rotatedAabb(sw.toDouble(), sh.toDouble(), tilt);
      final bbw = math.max(1, bb.w.ceil());
      final bbh = math.max(1, bb.h.ceil());
      final nxp = session.panNormX.clamp(-kProCanvasPanNormAbsMax, kProCanvasPanNormAbsMax);
      final nyp = session.panNormY.clamp(-kProCanvasPanNormAbsMax, kProCanvasPanNormAbsMax);
      final panPx = nxp * outW;
      final panPy = nyp * outH;

      final vfParts = <String>[
        'format=yuv420p',
        'scale=$sw:$sh:flags=lanczos',
      ];
      if (tilt.abs() > 1e-5) {
        vfParts.add('rotate=${tilt.toStringAsFixed(6)}:fillcolor=black');
      }

      if (bbw > outW && bbh > outH) {
        final oxRaw = (((bbw - outW) * 0.5) - panPx).round().clamp(0, bbw - outW);
        final oyRaw = (((bbh - outH) * 0.5) - panPy).round().clamp(0, bbh - outH);
        final ox = (oxRaw ~/ 2) * 2;
        final oy = (oyRaw ~/ 2) * 2;
        vfParts.add('crop=$outW:$outH:$ox:$oy');
      } else if (bbw > outW && bbh <= outH) {
        final bbhE = _evenDimension(bbh);
        final oxRaw = (((bbw - outW) * 0.5) - panPx).round().clamp(0, bbw - outW);
        final ox = (oxRaw ~/ 2) * 2;
        vfParts.add('crop=$outW:$bbhE:$ox:0');
        vfParts.add('pad=$outW:$outH:0:(oh-ih)/2:black');
      } else if (bbh > outH && bbw <= outW) {
        final bbwE = _evenDimension(bbw);
        final oyRaw = (((bbh - outH) * 0.5) - panPy).round().clamp(0, bbh - outH);
        final oy = (oyRaw ~/ 2) * 2;
        vfParts.add('crop=$bbwE:$outH:0:$oy');
        vfParts.add('pad=$outW:$outH:(ow-iw)/2:0:black');
      } else {
        final rangeX = math.max(0, outW - bbw);
        final rangeY = math.max(0, outH - bbh);
        final pxRaw = (((rangeX * 0.5) + panPx).round()).clamp(0, rangeX);
        final pyRaw = (((rangeY * 0.5) + panPy).round()).clamp(0, rangeY);
        final px = (pxRaw ~/ 2) * 2;
        final py = (pyRaw ~/ 2) * 2;
        vfParts.add('pad=$outW:$outH:$px:$py:black');
      }
      final vf = vfParts.join(',');

      final durMs = await VideoCompressionService.probeDurationMs(srcCopy) ?? 0;
      final hasAudio = await inputHasAudio(srcCopy);

      return await _encodeToTemp(
        inputPath: srcCopy,
        encodeArgs: [
          '-vf',
          vf,
          '-c:v',
          'libx264',
          '-preset',
          'veryfast',
          '-crf',
          '20',
          if (hasAudio) ...['-c:a', 'aac', '-b:a', '128k'] else '-an',
          '-movflags',
          '+faststart',
        ],
        progressDenomMs: durMs,
        onProgress: onProgress,
      );
    } finally {
      await deleteFileIfExists(srcCopy);
    }
  }

  /// Copies file into a new temp path (for Duplicate).
  static Future<String> duplicateToTemp(String inputPath) async {
    final tempDir = await getTemporaryDirectory();
    final outPath = p.join(tempDir.path, 'vidpress_dup_${DateTime.now().millisecondsSinceEpoch}.mp4');
    await File(inputPath).copy(outPath);
    return outPath;
  }

  static Future<void> deleteFileIfExists(String path) async {
    try {
      final f = File(path);
      if (await f.exists()) await f.delete();
    } catch (_) {}
  }
}
