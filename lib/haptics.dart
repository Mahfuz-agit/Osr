import 'package:flutter/services.dart';

import 'app_state.dart';

/// Haptics are rare and meaningful: one for a favorite, light ticks at
/// detents (scrub deciles, zoom fit and fill), one when scrubbing begins.
class Haptics {
  static bool get _on => AppState.instance.haptics;

  static void selection() {
    if (_on) HapticFeedback.selectionClick();
  }

  static void light() {
    if (_on) HapticFeedback.lightImpact();
  }

  static void medium() {
    if (_on) HapticFeedback.mediumImpact();
  }

  static void like() {
    if (_on) HapticFeedback.mediumImpact();
  }
}
