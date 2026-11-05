import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

const kComicReaderFitScale = 1.0;
const kComicReaderDoubleTapScale = 2.5;
const kComicReaderMaxScale = 4.0;
const kComicReaderZoomDuration = Duration(milliseconds: 220);

typedef ComicReaderPageDecorator = Widget Function(
    Object pageKey, Widget child);

/// Zooms the visible reading area without changing the layout of its pages.
class ComicReaderViewport extends StatefulWidget {
  const ComicReaderViewport({
    super.key,
    required this.zoomEnabled,
    required this.resetToken,
    required this.pageKey,
    required this.onTap,
    required this.onPreviousPage,
    required this.onNextPage,
    required this.builder,
    this.previewBuilder,
    this.reverse = false,
    this.animateZoom = true,
  });

  final bool zoomEnabled;
  final Object resetToken;
  final Object pageKey;
  final ValueChanged<double> onTap;
  final VoidCallback? onPreviousPage;
  final VoidCallback? onNextPage;
  final Widget Function(
    BuildContext context,
    bool scrollLocked,
    ComicReaderPageDecorator decoratePage,
  ) builder;
  final ({Object pageKey, Widget child})? Function(bool next)? previewBuilder;
  final bool reverse;
  final bool animateZoom;

  @override
  State<ComicReaderViewport> createState() => _ComicReaderViewportState();
}

