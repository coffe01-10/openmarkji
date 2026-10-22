// OpenMarkji adapters for the GPL-3.0 components in this directory.
import 'package:flutter/material.dart';

extension GlassContext on BuildContext {
  ColorScheme get colorScheme => Theme.of(this).colorScheme;
  Duration motionDuration(Duration duration) =>
      MediaQuery.disableAnimationsOf(this) ? Duration.zero : duration;
}

abstract final class AppShape {
  static const full = StadiumBorder();
  static RoundedSuperellipseBorder all(double radius) =>
      of(BorderRadius.circular(radius));
  static RoundedSuperellipseBorder of(BorderRadius corners) =>
      RoundedSuperellipseBorder(borderRadius: corners);
}

enum SurfaceLevel {
  card,
  block,
  inset;

  SurfaceLevel get next => this == card ? block : inset;
  static SurfaceLevel floatingOf(ColorScheme scheme) =>
      scheme.brightness == Brightness.dark ? block : card;
  Color colorOf(ColorScheme scheme) => switch (this) {
    card => scheme.surfaceContainerLowest,
    block => scheme.surfaceContainerHigh,
    inset => scheme.surfaceContainerHighest,
  };
}

abstract final class AppRadius {
  static BorderRadius all(double radius) => BorderRadius.circular(radius);
}

typedef Glyph = IconData;

class GlyphIcon extends StatelessWidget {
  const GlyphIcon(this.glyph, {super.key, this.size, this.color, this.fill});
  final IconData glyph;
  final double? size, fill;
  final Color? color;
  @override
  Widget build(BuildContext context) =>
      Icon(glyph, size: size, color: color, fill: fill);
}

abstract final class AppTextStyle {
  static const subheadline = _AppTextStyle(15, 22);
  static TextStyle custom(
    BuildContext context, {
    required double size,
    required double leading,
    required FontWeight weight,
  }) => TextStyle(fontSize: size, height: leading / size, fontWeight: weight);
}

class _AppTextStyle {
  const _AppTextStyle(this.size, this.leading);
  final double size, leading;
  TextStyle of(BuildContext context) =>
      TextStyle(fontSize: size, height: leading / size);
}

double textWidthOf(BuildContext context, String text, TextStyle style) {
  final painter = TextPainter(
    text: TextSpan(text: text, style: style),
    textDirection: Directionality.of(context),
    textScaler: MediaQuery.textScalerOf(context),
  )..layout();
  final width = painter.width;
  painter.dispose();
  return width;
}

BorderSide focusRingSide(ColorScheme scheme) =>
    BorderSide(color: scheme.primary, width: 2);
