// Adapted from GPL-3.0 upstream code. See third_party/GPL-3.0/NOTICE.md.
import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import 'compat.dart';
import 'liquid_glass.dart';
import 'motion.dart';
import 'navigation_dock.dart';

const _alertRadius = 34.0;
const _alertDuration = Duration(milliseconds: 404);
final _alertSpring = SpringCurve(
  SpringDescription.withDurationAndBounce(
    duration: const Duration(milliseconds: 275),
  ),
  seconds: _alertDuration.inMicroseconds / Duration.microsecondsPerSecond,
);

Future<T?> showGlassDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
}) => Navigator.of(context, rootNavigator: true).push<T>(
  _GlassDialogRoute<T>(
    builder: builder,
    duration: context.motionDuration(_alertDuration),
    barrierColor: context.colorScheme.scrim.withValues(
      alpha: context.colorScheme.brightness == Brightness.dark ? .48 : .2,
    ),
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
  ),
);

class _GlassDialogRoute<T> extends PopupRoute<T> {
  _GlassDialogRoute({
    required this.builder,
    required this.duration,
    required this.barrierColor,
    required this.barrierLabel,
  });

  final WidgetBuilder builder;
  final Duration duration;
  @override
  final Color barrierColor;
  @override
  final String barrierLabel;
  @override
  bool get barrierDismissible => true;
  @override
  Duration get transitionDuration => duration;

  late final _spring = CurvedAnimation(
    parent: animation!,
    curve: _alertSpring,
    reverseCurve: _alertSpring.flipped,
  );

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) => Semantics(
    scopesRoute: true,
    explicitChildNodes: true,
    child: SafeArea(child: Builder(builder: builder)),
  );

  @override
  Widget buildModalBarrier() => AnimatedModalBarrier(
    color: _spring.drive(
      ColorTween(begin: barrierColor.withValues(alpha: 0), end: barrierColor),
    ),
    dismissible: barrierDismissible,
    semanticsLabel: barrierLabel,
    barrierSemanticsDismissible: semanticsDismissible,
  );

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) => _AlertTransition(animation: _spring, child: child);

  @override
  void dispose() {
    _spring.dispose();
    super.dispose();
  }
}

class _AlertTransition extends StatefulWidget {
  const _AlertTransition({required this.animation, required this.child});
  final Animation<double> animation;
  final Widget child;
  @override
  State<_AlertTransition> createState() => _AlertTransitionState();
}

class _AlertTransitionState extends State<_AlertTransition> {
  double? _heldScale;
  double get _scale => _heldScale ?? 1.2 - .2 * widget.animation.value;

  @override
  void initState() {
    super.initState();
    widget.animation.addStatusListener(_handleStatus);
  }

  @override
  void dispose() {
    widget.animation.removeStatusListener(_handleStatus);
    super.dispose();
  }

  void _handleStatus(AnimationStatus status) {
    // Dismissal fades at the current size, including during entry.
    _heldScale = status == AnimationStatus.reverse ? _scale : null;
  }

  @override
  Widget build(BuildContext context) => LiquidGlassFade(
    opacity: widget.animation,
    child: AnimatedBuilder(
      animation: widget.animation,
      builder: (_, child) => Transform.scale(scale: _scale, child: child),
      child: widget.child,
    ),
  );
}

/// Keeps Material's dialog layout while painting glass at its actual surface.
class GlassAlertDialog extends StatelessWidget {
  const GlassAlertDialog({
    super.key,
    required this.title,
    required this.content,
    required this.actions,
  });
  final Widget title, content;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final glass = LiquidGlassScope.of(context);
    final scheme = context.colorScheme;
    final text = Theme.of(context).textTheme;
    final dialog = AlertDialog(
      backgroundColor: glass
          ? Colors.transparent
          : SurfaceLevel.floatingOf(scheme).colorOf(scheme),
      surfaceTintColor: Colors.transparent,
      elevation: glass ? 0 : null,
      shape: AppShape.all(_alertRadius),
      titleTextStyle: text.titleLarge?.copyWith(
        fontSize: 20,
        fontWeight: FontWeight.w600,
        color: scheme.onSurface,
      ),
      contentTextStyle: text.bodyMedium?.copyWith(
        fontSize: 15,
        height: 1.5,
        color: scheme.onSurfaceVariant,
      ),
      titlePadding: const EdgeInsets.fromLTRB(30, 24, 30, 0),
      contentPadding: const EdgeInsets.fromLTRB(30, 8, 30, 24),
      actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      title: title,
      content: content,
      actions: actions,
    );
    return ElasticPress(
      enabled: !MediaQuery.disableAnimationsOf(context),
      pullPastEdges: true,
      maxGrowth: 4,
      maxPull: 3,
      panelOf: _surfaceRectIn,
      child: glass
          ? _AlertGlass(
              style: LiquidGlassScope.alertStyleOf(context),
              rim: LiquidGlassRim.alert(scheme),
              shadows: glassMenuShadows(scheme),
              child: dialog,
            )
          : dialog,
    );
  }
}

RenderPhysicalShape? _surfaceIn(RenderObject node) {
  if (node is RenderPhysicalShape) return node;
  RenderPhysicalShape? surface;
  node.visitChildren((child) => surface ??= _surfaceIn(child));
  return surface;
}

Rect _surfaceRectIn(RenderBox box) {
  final surface = _surfaceIn(box);
  if (surface == null) return Offset.zero & box.size;
  return MatrixUtils.transformRect(
    surface.getTransformTo(box),
    Offset.zero & surface.size,
  );
}

class _AlertGlass extends SingleChildRenderObjectWidget {
  const _AlertGlass({
    required this.style,
    required this.rim,
    required this.shadows,
    required super.child,
  });
  final LiquidGlassStyle style;
  final LiquidGlassRim rim;
  final List<BoxShadow> shadows;
  @override
  _RenderAlertGlass createRenderObject(BuildContext context) =>
      _RenderAlertGlass(style, rim, shadows);
  @override
  void updateRenderObject(
    BuildContext context,
    _RenderAlertGlass renderObject,
  ) {
    renderObject
      ..style = style
      ..rim = rim
      ..shadows = shadows;
  }
}

class _RenderAlertGlass extends RenderProxyBox {
  _RenderAlertGlass(this._style, this._rim, this._shadows);
  late final _pane = LiquidGlassPane(markNeedsPaint);
  LiquidGlassStyle _style;
  set style(LiquidGlassStyle value) {
    if (value == _style) return;
    _style = value;
    markNeedsPaint();
  }

  LiquidGlassRim _rim;
  set rim(LiquidGlassRim value) {
    if (value == _rim) return;
    _rim = value;
    markNeedsPaint();
  }

  List<BoxShadow> _shadows;
  set shadows(List<BoxShadow> value) {
    if (listEquals(value, _shadows)) return;
    _shadows = value;
    markNeedsPaint();
  }

  @override
  bool get alwaysNeedsCompositing => true;
  @override
  void dispose() {
    _pane.dispose();
    super.dispose();
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    if (_surfaceIn(this) == null) {
      _pane.clear();
    } else {
      final rect = _surfaceRectIn(this).shift(offset);
      _pane.paint(
        context,
        rect,
        shape: LiquidGlassCorners.circular(_alertRadius),
        style: _style,
        shadows: _shadows,
        rim: _rim,
      );
      _rim.paintLine(context.canvas, rect, _alertRadius);
    }
    super.paint(context, offset);
  }
}
