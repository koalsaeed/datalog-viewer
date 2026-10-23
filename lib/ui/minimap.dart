import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/vehicle_log.dart';
import 'theme.dart';

/// Full-length overview strip that doubles as a scrollbar.
///
/// Dragging it pans the chart with one finger. Pressing inside the highlighted
/// window grabs it exactly where you touched; pressing outside centres the
/// window on your finger first, so a tap never jumps wildly.
class Minimap extends StatefulWidget {
  const Minimap({
    super.key,
    required this.log,
    required this.selected,
    required this.start,
    required this.end,
    required this.onSeekTo,
    required this.cursorTime,
    required this.locked,
    required this.onCursorTime,
  });

  final VehicleLog log;
  final List<int> selected;
  final double start;
  final double end;

  /// Called with the requested viewport start time (already offset-adjusted).
  final ValueChanged<double> onSeekTo;

  /// Position of the time cursor, in seconds, or null when there is none.
  final double? cursorTime;

  /// When locked, dragging pans the view instead of moving the cursor.
  final bool locked;

  final ValueChanged<double> onCursorTime;

  @override
  State<Minimap> createState() => _MinimapState();
}

class _MinimapState extends State<Minimap> {
  double _grab = 0;

  double get _span => widget.end - widget.start;

  int get _referenceChannel {
    if (widget.selected.isNotEmpty) return widget.selected.first;
    final rpm = widget.log.channels
        .indexWhere((channel) => channel.name.toLowerCase().contains('rpm'));
    if (rpm >= 0) return rpm;
    for (var i = 0; i < widget.log.channels.length; i++) {
      if (widget.log.channels[i].hasData) return i;
    }
    return 0;
  }

  void _begin(Offset local, double width) {
    final duration = widget.log.duration;
    if (duration <= 0 || width <= 0) return;

    final fraction = (local.dx / width).clamp(0.0, 1.0).toDouble();
    final t = fraction * duration;

    if (t < widget.start || t > widget.end) {
      // Outside the window: centre it under the finger.
      _grab = _span / 2;
    } else {
      _grab = t - widget.start;
    }
    _emit(t);
  }

  void _update(Offset local, double width) {
    final duration = widget.log.duration;
    if (duration <= 0 || width <= 0) return;

    final fraction = (local.dx / width).clamp(0.0, 1.0).toDouble();
    _emit(fraction * duration);
  }

  void _emit(double t) => widget.onSeekTo(t - _grab);

  double? _timeAt(double dx, double width) {
    final duration = widget.log.duration;
    if (duration <= 0 || width <= 0) return null;
    final fraction = (dx / width).clamp(0.0, 1.0).toDouble();
    return fraction * duration;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapUp: (details) {
            final t = _timeAt(details.localPosition.dx, width);
            if (t == null) return;
            if (widget.locked) {
              widget.onSeekTo(t - _span / 2);
            } else {
              widget.onCursorTime(t);
            }
          },
          onHorizontalDragStart: (details) {
            if (widget.locked) {
              _begin(details.localPosition, width);
            } else {
              final t = _timeAt(details.localPosition.dx, width);
              if (t != null) widget.onCursorTime(t);
            }
          },
          onHorizontalDragUpdate: (details) {
            if (widget.locked) {
              _update(details.localPosition, width);
            } else {
              final t = _timeAt(details.localPosition.dx, width);
              if (t != null) widget.onCursorTime(t);
            }
          },
          child: Container(
            height: 52,
            decoration: const BoxDecoration(
              color: kSurface,
              border: Border(top: BorderSide(color: kBorder)),
            ),
            child: CustomPaint(
              painter: _MinimapPainter(
                log: widget.log,
                channelIndex: _referenceChannel,
                start: widget.start,
                end: widget.end,
                cursorTime: widget.cursorTime,
              ),
            ),
          ),
        );
      },
    );
  }
}

class _MinimapPainter extends CustomPainter {
  _MinimapPainter({
    required this.log,
    required this.channelIndex,
    required this.start,
    required this.end,
    required this.cursorTime,
  });

  final VehicleLog log;
  final int channelIndex;
  final double start;
  final double end;
  final double? cursorTime;

  @override
  void paint(Canvas canvas, Size size) {
    final duration = log.duration;
    if (duration <= 0 || size.width <= 1) return;

    final channel = log.channels[channelIndex];
    final samples = log.sampleCount;

    if (channel.hasData && samples > 1) {
      final range = channel.max - channel.min;
      final paint = Paint()
        ..color = const Color(0x664EA1FF)
        ..strokeWidth = 1;

      final columns = size.width.floor();
      for (var x = 0; x < columns; x++) {
        final from = (x * samples / columns).floor();
        final to = math.min(samples, ((x + 1) * samples / columns).ceil());

        var low = double.infinity;
        var high = double.negativeInfinity;
        for (var i = from; i < to; i++) {
          final value = channel.values[i];
          if (!value.isFinite) continue;
          if (value < low) low = value;
          if (value > high) high = value;
        }
        if (!low.isFinite) continue;

        final normalisedLow =
            range <= 0 ? 0.5 : ((low - channel.min) / range).clamp(0.0, 1.0);
        final normalisedHigh =
            range <= 0 ? 0.5 : ((high - channel.min) / range).clamp(0.0, 1.0);
        final y1 =
            size.height - 4 - normalisedHigh.toDouble() * (size.height - 8);
        final y2 =
            size.height - 4 - normalisedLow.toDouble() * (size.height - 8);
        canvas.drawLine(
          Offset(x.toDouble(), y1),
          Offset(x.toDouble(), y2),
          paint,
        );
      }
    }

    final span = end - start;
    if (span <= 0) return;

    final left = (start / duration).clamp(0.0, 1.0).toDouble() * size.width;
    final right = (end / duration).clamp(0.0, 1.0).toDouble() * size.width;

    canvas.drawRect(
      Rect.fromLTRB(left, 0, right, size.height),
      Paint()..color = const Color(0x1A4EA1FF),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTRB(left + 1, 1, math.max(left + 2, right - 1), size.height - 1),
        const Radius.circular(3),
      ),
      Paint()
        ..color = const Color(0xCC4EA1FF)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );

    final cursor = cursorTime;
    if (cursor != null && cursor.isFinite) {
      final cx = (cursor / duration).clamp(0.0, 1.0).toDouble() * size.width;
      canvas.drawLine(
        Offset(cx, 0),
        Offset(cx, size.height),
        Paint()
          ..color = const Color(0xFFFFFFFF)
          ..strokeWidth = 1.5,
      );
      final thumbY = size.height / 2;
      canvas.drawCircle(
        Offset(cx, thumbY),
        5.5,
        Paint()..color = const Color(0xFFFFFFFF),
      );
      canvas.drawCircle(
        Offset(cx, thumbY),
        5.5,
        Paint()
          ..color = const Color(0xFF0B0E13)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _MinimapPainter oldDelegate) {
    return oldDelegate.start != start ||
        oldDelegate.end != end ||
        oldDelegate.log != log ||
        oldDelegate.cursorTime != cursorTime ||
        oldDelegate.channelIndex != channelIndex;
  }
}
