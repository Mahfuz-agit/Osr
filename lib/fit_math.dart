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
  });

  /// True when the video fills the screen (small crop). False means it is
  /// fitted whole, with an ambient blur behind it.
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
}

class FitMath {
  /// A video is cropped to fill only when at most this share is lost.
  static const double cropMax = 0.25;

  static FitResult compute(Size screen, Size video) {
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

    final fill = crop <= cropMax;
    final s0 = fill ? sCover : sContain;
    return FitResult(
      fill: fill,
      s0: s0,
      sFill: sCover,
      zFill: sCover / s0,
      zMax: 2.5 * sCover / s0,
      base: Size(vw * s0, vh * s0),
    );
  }
}
