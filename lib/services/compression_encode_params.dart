import '../models/compression_preset.dart';
import '../models/custom_settings.dart';

/// FFmpeg encode settings for a preset + optional custom tuning.
/// Shared by [VideoCompressionService] and output size estimation.
class CompressionEncodeParams {
  const CompressionEncodeParams({
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

CompressionEncodeParams compressionParamsFor(CompressionPreset preset, CustomCompressionSettings custom) {
  if (preset.isCustom) {
    final crf = (36 - (custom.qualityPercent / 100) * 14).round().clamp(18, 35);
    return switch (custom.resolution) {
      VideoResolutionPreset.p480 => CompressionEncodeParams(
          boxW: 854,
          boxH: 480,
          fps: custom.fpsValue,
          crf: crf,
          x264Preset: 'medium',
          audioBitrateK: 96,
        ),
      VideoResolutionPreset.p720 => CompressionEncodeParams(
          boxW: 720,
          boxH: 1280,
          fps: custom.fpsValue,
          crf: crf,
          x264Preset: 'medium',
          audioBitrateK: 128,
        ),
      VideoResolutionPreset.p1080 => CompressionEncodeParams(
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
    'instagram' => const CompressionEncodeParams(
        boxW: 1080,
        boxH: 1920,
        fps: 30,
        crf: 23,
        x264Preset: 'medium',
        audioBitrateK: 128,
      ),
    'whatsapp' => const CompressionEncodeParams(
        boxW: 720,
        boxH: 1280,
        fps: 30,
        crf: 28,
        x264Preset: 'faster',
        audioBitrateK: 96,
      ),
    'telegram' => const CompressionEncodeParams(
        boxW: 720,
        boxH: 1280,
        fps: 30,
        crf: 26,
        x264Preset: 'fast',
        audioBitrateK: 112,
      ),
    'high_quality' => const CompressionEncodeParams(
        boxW: 1920,
        boxH: 1080,
        fps: 30,
        crf: 18,
        x264Preset: 'slow',
        audioBitrateK: 192,
      ),
    'balanced' => const CompressionEncodeParams(
        boxW: 720,
        boxH: 1280,
        fps: 30,
        crf: 23,
        x264Preset: 'medium',
        audioBitrateK: 128,
      ),
    'max' => const CompressionEncodeParams(
        boxW: 854,
        boxH: 480,
        fps: 30,
        crf: 32,
        x264Preset: 'veryfast',
        audioBitrateK: 64,
      ),
    _ => const CompressionEncodeParams(
        boxW: 720,
        boxH: 1280,
        fps: 30,
        crf: 23,
        x264Preset: 'medium',
        audioBitrateK: 128,
      ),
  };
}
