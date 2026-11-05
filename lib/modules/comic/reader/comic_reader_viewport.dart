import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:zai_x/modules/comic/reader/comic_reader_pan.dart';

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
  final _pan = ComicReaderPan();
  late final ComicReaderPanMomentum _momentum;
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
    _momentum = ComicReaderPanMomentum(this, _setPanPosition);
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
      _pan.cancel();
      _momentum.stop();
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
    _momentum.stop();
    _pointers.add(event.pointer);
    if (_zoomed && widget.zoomEnabled && _pointers.length == 1) {
      _dragDelta = Offset.zero;
      _pan.begin(event, MediaQuery.maybeGestureSettingsOf(context));
    }
    if (widget.zoomEnabled && _pointers.length == 2 && !_pinching) {
      // Stop the scrollable from claiming a drag as soon as a second finger
      // lands, even before the scale crosses its gesture threshold.
      _zoomAnimation.stop();
      _pan.cancel();
      _restoreAfterScroll = false;
      _pageSlide.value = 0;
      setState(() => _pinching = true);
    }
  }

  void _onPointerMove(PointerMoveEvent event) {
    final delta = _pan.update(event);
    if (delta == null) return;
    _stopZoomAnimation();
    _pageSlide.stop();
    _dragDelta += delta;
    _dragPan(delta,
        canSlide:
            _pageSlide.value != 0 || _dragDelta.dx.abs() > _dragDelta.dy.abs());
  }

  void _onPointerUp(PointerUpEvent event) {
    final velocity = _pan.end(event);
    _onPointerEnd(event);
    if (velocity != null) _finishDrag(velocity);
  }

  void _onPointerEnd(PointerEvent event) {
    _pointers.remove(event.pointer);
    if (_pinching && _pointers.isEmpty) {
      setState(() => _pinching = false);
    }
  }

  void _stopZoomAnimation() {
    if (_zoomAnimation.isAnimating) {
      setState(_zoomAnimation.stop);
    }
  }

  bool _isNext(double offset) => widget.reverse ? offset > 0 : offset < 0;

  bool get _animate =>
      widget.animateZoom && !MediaQuery.disableAnimationsOf(context);

  void _onInteractionUpdate(ScaleUpdateDetails details) {
    // Pointer drags are handled from the first movement. The viewer still
    // handles pinches and supplies trackpad deltas without a down event.
    if (_zoomed && _pointers.isEmpty && details.scale == 1) {
      _dragPan(details.focalPointDelta, canSlide: false);
    }
  }

  Offset get _panPosition {
    final position = _transform.value.getTranslation();
    return Offset(position.x, position.y);
  }

  Offset _minimumPan(Size size) {
    final travel = kComicReaderFitScale - _transform.value.getMaxScaleOnAxis();
    return Offset(size.width * travel, size.height * travel);
  }

  void _setPanPosition(Offset position) {
    if (position == _panPosition) return;
    _transform.value = _transform.value.clone()
      ..setTranslationRaw(position.dx, position.dy, 0);
  }

  void _dragPan(Offset delta, {required bool canSlide}) {
    final size = context.size!;
    final minimum = _minimumPan(size);
    // Use each movement to pan the image first. Only movement past its
    // edge slides the page, so reversing the drag closes the gap first.
    final proposed = _panPosition + Offset(_pageSlide.value, 0) + delta;
    final pan = Offset(
      proposed.dx.clamp(minimum.dx, 0),
      proposed.dy.clamp(minimum.dy, 0),
    );
    _setPanPosition(pan);
    final slide =
        canSlide ? (proposed.dx - pan.dx).clamp(-size.width, size.width) : 0.0;
    if (slide != _pageSlide.value) _pageSlide.value = slide;
  }

  void _finishDrag(Offset velocity) {
    final offset = _pageSlide.value;
    if (offset == 0) {
      if (_animate && _zoomed) {
        _momentum.fling(_panPosition, velocity, _minimumPan(context.size!));
      }
      return;
    }
    final extent = context.size!.width;
    final speed = velocity.dx;
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
      builder: (_, constraints) {
        final previews = <bool, ({Object pageKey, Widget child})?>{};
        return ValueListenableBuilder<double>(
          valueListenable: _pageSlide,
          child: child,
          builder: (_, offset, child) {
            final extent = constraints.maxWidth;
            final next = _isNext(offset);
            final preview = offset == 0
                ? null
                : previews.putIfAbsent(
                    next, () => widget.previewBuilder?.call(next));
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
        );
      },
    );
  }

  Widget _decoratePage(Object pageKey, Widget child) {
    // The pager is at fit scale during a normal swipe. Paint each visible
    // page at its saved zoom until the viewport takes over after settling.
    final saved = !_zoomed && (pageKey != widget.pageKey || _restoreAfterScroll)
        ? _pageTransforms[pageKey]
        : null;
    return ClipRect(
      child: Transform(
        transform: saved ?? Matrix4.identity(),
        alignment: Alignment.topLeft,
        child: child,
      ),
    );
  }

  @override
  void dispose() {
    _momentum.dispose();
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
        onPointerMove: _onPointerMove,
        onPointerUp: _onPointerUp,
        onPointerCancel: (event) {
          _pan.cancel();
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
            onInteractionStart: (_) => _stopZoomAnimation(),
            onInteractionUpdate: _onInteractionUpdate,
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
