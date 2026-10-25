import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import 'theme.dart';

/// Where controls may live. Mirrors the bands TikTok, Instagram, Facebook and
/// YouTube Shorts keep clear: about 14% at the top and 35% at the bottom.
/// Every control stays inside these bands, and never touches the screen edge
/// or the system gesture area (it always clears the system inset).
class UiZones {
  const UiZones({
    required this.topBand,
    required this.bottomBand,
    required this.topOffset,
    required this.bottomOffset,
    required this.topButton,
    required this.bottomButton,
  });

  final double topBand;
  final double bottomBand;
  final double topOffset;
  final double bottomOffset;
  final double topButton;
  final double bottomButton;

  static UiZones of(MediaQueryData mq) {
    final h = mq.size.height;
    final topInset = math.max(mq.padding.top, mq.viewPadding.top);
    final bottomInset = math.max(mq.padding.bottom, mq.viewPadding.bottom);

    final topBand = math.max(0.14 * h, topInset + 64);
    final bottomBand = 0.35 * h;
    final topOffset = topInset + Sp.x2;
    final bottomOffset = bottomInset + Sp.x4;

    // Buttons shrink (never below 40 and 44) instead of leaving the band.
    final topButton = (topBand - topOffset).clamp(40.0, 44.0).toDouble();
    final bottomButton = (bottomBand - bottomOffset).clamp(44.0, 52.0).toDouble();

    return UiZones(
      topBand: topBand,
      bottomBand: bottomBand,
      topOffset: topOffset,
      bottomOffset: bottomOffset,
      topButton: topButton,
      bottomButton: bottomButton,
    );
  }
}
