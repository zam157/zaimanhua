import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:zai_x/modules/comic/reader/comic_reader_pan.dart';
import 'package:zai_x/modules/comic/reader/comic_reader_viewport.dart';

/// Zooms one continuous strip while the list handles vertical scrolling.
class ComicStripViewport extends StatefulWidget {
  const ComicStripViewport({
    super.key,
    required this.zoomEnabled,
    required this.animateZoom,
    required this.onTap,
    required this.builder,
  });

  final bool zoomEnabled;
  final bool animateZoom;
  final ValueChanged<double> onTap;
  final Widget Function(BuildContext context, bool scrollLocked) builder;

  @override
  State<ComicStripViewport> createState() => _ComicStripViewportState();
}

class _ComicStripViewportState extends State<ComicStripViewport>
    with TickerProviderStateMixin {
  final _transform = TransformationController();
  final _pointers = <int>{};
  final _pan = ComicReaderPan(horizontalOnly: true);
  late final ComicReaderPanMomentum _momentum;
  late final AnimationController _animation;
  late Animation<Matrix4> _transition;
  ScrollableState? _scrollable;
  bool _pinching = false;
  double _startScale = kComicReaderFitScale;
  double _sceneX = 0;
  double _animationFocalY = 0;
  Offset _lastFocal = Offset.zero;
  Offset _doubleTapPosition = Offset.zero;

  double get _scale => _transform.value.getMaxScaleOnAxis();
  double get _x => _transform.value.getTranslation().x;
  double get _minimumX => context.size!.width * (1 - _scale);
  bool get _animate =>
      widget.animateZoom && !MediaQuery.disableAnimationsOf(context);

  @override
  void initState() {
    super.initState();
    _momentum = ComicReaderPanMomentum(
        this, (position) => _setHorizontalPan(position.dx));
    _animation =
        AnimationController(vsync: this, duration: kComicReaderZoomDuration)
          ..addListener(() {
            final value = _transition.value;
            _applyZoom(
              value.getMaxScaleOnAxis(),
              value.getTranslation().x,
              _animationFocalY,
              _animationFocalY,
            );
          })
          ..addStatusListener((_) => setState(() {}));
  }

  @override
  void didUpdateWidget(covariant ComicStripViewport oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.zoomEnabled) {
      _animation.stop();
      _pan.cancel();
      _momentum.stop();
    }
  }

  bool _rememberScrollable(ScrollMetricsNotification notification) {
    if (notification.depth == 0) {
      _scrollable =
          Scrollable.maybeOf(notification.context, axis: Axis.vertical);
    }
    return false;
  }

  void _applyZoom(double scale, double x, double oldY, double newY) {
    final size = context.size!;
    final scrollable = _scrollable;
    final scrollDelta = oldY / _scale - newY / scale;
    _transform.value = Matrix4.identity()
      ..translateByDouble(x.clamp(size.width * (1 - scale), 0), 0, 0, 1)
      ..scaleByDouble(scale, scale, scale, 1);

    if (scrollDelta.abs() < 1e-6 || scrollable == null || !scrollable.mounted) {
      return;
    }
    final position = scrollable.position;
    if (!position.hasContentDimensions || !position.hasPixels) return;

    // The list still uses its old logical height until the next layout.
    // Account for the new height when keeping the point under the fingers.
    final max = math.max(
        position.minScrollExtent,
        position.maxScrollExtent +
            position.viewportDimension -
            size.height / scale);
    final target =
        (position.pixels + scrollDelta).clamp(position.minScrollExtent, max);
    if ((target - position.pixels).abs() >= 1e-6) position.jumpTo(target);
  }

  void _onPointerDown(PointerDownEvent event) {
    _momentum.stop();
    _pointers.add(event.pointer);
    if (widget.zoomEnabled &&
        _scale > kComicReaderFitScale &&
        _pointers.length == 1) {
      _pan.begin(event, MediaQuery.maybeGestureSettingsOf(context));
    }
    if (_animation.isAnimating ||
        (widget.zoomEnabled && _pointers.length == 2)) {
      setState(() {
        _animation.stop();
        _pinching = widget.zoomEnabled && _pointers.length >= 2;
        if (_pinching) _pan.cancel();
      });
    }
  }

  void _setHorizontalPan(double x) {
    final clamped = x.clamp(_minimumX, 0).toDouble();
    if (clamped == _x) return;
    _transform.value = _transform.value.clone()
      ..setTranslationRaw(clamped, 0, 0);
  }

  void _onPointerMove(PointerMoveEvent event) {
    final delta = _pan.update(event);
    if (delta != null) _setHorizontalPan(_x + delta.dx);
  }

  void _onPointerUp(PointerUpEvent event) {
    final velocity = _pan.end(event);
    _onPointerEnd(event);
    if (velocity != null && _animate) {
      _momentum.fling(
          Offset(_x, 0), Offset(velocity.dx, 0), Offset(_minimumX, 0));
    }
  }

  void _onPointerEnd(PointerEvent event) {
    _pointers.remove(event.pointer);
    if (_pinching && _pointers.isEmpty) setState(() => _pinching = false);
  }

  void _onScaleStart(ScaleStartDetails details) {
    _startScale = _scale;
    _lastFocal = details.localFocalPoint;
    _sceneX = (_lastFocal.dx - _x) / _startScale;
  }

  void _onScaleUpdate(ScaleUpdateDetails details) {
    final focal = details.localFocalPoint;
    if (_pinching && details.pointerCount > 1) {
      final scale = (_startScale * details.scale)
          .clamp(kComicReaderFitScale, kComicReaderMaxScale);
      _applyZoom(scale, focal.dx - _sceneX * scale, _lastFocal.dy, focal.dy);
    } else if (_pointers.isEmpty && _scale > kComicReaderFitScale) {
      _setHorizontalPan(_x + details.focalPointDelta.dx);
    }
    _lastFocal = focal;
  }

  void _toggleZoom() {
    final scale = _scale > kComicReaderFitScale + 1e-6
        ? kComicReaderFitScale
        : kComicReaderDoubleTapScale;
    final x = _doubleTapPosition.dx * (1 - scale);
    final y = _doubleTapPosition.dy;
    if (!_animate) {
      _applyZoom(scale, x, y, y);
      return;
    }
    _animationFocalY = y;
    final target = Matrix4.identity()
      ..translateByDouble(x, 0, 0, 1)
      ..scaleByDouble(scale, scale, scale, 1);
    _transition = Matrix4Tween(begin: _transform.value, end: target)
        .chain(CurveTween(curve: Curves.easeInOutCubic))
        .animate(_animation);
    _animation.forward(from: 0);
  }

  @override
  void dispose() {
    _momentum.dispose();
    _animation.dispose();
    _transform.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.zoomEnabled;
    return SizedBox.expand(
      child: Listener(
        onPointerDown: _onPointerDown,
        onPointerMove: _onPointerMove,
        onPointerUp: _onPointerUp,
        onPointerCancel: (event) {
          _pan.cancel();
          _onPointerEnd(event);
        },
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapUp: (details) {
            if (!_pinching) {
              widget.onTap(details.localPosition.dx / context.size!.width);
            }
          },
          onDoubleTapDown: enabled
              ? (details) => _doubleTapPosition = details.localPosition
              : null,
          onDoubleTap: enabled ? _toggleZoom : null,
          onScaleStart: enabled ? _onScaleStart : null,
          onScaleUpdate: enabled ? _onScaleUpdate : null,
          child: ClipRect(
            child: LayoutBuilder(
              builder: (_, constraints) => ValueListenableBuilder<Matrix4>(
                valueListenable: _transform,
                child: NotificationListener<ScrollMetricsNotification>(
                  onNotification: _rememberScrollable,
                  child: NotificationListener<ScrollStartNotification>(
                    onNotification: (notification) {
                      if (notification.depth == 0 &&
                          notification.dragDetails != null) {
                        _pan.cancel();
                        _momentum.stop();
                      }
                      return false;
                    },
                    child: widget.builder(
                        context, _pinching || _animation.isAnimating),
                  ),
                ),
                builder: (_, matrix, child) {
                  // Use the height that is actually visible after scaling.
                  // The list's item positions and chapter edges stay accurate.
                  final height =
                      constraints.maxHeight / matrix.getMaxScaleOnAxis();
                  return Transform(
                    transform: matrix,
                    alignment: Alignment.topLeft,
                    child: OverflowBox(
                      alignment: Alignment.topLeft,
                      minHeight: height,
                      maxHeight: height,
                      child: child,
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}
