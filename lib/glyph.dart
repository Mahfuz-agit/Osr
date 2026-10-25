import 'dart:math' as math;
import 'dart:ui' show Canvas, Color, Offset, Paint, PaintingStyle, Path, RRect, Radius, Rect, Size, StrokeCap, StrokeJoin;

import 'package:flutter/widgets.dart';

/// Hand-drawn glyphs in the style of Apple's SF Symbols (thin, round ends,
/// 24pt grid). SF Symbols themselves cannot be bundled on Android, so these
/// are original vector drawings.
enum GlyphKind {
  share,
  heart,
  heartFill,
  sliders,
  play,
  pause,
  folder,
  lockOpen,
  refresh,
  minusCircle,
}

class Glyph extends StatelessWidget {
  const Glyph(this.kind, {super.key, this.size = 24, required this.color});

  final GlyphKind kind;
  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _GlyphPainter(kind, color)),
    );
  }
}

class _GlyphPainter extends CustomPainter {
  _GlyphPainter(this.kind, this.color);

  final GlyphKind kind;
  final Color color;

  static const Radius _r2 = Radius.circular(2);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 24.0);

    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final fill = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    switch (kind) {
      case GlyphKind.share:
        final arrow = Path()
          ..moveTo(12, 14)
          ..lineTo(12, 3.5)
          ..moveTo(8.3, 7.2)
          ..lineTo(12, 3.5)
          ..lineTo(15.7, 7.2);
        final box = Path()
          ..moveTo(8, 10)
          ..lineTo(7, 10)
          ..arcToPoint(const Offset(5, 12), radius: _r2, clockwise: false)
          ..lineTo(5, 18.5)
          ..arcToPoint(const Offset(7, 20.5), radius: _r2, clockwise: false)
          ..lineTo(17, 20.5)
          ..arcToPoint(const Offset(19, 18.5), radius: _r2, clockwise: false)
          ..lineTo(19, 12)
          ..arcToPoint(const Offset(17, 10), radius: _r2, clockwise: false)
          ..lineTo(16, 10);
        canvas.drawPath(arrow, stroke);
        canvas.drawPath(box, stroke);
        break;

      case GlyphKind.heart:
        canvas.drawPath(_heart(), stroke);
        break;

      case GlyphKind.heartFill:
        canvas.drawPath(_heart(), fill);
        canvas.drawPath(_heart(), stroke);
        break;

      case GlyphKind.sliders:
        canvas.drawLine(const Offset(4, 7), const Offset(13, 7), stroke);
        canvas.drawLine(const Offset(17, 7), const Offset(20, 7), stroke);
        canvas.drawLine(const Offset(4, 17), const Offset(7, 17), stroke);
        canvas.drawLine(const Offset(11, 17), const Offset(20, 17), stroke);
        canvas.drawCircle(const Offset(15, 7), 2, stroke);
        canvas.drawCircle(const Offset(9, 17), 2, stroke);
        break;

      case GlyphKind.play:
        final tri = Path()
          ..moveTo(8, 5.2)
          ..lineTo(19, 12)
          ..lineTo(8, 18.8)
          ..close();
        canvas.drawPath(tri, fill);
        canvas.drawPath(tri, stroke);
        break;

      case GlyphKind.pause:
        canvas.drawRRect(
          RRect.fromLTRBR(7, 5, 10.6, 19, const Radius.circular(1.4)),
          fill,
        );
        canvas.drawRRect(
          RRect.fromLTRBR(13.4, 5, 17, 19, const Radius.circular(1.4)),
          fill,
        );
        break;

      case GlyphKind.folder:
        final f = Path()
          ..moveTo(3.5, 7.5)
          ..arcToPoint(const Offset(5.5, 5.5), radius: _r2)
          ..lineTo(9.1, 5.5)
          ..lineTo(11.1, 7.5)
          ..lineTo(18.5, 7.5)
          ..arcToPoint(const Offset(20.5, 9.5), radius: _r2)
          ..lineTo(20.5, 17.5)
          ..arcToPoint(const Offset(18.5, 19.5), radius: _r2)
          ..lineTo(5.5, 19.5)
          ..arcToPoint(const Offset(3.5, 17.5), radius: _r2)
          ..close();
        canvas.drawPath(f, stroke);
        break;

      case GlyphKind.lockOpen:
        canvas.drawRRect(
          RRect.fromLTRBR(5, 11, 19, 20.5, const Radius.circular(2.5)),
          stroke,
        );
        final shackle = Path()
          ..moveTo(8, 11)
          ..lineTo(8, 8)
          ..arcToPoint(const Offset(15.5, 6.5), radius: const Radius.circular(3.8));
        canvas.drawPath(shackle, stroke);
        break;

      case GlyphKind.refresh:
        const center = Offset(12, 12);
        const radius = 7.5;
        const start = -0.9;
        const sweep = 5.2;
        final arc = Path()
          ..addArc(Rect.fromCircle(center: center, radius: radius), start, sweep);
        canvas.drawPath(arc, stroke);
        const endAngle = start + sweep;
        final end = Offset(
          center.dx + radius * math.cos(endAngle),
          center.dy + radius * math.sin(endAngle),
        );
        final back = Offset(math.sin(endAngle), -math.cos(endAngle));
        Offset rot(Offset v, double a) => Offset(
              v.dx * math.cos(a) - v.dy * math.sin(a),
              v.dx * math.sin(a) + v.dy * math.cos(a),
            );
        final h1 = rot(back, 0.6) * 3.6;
        final h2 = rot(back, -0.6) * 3.6;
        final head = Path()
          ..moveTo(end.dx + h1.dx, end.dy + h1.dy)
          ..lineTo(end.dx, end.dy)
          ..lineTo(end.dx + h2.dx, end.dy + h2.dy);
        canvas.drawPath(head, stroke);
        break;

      case GlyphKind.minusCircle:
        canvas.drawCircle(const Offset(12, 12), 9, fill);
        final line = Paint()
          ..color = const Color(0xFFFFFFFF)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..strokeCap = StrokeCap.round;
        canvas.drawLine(const Offset(7.5, 12), const Offset(16.5, 12), line);
        break;
    }
    canvas.restore();
  }

  Path _heart() {
    return Path()
      ..moveTo(12, 20.2)
      ..cubicTo(12, 20.2, 4, 15.6, 4, 9.9)
      ..arcToPoint(const Offset(12, 7.7), radius: const Radius.circular(4.3))
      ..arcToPoint(const Offset(20, 9.9), radius: const Radius.circular(4.3))
      ..cubicTo(20, 15.6, 12, 20.2, 12, 20.2)
      ..close();
  }

  @override
  bool shouldRepaint(covariant _GlyphPainter old) =>
      old.kind != kind || old.color != color;
}
