import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import 'app_state.dart';
import 'theme.dart';

/// Frosted glass: real backdrop blur, a translucent tint and a hairline edge.
/// Falls back to a solid fill when transparency is reduced.
class Glass extends StatelessWidget {
  const Glass({
    super.key,
    required this.child,
    this.width,
    this.height,
    this.radius = 0,
    this.circle = false,
    this.padding,
    this.alignment,
  });

  final Widget child;
  final double? width;
  final double? height;
  final double radius;
  final bool circle;
  final EdgeInsetsGeometry? padding;
  final AlignmentGeometry? alignment;

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    final solid =
        AppState.instance.reduceTransparency || MediaQuery.of(context).highContrast;
    final box = Container(
      width: width,
      height: height,
      padding: padding,
      alignment: alignment,
      decoration: BoxDecoration(
        color: solid ? p.solid : p.glassFill,
        shape: circle ? BoxShape.circle : BoxShape.rectangle,
        borderRadius: circle ? null : BorderRadius.circular(radius),
        border: Border.all(color: p.glassEdge, width: 0.5),
      ),
      child: child,
    );
    if (solid) return box;
    final blurred = BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
      child: box,
    );
    return circle
        ? ClipOval(child: blurred)
        : ClipRRect(borderRadius: BorderRadius.circular(radius), child: blurred);
  }
}

/// Scales down slightly while pressed.
class Pressable extends StatefulWidget {
  const Pressable({super.key, required this.child, this.onTap});

  final Widget child;
  final VoidCallback? onTap;

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => setState(() => _down = true),
      onTapUp: (_) => setState(() => _down = false),
      onTapCancel: () => setState(() => _down = false),
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: _down ? 0.92 : 1.0,
        duration: Dur.fast,
        curve: kEase,
        child: widget.child,
      ),
    );
  }
}

/// Round glass button.
class GlassButton extends StatelessWidget {
  const GlassButton({
    super.key,
    required this.icon,
    required this.onTap,
    this.size = 48,
    this.iconSize = 22,
  });

  final IconData icon;
  final VoidCallback onTap;
  final double size;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    return Pressable(
      onTap: onTap,
      child: Glass(
        circle: true,
        width: size,
        height: size,
        alignment: Alignment.center,
        child: Icon(icon, size: iconSize, color: p.ink),
      ),
    );
  }
}
