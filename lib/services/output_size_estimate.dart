import 'dart:math' as math;

import 'compression_encode_params.dart';

/// Output dimensions after `scale=W:H:force_original_aspect_ratio=decrease:force_divisible_by=2`.
(int, int) scaledOutputDimensions(int sourceWidth, int sourceHeight, CompressionEncodeParams params) {
  return scaledToFitBox(sourceWidth, sourceHeight, params.boxW, params.boxH);
}

(int, int) scaledToFitBox(int srcW, int srcH, int boxW, int boxH) {
  var w = srcW;
  var h = srcH;
  if (w < 1) w = 1;
  if (h < 1) h = 1;
  final scale = math.min(boxW / w, boxH / h);
  var outW = (w * scale).floor();
  var outH = (h * scale).floor();
  if (outW.isOdd) outW--;
  if (outH.isOdd) outH--;
  outW = outW.clamp(2, boxW);
  outH = outH.clamp(2, boxH);
  return (outW, outH);
}

/// Rough MP4 (H.264 + AAC) size for the UI. Actual size varies with content complexity.
///
/// Returns `null` if [duration] is unknown or non-positive.
int? estimateCompressedVideoBytes({
  required CompressionEncodeParams params,
  required Duration duration,
  required int sourceWidth,
  required int sourceHeight,
  int? sourceFileBytes,
}) {
  final seconds = duration.inMicroseconds / 1e6;
  if (seconds <= 0) return null;

  final dims = scaledOutputDimensions(sourceWidth, sourceHeight, params);
  final outPixels = dims.$1 * dims.$2;
  const refPixels = 1920 * 1080.0;
  final pixelRatio = (outPixels / refPixels).clamp(0.04, 5.0);

  const refKbps = 4800.0;
  final crfMult = math.pow(2.0, (23 - params.crf) / 5.8).toDouble().clamp(0.12, 8.0);
  final fpsMult = math.pow((params.fps / 30.0).clamp(0.4, 2.5), 0.38).toDouble();

  var videoKbps = refKbps * math.pow(pixelRatio, 0.78) * crfMult * fpsMult;
  videoKbps = videoKbps.clamp(180.0, 100_000.0);

  final totalKbps = videoKbps + params.audioBitrateK;
  var bytes = (seconds * totalKbps * 1000 / 8).round();
  bytes = (bytes * 1.06).round();

  final floor = (seconds * params.audioBitrateK * 1000 / 8).round() + 12 * 1024;
  bytes = math.max(bytes, floor);

  if (sourceFileBytes != null && sourceFileBytes > 0 && bytes > sourceFileBytes * 1.25) {
    bytes = (sourceFileBytes * 1.15).round();
  }

  return bytes;
}
