import 'dart:math' as math;
import 'dart:ui' show Size;

/// Result of the fit-or-fill decision for one video on one screen.
class FitResult {
  const FitResult({
    required this.fill,
    required this.s0,
    required this.sFill,
    required this.zFill,
    required this.zMax,
    required this.base,
    required this.dy,
  });

  /// True when the video fills the screen (small crop).
  final bool fill;

  /// Starting scale (video pixels to screen pixels).
  final double s0;

  /// Scale that would exactly cover the screen.
  final double sFill;

  /// Zoom factor (relative to s0) at which the screen is exactly covered.
  final double zFill;

  /// Maximum zoom factor (relative to s0).
  final double zMax;

  /// Rendered size of the video at zoom 1.
  final Size base;

  /// Optical offset at zoom 1: the video sits slightly above center, so the
  /// bars split 40 (top) to 60 (bottom).
  final double dy;

  /// The offset fades out as the zoom approaches fill, so no gap ever opens.
  double dyAt(double z) {
    if (dy == 0) return 0;
    if (zFill <= 1.001) return dy;
    final t = ((z - 1) / (zFill - 1)).clamp(0.0, 1.0).toDouble();
    return dy * (1 - t);
  }
}

class FitMath {
  /// Smart policy: fill only when at most this much would be cropped. This is
  /// the broadcast "safe action" margin: viewers cannot count on seeing the
  /// outer 10% of a frame.
  static const double cropMax = 0.10;

  static FitResult compute(Size screen, Size video, {String policy = 'smart'}) {
    final vw = video.width <= 0 ? 1.0 : video.width;
    final vh = video.height <= 0 ? 1.0 : video.height;
    final sw = screen.width <= 0 ? 1.0 : screen.width;
    final sh = screen.height <= 0 ? 1.0 : screen.height;

    final sContain = math.min(sw / vw, sh / vh);
    final sCover = math.max(sw / vw, sh / vh);

    final aScreen = sw / sh;
    final aVideo = vw / vh;
    final r = math.min(aVideo, aScreen) / math.max(aVideo, aScreen);
    final crop = 1.0 - r;

    final bool fill;
    switch (policy) {
      case 'fill':
        fill = true;
        break;
      case 'fit':
        fill = false;
        break;
      default:
        fill = crop <= cropMax;
    }

    final s0 = fill ? sCover : sContain;
    final base = Size(vw * s0, vh * s0);
    final barsV = sh - base.height;
    final dy = (!fill && barsV > 1) ? -0.1 * barsV : 0.0;

    return FitResult(
      fill: fill,
      s0: s0,
      sFill: sCover,
      zFill: sCover / s0,
      zMax: 2.5 * sCover / s0,
      base: base,
      dy: dy,
    );
  }
}
