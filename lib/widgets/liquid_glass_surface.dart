import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

/// Lightweight frosted-glass surface tuned for Android TV rendering.
class LiquidGlassSurface extends StatelessWidget {
  const LiquidGlassSurface({
    super.key,
    required this.child,
    this.radius = 22,
    this.blur = 16,
    this.tint = const Color(0x1FFFFFFF),
    this.borderColor = const Color(0x33FFFFFF),
    this.padding = const EdgeInsets.all(12),
    this.glow = false,
  });

  final Widget child;
  final double radius;
  final double blur;
  final Color tint;
  final Color borderColor;
  final EdgeInsetsGeometry padding;
  final bool glow;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: padding,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color.lerp(tint, Colors.white, .12)!,
                tint,
                Color.lerp(tint, const Color(0xFF6C62A8), .10)!,
              ],
            ),
            borderRadius: BorderRadius.circular(radius),
            border: Border.all(color: borderColor, width: 1.15),
            boxShadow: [
              BoxShadow(
                color: glow ? const Color(0x66E6BD63) : Colors.black.withValues(alpha: .18),
                blurRadius: glow ? 24 : 16,
                spreadRadius: glow ? 1 : 0,
              ),
              const BoxShadow(
                color: Color(0x22FFFFFF),
                blurRadius: 1,
                offset: Offset(0, -1),
              ),
            ],
          ),
          child: child,
        ),
      ),
    );
  }
}
