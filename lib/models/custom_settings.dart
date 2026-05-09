enum VideoResolutionPreset { p480, p720, p1080 }

enum VideoFpsPreset { fps24, fps30, fps60 }

class CustomCompressionSettings {
  CustomCompressionSettings({
    this.resolution = VideoResolutionPreset.p720,
    this.qualityPercent = 75,
    this.fps = VideoFpsPreset.fps30,
  });

  VideoResolutionPreset resolution;
  double qualityPercent;
  VideoFpsPreset fps;

  CustomCompressionSettings copyWith({
    VideoResolutionPreset? resolution,
    double? qualityPercent,
    VideoFpsPreset? fps,
  }) {
    return CustomCompressionSettings(
      resolution: resolution ?? this.resolution,
      qualityPercent: qualityPercent ?? this.qualityPercent,
      fps: fps ?? this.fps,
    );
  }

  String get resolutionLabel => switch (resolution) {
        VideoResolutionPreset.p480 => '480p',
        VideoResolutionPreset.p720 => '720p',
        VideoResolutionPreset.p1080 => '1080p',
      };

  String get fpsLabel => switch (fps) {
        VideoFpsPreset.fps24 => '24fps',
        VideoFpsPreset.fps30 => '30fps',
        VideoFpsPreset.fps60 => '60fps',
      };

  int get fpsValue => switch (fps) {
        VideoFpsPreset.fps24 => 24,
        VideoFpsPreset.fps30 => 30,
        VideoFpsPreset.fps60 => 60,
      };

  /// Mock estimates for the summary row in the custom sheet.
  int estimatedReductionPercent() {
    final res = switch (resolution) {
      VideoResolutionPreset.p480 => 72,
      VideoResolutionPreset.p720 => 58,
      VideoResolutionPreset.p1080 => 42,
    };
    final q = (100 - qualityPercent).clamp(0, 90).toInt();
    return ((res + q) / 2).clamp(35, 88).round();
  }

  String estimatedBitrateMbps() {
    final base = switch (resolution) {
      VideoResolutionPreset.p480 => 1.2,
      VideoResolutionPreset.p720 => 2.8,
      VideoResolutionPreset.p1080 => 5.5,
    };
    final factor = (qualityPercent / 100).clamp(0.15, 1.0);
    final v = base * factor;
    return '${v.toStringAsFixed(1)} Mbps';
  }

  String qualityCaption() {
    if (qualityPercent >= 85) return 'Excellent — near-original detail';
    if (qualityPercent >= 65) return 'Good quality — balanced for most uses';
    if (qualityPercent >= 40) return 'Smaller files — noticeable compression';
    return 'Heavy compression — smallest size';
  }

  String resolutionCaption() {
    return switch (resolution) {
      VideoResolutionPreset.p480 => 'Lightweight — fastest sharing',
      VideoResolutionPreset.p720 => 'HD — great balance for mobile and web',
      VideoResolutionPreset.p1080 => 'Full HD — best for large screens',
    };
  }

  String fpsCaption() {
    return switch (fps) {
      VideoFpsPreset.fps24 => 'Cinematic — film-like motion',
      VideoFpsPreset.fps30 => 'Standard — ideal for most videos',
      VideoFpsPreset.fps60 => 'Smooth — great for action & games',
    };
  }
}
