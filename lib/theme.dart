import 'package:flutter/material.dart';

/// Spacing scale (4pt base). Nothing outside these values.
class Sp {
  static const double x1 = 4;
  static const double x2 = 8;
  static const double x3 = 12;
  static const double x4 = 16;
  static const double x6 = 24;
  static const double x8 = 32;
}

/// The only three durations used for motion.
class Dur {
  static const Duration fast = Duration(milliseconds: 150);
  static const Duration base = Duration(milliseconds: 250);
  static const Duration slow = Duration(milliseconds: 350);
}

/// The one easing curve used everywhere.
const Curve kEase = Cubic(0.2, 0.8, 0.2, 1.0);

/// Colors that follow light and dark mode.
class Pal {
  const Pal({
    required this.dark,
    required this.bg,
    required this.ink,
    required this.muted,
    required this.glassFill,
    required this.glassEdge,
    required this.solid,
    required this.ambientTint,
  });

  final bool dark;
  final Color bg;
  final Color ink;
  final Color muted;
  final Color glassFill;
  final Color glassEdge;
  final Color solid;
  final Color ambientTint;

  static const Color pink = Color(0xFFE0557F);

  static const Pal light = Pal(
    dark: false,
    bg: Color(0xFFF1EFE8),
    ink: Color(0xFF1C1C1E),
    muted: Color(0xFF6C6C70),
    glassFill: Color(0x4DFFFFFF),
    glassEdge: Color(0xB3FFFFFF),
    solid: Color(0xF2FFFFFF),
    ambientTint: Color(0x26FFFFFF),
  );

  static const Pal darkPal = Pal(
    dark: true,
    bg: Color(0xFF000000),
    ink: Color(0xFFFFFFFF),
    muted: Color(0xFF8E8E93),
    glassFill: Color(0x5C3C3C43),
    glassEdge: Color(0x2EFFFFFF),
    solid: Color(0xF21C1C1E),
    ambientTint: Color(0x59000000),
  );

  static Pal of(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark ? darkPal : light;
}

ThemeData buildTheme(Brightness b) {
  final isDark = b == Brightness.dark;
  final accent = isDark ? const Color(0xFF0A84FF) : const Color(0xFF007AFF);
  return ThemeData(
    useMaterial3: true,
    brightness: b,
    colorScheme: ColorScheme.fromSeed(seedColor: accent, brightness: b)
        .copyWith(primary: accent),
    scaffoldBackgroundColor: isDark ? Colors.black : Colors.white,
  );
}
