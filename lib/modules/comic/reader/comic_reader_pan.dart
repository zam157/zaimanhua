import 'package:flutter/gestures.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/scheduler.dart';

/// Tracks one finger from pointer down, including the movement before slop.
class ComicReaderPan {
  ComicReaderPan({this.horizontalOnly = false});

  final bool horizontalOnly;
  int? _pointer;
  VelocityTracker? _velocity;
  Offset _lastPosition = Offset.zero;
  Duration _lastSample = Duration.zero;
  double _slop = kTouchSlop;
  bool _dragging = false;

  void begin(PointerDownEvent event, DeviceGestureSettings? settings) {
    if (event.buttons != kPrimaryButton) return;
    _pointer = event.pointer;
    _lastPosition = event.localPosition;
    _lastSample = event.timeStamp;
    _slop = computeHitSlop(event.kind, settings);
    _dragging = false;
    _velocity = VelocityTracker.withKind(event.kind)
      ..addPosition(event.timeStamp, event.localPosition);
  }

  Offset? update(PointerMoveEvent event) {
    if (event.pointer != _pointer) return null;
    if (!event.synthesized) {
      _lastSample = event.timeStamp;
      _velocity!.addPosition(event.timeStamp, event.localPosition);
    }
    final delta = event.localPosition - _lastPosition;
    if (!_dragging) {
      if (delta.distance <= _slop) return null;
      if (horizontalOnly && delta.dx.abs() <= delta.dy.abs()) {
        cancel();
        return null;
      }
      _dragging = true;
    }
    _lastPosition = event.localPosition;
    return horizontalOnly ? Offset(delta.dx, 0) : delta;
  }

  Offset? end(PointerUpEvent event) {
    if (event.pointer != _pointer) return null;
    final recent =
        event.timeStamp - _lastSample <= const Duration(milliseconds: 50);
    final velocity = !_dragging
        ? null
        : recent
            ? _velocity!.getVelocity().pixelsPerSecond
            : Offset.zero;
    cancel();
    return velocity;
  }

  void cancel() {
    _pointer = null;
    _velocity = null;
    _dragging = false;
  }
}

/// Continues panning after release, decelerating within the image bounds.
class ComicReaderPanMomentum {
  ComicReaderPanMomentum(TickerProvider vsync, this.onPosition) {
    _ticker = vsync.createTicker(_tick);
  }

  final void Function(Offset) onPosition;
  late final Ticker _ticker;
  late FrictionSimulation _horizontal;
  late FrictionSimulation _vertical;
  Offset _minimum = Offset.zero;

  void fling(Offset position, Offset velocity, Offset minimum) {
    stop();
    if (velocity.distance < kMinFlingVelocity) return;
    _minimum = minimum;
    _horizontal = _simulation(position.dx, velocity.dx);
    _vertical = _simulation(position.dy, velocity.dy);
    _ticker.start();
  }

  FrictionSimulation _simulation(double position, double velocity) =>
      FrictionSimulation(
        0.003,
        position,
        velocity.clamp(-kMaxFlingVelocity, kMaxFlingVelocity),
        tolerance: const Tolerance(velocity: 20),
      );

  void _tick(Duration elapsed) {
    final time = elapsed.inMicroseconds / Duration.microsecondsPerSecond;
    final x = _horizontal.x(time);
    final y = _vertical.x(time);
    final clampedX = x.clamp(_minimum.dx, 0).toDouble();
    final clampedY = y.clamp(_minimum.dy, 0).toDouble();
    onPosition(Offset(clampedX, clampedY));
    if ((x != clampedX || _horizontal.isDone(time)) &&
        (y != clampedY || _vertical.isDone(time))) {
      stop();
    }
  }

  void stop() => _ticker.stop();

  void dispose() => _ticker.dispose();
}
