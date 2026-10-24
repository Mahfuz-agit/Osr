import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import 'fit_math.dart';

/// Pinch zoom and pan for the current video.
///
/// Rules: zoom stays within [1, zMax], with magnetic detents at fit (1) and
/// fill (zFill). Below 1 and above zMax it resists like rubber and springs
/// back. Pan is limited so the video edge never leaves the screen edge.
class ZoomController extends ChangeNotifier {
  ZoomController(TickerProvider vsync) {
    _ticker = vsync.createTicker(_onTick);
  }

  late final Ticker _ticker;
  static final SpringDescription _spring = SpringDescription.withDampingRatio(
    mass: 1.0,
    stiffness: 220.0,
    ratio: 0.9,
  );

  double z = 1.0;
  double tx = 0.0;
  double ty = 0.0;
  FitResult? fit;
  Size screen = Size.zero;

  /// Called when the pinch enters a detent: 1 = fit, 2 = fill.
  void Function(int id)? onDetent;

  double _sz = 1.0;
  double _stx = 0.0;
  double _sty = 0.0;
  Offset _sf = Offset.zero;
  int _detent = 0;

  SpringSimulation? _zs;
  SpringSimulation? _xs;
  SpringSimulation? _ys;
  double _tz = 1.0;
  double _ttx = 0.0;
  double _tty = 0.0;

  bool get zoomed => z > 1.01;

  void configure(FitResult f, Size s) {
    fit = f;
    screen = s;
  }

  double _limitX(double zz) {
    final f = fit;
    if (f == null) return 0.0;
    return math.max(0.0, (f.base.width * zz - screen.width) / 2);
  }

  double _limitY(double zz) {
    final f = fit;
    if (f == null) return 0.0;
    return math.max(0.0, (f.base.height * zz - screen.height) / 2);
  }

  double _rubber(double v, double lim) {
    if (v > lim) return lim + (v - lim) * 0.4;
    if (v < -lim) return -lim + (v + lim) * 0.4;
    return v;
  }

  void start(Offset focal) {
    _ticker.stop();
    _sz = z;
    _stx = tx;
    _sty = ty;
    _sf = focal - Offset(screen.width / 2, screen.height / 2);
    _detent = 0;
  }

  void update(double scale, Offset focal) {
    final f = fit;
    if (f == null) return;
    final zr = _sz * scale;
    var zz = zr;
    var det = 0;
    if (zr < 1.0) {
      zz = 1.0 - (1.0 - zr) * 0.4;
    } else if ((zr - 1.0).abs() < 0.04) {
      zz = 1.0;
      det = 1;
    } else if (f.zFill > 1.05 && (zr - f.zFill).abs() / f.zFill < 0.06) {
      zz = f.zFill;
      det = 2;
    } else if (zr > f.zMax) {
      zz = f.zMax + (zr - f.zMax) * 0.3;
    }
    if (det != 0 && det != _detent) onDetent?.call(det);
    _detent = det;

    final center = Offset(screen.width / 2, screen.height / 2);
    final fo = focal - center;
    final content = (_sf - Offset(_stx, _sty)) / _sz;
    final nt = fo - content * zz;
    z = zz;
    tx = _rubber(nt.dx, _limitX(zz));
    ty = _rubber(nt.dy, _limitY(zz));
    notifyListeners();
  }

  void end(Offset velocity) {
    final f = fit;
    if (f == null) return;
    var tz = z.clamp(1.0, f.zMax).toDouble();
    if (tz < 1.08) {
      tz = 1.0;
    } else if (f.zFill > 1.05 && (tz - f.zFill).abs() / f.zFill < 0.12) {
      tz = f.zFill;
    }
    var ttx = 0.0;
    var tty = 0.0;
    if (tz > 1.0) {
      final lx = _limitX(tz);
      final ly = _limitY(tz);
      ttx = (tx + velocity.dx * 0.18).clamp(-lx, lx).toDouble();
      tty = (ty + velocity.dy * 0.18).clamp(-ly, ly).toDouble();
    }
    _animate(tz, ttx, tty);
  }

  void reset() => _animate(1.0, 0.0, 0.0);

  void resetNow() {
    _ticker.stop();
    z = 1.0;
    tx = 0.0;
    ty = 0.0;
    notifyListeners();
  }

  void _animate(double tz, double ttx, double tty) {
    if ((z - tz).abs() < 0.001 && (tx - ttx).abs() < 0.5 && (ty - tty).abs() < 0.5) {
      z = tz;
      tx = ttx;
      ty = tty;
      notifyListeners();
      return;
    }
    _tz = tz;
    _ttx = ttx;
    _tty = tty;
    _zs = SpringSimulation(_spring, z, tz, 0.0);
    _xs = SpringSimulation(_spring, tx, ttx, 0.0);
    _ys = SpringSimulation(_spring, ty, tty, 0.0);
    _ticker.stop();
    _ticker.start();
  }

  void _onTick(Duration elapsed) {
    final t = elapsed.inMicroseconds / 1000000.0;
    final zs = _zs;
    final xs = _xs;
    final ys = _ys;
    if (zs == null || xs == null || ys == null) {
      _ticker.stop();
      return;
    }
    z = zs.x(t);
    tx = xs.x(t);
    ty = ys.x(t);
    if (zs.isDone(t) && xs.isDone(t) && ys.isDone(t)) {
      z = _tz;
      tx = _ttx;
      ty = _tty;
      _ticker.stop();
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }
}