class _ComicReaderViewportState extends State<ComicReaderViewport>
    with TickerProviderStateMixin {
  final _transform = TransformationController();
  final _pageTransforms = <Object, Matrix4>{};
  final _pointers = <int>{};
  late final AnimationController _zoomAnimation;
  late final AnimationController _pageSlide;
  late Animation<Matrix4> _zoomTransition;
  Offset _doubleTapPosition = Offset.zero;
  Offset _dragDelta = Offset.zero;
  bool _zoomed = false;
  bool _pinching = false;
  bool _scrolling = false;
  bool _restoreAfterScroll = false;

  @override
  void initState() {
    super.initState();
    _transform.addListener(_updateZoomState);
    _zoomAnimation = AnimationController(
      vsync: this,
      duration: kComicReaderZoomDuration,
    )
      ..addListener(() => _transform.value = _zoomTransition.value)
      ..addStatusListener((_) => setState(() {}));
    _pageSlide = AnimationController.unbounded(vsync: this);
  }

  @override
  void didUpdateWidget(covariant ComicReaderViewport oldWidget) {
    super.didUpdateWidget(oldWidget);
    final layoutChanged = oldWidget.resetToken != widget.resetToken;
    if (layoutChanged ||
        oldWidget.pageKey != widget.pageKey ||
        oldWidget.zoomEnabled != widget.zoomEnabled) {
      if (layoutChanged) {
        _pageTransforms.clear();
      } else if (oldWidget.zoomEnabled && !_restoreAfterScroll) {
        if (_zoomed) {
          _pageTransforms[oldWidget.pageKey] = _transform.value.clone();
        } else {
          _pageTransforms.remove(oldWidget.pageKey);
        }
      }
      _zoomAnimation.stop();
      _pageSlide.value = 0;
      if (layoutChanged || !widget.zoomEnabled) _scrolling = false;
      final saved = widget.zoomEnabled ? _pageTransforms[widget.pageKey] : null;
      _restoreAfterScroll = saved != null && _scrolling;
      _transform.value = _restoreAfterScroll
          ? Matrix4.identity()
          : saved?.clone() ?? Matrix4.identity();
    }
  }

  bool _onScroll(ScrollNotification notification) {
    if (notification.depth != 0) return false;
    if (notification is ScrollStartNotification) {
      _scrolling = true;
    } else if (notification is ScrollEndNotification) {
      _scrolling = false;
      if (_restoreAfterScroll) {
        // Restoring zoom locks user scrolling. Let the pager settle first.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted || _scrolling || !_restoreAfterScroll) return;
          _restoreAfterScroll = false;
          _transform.value =
              _pageTransforms[widget.pageKey]?.clone() ?? Matrix4.identity();
        });
        WidgetsBinding.instance.ensureVisualUpdate();
      }
    }
    return false;
  }

  void _updateZoomState() {
    final zoomed =
        _transform.value.getMaxScaleOnAxis() > kComicReaderFitScale + 1e-6;
    if (zoomed != _zoomed) {
      setState(() => _zoomed = zoomed);
    }
  }

  void _onPointerDown(PointerDownEvent event) {
    _pointers.add(event.pointer);
    if (widget.zoomEnabled && _pointers.length == 2 && !_pinching) {
      // Stop the scrollable from claiming a drag as soon as a second finger
      // lands, even before the scale crosses its gesture threshold.
      _zoomAnimation.stop();
      _restoreAfterScroll = false;
      _pageSlide.value = 0;
      setState(() => _pinching = true);
    }
  }

  void _onPointerEnd(PointerEvent event) {
    _pointers.remove(event.pointer);
    if (_pinching && _pointers.isEmpty) {
      setState(() => _pinching = false);
    }
  }

  void _onInteractionStart(ScaleStartDetails details) {
    _dragDelta = Offset.zero;
    _pageSlide.stop();
    if (_zoomAnimation.isAnimating) {
      setState(_zoomAnimation.stop);
    }
  }

  bool _isNext(double offset) => widget.reverse ? offset > 0 : offset < 0;

  bool get _animate =>
      widget.animateZoom && !MediaQuery.disableAnimationsOf(context);

  void _onInteractionUpdate(ScaleUpdateDetails details) {
    if (!_zoomed || _pinching || details.scale != 1) return;
    final size = context.size!;
    final delta = details.focalPointDelta;
    final matrix = _transform.value;
    final translation = matrix.getTranslation();
    final travel = matrix.getMaxScaleOnAxis() - kComicReaderFitScale;
    _dragDelta += delta;

    // Use each movement to pan the image first. Only movement past its
    // edge slides the page, so reversing the drag closes the gap first.
    final proposed = Offset(translation.x, translation.y) +
        Offset(_pageSlide.value, 0) +
        delta;
    final pan = Offset(
      proposed.dx.clamp(-size.width * travel, 0),
      proposed.dy.clamp(-size.height * travel, 0),
    );
    _transform.value = matrix.clone()..setTranslationRaw(pan.dx, pan.dy, 0);
    final pageDrag = details.pointerCount == 1 &&
        (_pageSlide.value != 0 || _dragDelta.dx.abs() > _dragDelta.dy.abs());
    _pageSlide.value =
        pageDrag ? (proposed.dx - pan.dx).clamp(-size.width, size.width) : 0;
  }

  void _onInteractionEnd(ScaleEndDetails details) {
    final offset = _pageSlide.value;
    if (offset == 0 || details.pointerCount != 0) return;
    final extent = context.size!.width;
    final speed = details.velocity.pixelsPerSecond.dx;
    final fling = speed.sign == offset.sign && speed.abs() >= 450;
    final turn = _isNext(offset) ? widget.onNextPage : widget.onPreviousPage;
    if (turn == null ||
        (offset.abs() < extent / 3 && !(fling && offset.abs() > kTouchSlop))) {
      _settleSlide(0);
      return;
    }

    if (!_animate) {
      _pageSlide.value = 0;
      turn();
      return;
    }
    _settleSlide(offset.sign * extent).then((_) {
      if (!mounted) return;
      turn();
      // Chapter throttling or a failed jump can leave the same page active.
      // Give a successful jump a frame to update its page key first.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _pageSlide.value != 0 && !_pageSlide.isAnimating) {
          _settleSlide(0);
        }
      });
      WidgetsBinding.instance.ensureVisualUpdate();
    });
  }

  Future<void> _settleSlide(double offset) => _pageSlide.animateTo(
        offset,
        duration: _animate ? const Duration(milliseconds: 180) : Duration.zero,
        curve: Curves.easeOutCubic,
      );

  void _toggleZoom() {
    if (_pageSlide.value != 0) return;
    _restoreAfterScroll = false;
    final matrix = Matrix4.identity();
    if (!_zoomed) {
      final offset = _doubleTapPosition * (1 - kComicReaderDoubleTapScale);
      matrix
        ..translateByDouble(offset.dx, offset.dy, 0, 1)
        ..scaleByDouble(kComicReaderDoubleTapScale, kComicReaderDoubleTapScale,
            kComicReaderDoubleTapScale, 1);
    }
    if (!_animate) {
      _zoomAnimation.stop();
      _transform.value = matrix;
      return;
    }
    _zoomTransition = Matrix4Tween(begin: _transform.value, end: matrix)
        .chain(CurveTween(curve: Curves.easeInOutCubic))
        .animate(_zoomAnimation);
    _zoomAnimation.forward(from: 0);
  }

  Widget _withPageSlide(Widget child) {
    return LayoutBuilder(
      builder: (_, constraints) => ValueListenableBuilder<double>(
        valueListenable: _pageSlide,
        child: child,
        builder: (_, offset, child) {
          final extent = constraints.maxWidth;
          final preview =
              offset == 0 ? null : widget.previewBuilder?.call(_isNext(offset));
          return ClipRect(
            child: Stack(
              fit: StackFit.expand,
              children: [
                Transform.translate(
                  offset: Offset(offset, 0),
                  transformHitTests: false,
                  child: child!,
                ),
                if (preview != null)
                  IgnorePointer(
                    child: Transform.translate(
                      offset: Offset(offset - offset.sign * extent, 0),
                      child: ClipRect(
                        child: Transform(
                          transform: _pageTransforms[preview.pageKey] ??
                              Matrix4.identity(),
                          child: preview.child,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _decoratePage(Object pageKey, Widget child) {
    return ValueListenableBuilder<Matrix4>(
      valueListenable: _transform,
      child: child,
      builder: (_, matrix, child) {
        // The pager is at fit scale during a normal swipe. Paint each visible
        // page at its saved zoom until the viewport takes over after settling.
        final useSavedTransform =
            matrix.getMaxScaleOnAxis() <= kComicReaderFitScale + 1e-6 &&
                (pageKey != widget.pageKey || _restoreAfterScroll);
        return ClipRect(
          child: Transform(
            transform: (useSavedTransform ? _pageTransforms[pageKey] : null) ??
                Matrix4.identity(),
            alignment: Alignment.topLeft,
            child: child,
          ),
        );
      },
    );
  }

  @override
  void dispose() {
    _pageSlide.dispose();
    _zoomAnimation.dispose();
    _transform.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox.expand(
      child: Listener(
        onPointerDown: _onPointerDown,
        onPointerUp: _onPointerEnd,
        onPointerCancel: (event) {
          _pageSlide.value = 0;
          _onPointerEnd(event);
        },
        child: GestureDetector(
          onTapUp: (details) {
            if (_pinching || _pageSlide.value != 0) return;
            widget.onTap(details.localPosition.dx / context.size!.width);
          },
          onDoubleTapDown: widget.zoomEnabled
              ? (details) => _doubleTapPosition = details.localPosition
              : null,
          onDoubleTap: widget.zoomEnabled ? _toggleZoom : null,
          child: _withPageSlide(InteractiveViewer(
            alignment: Alignment.topLeft,
            transformationController: _transform,
            minScale: kComicReaderFitScale,
            maxScale: kComicReaderMaxScale,
            panEnabled: false,
            onInteractionStart: _onInteractionStart,
            onInteractionUpdate: _onInteractionUpdate,
            onInteractionEnd: _onInteractionEnd,
            // Keep mouse-wheel events with the scrollable at fit scale.
            scaleEnabled: widget.zoomEnabled && _pinching,
            child: NotificationListener<ScrollNotification>(
              onNotification: _onScroll,
              child: widget.builder(
                context,
                _zoomed || _pinching || _zoomAnimation.isAnimating,
                _decoratePage,
              ),
            ),
          )),
        ),
      ),
    );
  }
}
