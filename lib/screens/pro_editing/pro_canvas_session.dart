import 'dart:math' as math;
import 'dart:ui' show Size, lerpDouble;

import 'package:video_player/video_player.dart';

/// Width/height for each ratio chip index (same order as canvas UI).
/// `null` = Fit → use [videoAspect] when resolving.
const List<double?> kProCanvasRatioAspects = <double?>[
  null,
  1.0,
  4 / 5,
  9 / 16,
  16 / 9,
  9 / 16,
  3 / 4,
  4 / 3,
  2 / 3,
  3 / 2,
  2.35,
  2.0,
  1 / 2,
];

int get kProCanvasRatioCount => kProCanvasRatioAspects.length;

/// Max zoom relative to the scale where the full (tilted) frame still fits in the canvas.
const double kProCanvasMaxZoomHeadroom = 6.0;

/// Soft cap for stored pan as a multiple of canvas width/height (dimensionless).
const double kProCanvasPanNormAbsMax = 5000.0;

/// Applied framing when the user confirms Canvas (✓).
class ProCanvasSessionSettings {
  const ProCanvasSessionSettings({
    required this.ratioIndex,
    required this.zoomSlider,
    required this.fillExpandMode,
    required this.pinchScale,
    required this.tiltRadians,
    double? panNormX,
    double? panNormY,
  })  : _panNormX = panNormX,
        _panNormY = panNormY;

  final int ratioIndex;
  final double zoomSlider;
  final bool fillExpandMode;
  final double pinchScale;
  final double tiltRadians;

  final double? _panNormX;
  final double? _panNormY;

  /// Pan as a fraction of the canvas box width/height ([ProCanvasLayout.canvasBox] `w`/`h`).
  /// Stored normalized so the same framing appears on the full Canvas screen and the
  /// smaller editor preview, and matches export (output canvas size).
  ///
  /// Backing fields are nullable so hot reload / stale instances never throw; invalid
  /// values are treated as centered (0).
  double get panNormX {
    final x = _panNormX;
    if (x == null || !x.isFinite) return 0;
    return x;
  }

  double get panNormY {
    final y = _panNormY;
    if (y == null || !y.isFinite) return 0;
    return y;
  }

  int get _safeIndex => ratioIndex.clamp(0, kProCanvasRatioCount - 1);

  double resolvedCanvasAspect(double videoAspect) {
    return kProCanvasRatioAspects[_safeIndex] ?? videoAspect;
  }
}

/// Shared layout math: canvas screen + main editor preview.
abstract final class ProCanvasLayout {
  static double videoAspect(VideoPlayerController c) {
    final a = c.value.aspectRatio;
    if (a <= 0) return 16 / 9;
    return a;
  }

  /// Largest axis-aligned box of [canvasAspect] that fits in [max].
  static ({double w, double h}) canvasBox(Size max, double canvasAspect) {
    final rw = canvasAspect;
    if (max.width / max.height >= rw) {
      final h = max.height;
      return (w: h * rw, h: h);
    }
    final w = max.width;
    return (w: w, h: w / rw);
  }

  static ({double bw, double bh}) containVideo(double cw, double ch, double videoAr) {
    if (videoAr >= cw / ch) {
      final bw = cw;
      final bh = cw / videoAr;
      return (bw: bw, bh: bh);
    }
    final bh = ch;
    final bw = ch * videoAr;
    return (bw: bw, bh: bh);
  }

  static double coverScale(double cw, double ch, double bw, double bh) {
    return math.max(cw / bw, ch / bh);
  }

  static double sliderBaseScale(double t, double coverS, bool fillExpandMode) {
    if (fillExpandMode) {
      return lerpDouble(1.0, coverS, t) ?? 1.0;
    }
    final tt = t.clamp(0.0, 1.0);
    // Same 0.42→1 “fit” curve up to ~0.62 (default ~0.55 unchanged). Past that, ramp toward
    // [kProCanvasMaxZoomHeadroom] so users can zoom (and pan) with the slider alone, not only pinch.
    const u0 = 0.62;
    final fitBase = lerpDouble(0.42, 1.0, tt) ?? 1.0;
    final u = tt <= u0 ? 0.0 : ((tt - u0) / (1.0 - u0)).clamp(0.0, 1.0);
    final head = lerpDouble(1.0, kProCanvasMaxZoomHeadroom, u) ?? 1.0;
    return fitBase * head;
  }

  static double maxUniformScaleForRotatedRect(
    double cw,
    double ch,
    double bw,
    double bh,
    double thetaRad,
  ) {
    final ca = math.cos(thetaRad).abs();
    final sa = math.sin(thetaRad).abs();
    final dw = bw * ca + bh * sa;
    final dh = bw * sa + bh * ca;
    if (dw <= 1e-6 || dh <= 1e-6) return 1.0;
    return math.min(cw / dw, ch / dh) * 0.998;
  }

  /// Axis-aligned bounding box of a [rw]×[rh] rectangle rotated by [thetaRad].
  static ({double w, double h}) rotatedAabb(double rw, double rh, double thetaRad) {
    final ca = math.cos(thetaRad).abs();
    final sa = math.sin(thetaRad).abs();
    return (w: rw * ca + rh * sa, h: rw * sa + rh * ca);
  }

  /// Letterboxed size of video inside contain box (before uniform [scale]).
  static ({double rw, double rh}) fittedVideoInContain(double bw, double bh, double videoAr) {
    if (videoAr >= bw / bh) {
      return (rw: bw, rh: bw / videoAr);
    }
    return (rw: bh * videoAr, rh: bh);
  }

  /// Final uniform scale for the video rect (slider × pinch, capped to canvas).
  static double clampedVideoScale({
    required double cw,
    required double ch,
    required double videoAr,
    required double tiltRad,
    required double zoomSlider01,
    required bool fillExpandMode,
    required double pinchScale,
    double maxZoomHeadroom = kProCanvasMaxZoomHeadroom,
  }) {
    final contain = containVideo(cw, ch, videoAr);
    final coverS = coverScale(cw, ch, contain.bw, contain.bh);
    final t = zoomSlider01.clamp(0.0, 1.0);
    final base = sliderBaseScale(t, coverS, fillExpandMode);
    final maxTotal = maxUniformScaleForRotatedRect(cw, ch, contain.bw, contain.bh, tiltRad);
    final cap = maxTotal * maxZoomHeadroom.clamp(1.0, 32.0);
    return math.min(base * pinchScale, cap);
  }

  /// InShot-style: chip **is** the aspect shape, inside a max cell (bottom-aligned in strip).
  static const double chipMaxW = 72;
  static const double chipMaxH = 118;

  static ({double w, double h}) ratioChipOuterSize(double? aspectWidthOverHeight, double videoAspect) {
    final r = (aspectWidthOverHeight ?? videoAspect).clamp(0.2, 10.0);
    if (r >= chipMaxW / chipMaxH) {
      final w = chipMaxW;
      return (w: w, h: w / r);
    }
    final h = chipMaxH;
    return (w: h * r, h: h);
  }
}
