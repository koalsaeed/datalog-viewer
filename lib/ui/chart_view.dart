import 'dart:math' as math;

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';

import '../models/vehicle_log.dart';
import '../util/units.dart';
import 'theme.dart';

const double kPadLeft = 14;
const double kPadRight = 14;
const double kPadTop = 14;
const double kPadBottom = 30;

/// A gap larger than this (seconds) breaks the trace instead of drawing a
/// straight line across missing samples. A fake line looks like a real event
/// and misleads tuning decisions.
const double kGapSeconds = 0.10;

class ChartView extends StatelessWidget {
  const ChartView({
    super.key,
    required this.log,
    required this.selected,
    required this.cursor,
    required this.onCursorChanged,
  });

  final VehicleLog log;
  final List<int> selected;
  final int? cursor;
  final ValueChanged<int> onCursorChanged;

  int? _indexAt(double dx, double width) {
    final plotWidth = width - kPadLeft - kPadRight;
    if (plotWidth <= 0 || log.sampleCount == 0) return null;
    final fraction = ((dx - kPadLeft) / plotWidth).clamp(0.0, 1.0);
    return (fraction * (log.sampleCount - 1)).round();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (details) {
            final index = _indexAt(details.localPosition.dx, constraints.maxWidth);
            if (index != null) onCursorChanged(index);
          },
          onHorizontalDragUpdate: (details) {
            final index = _indexAt(details.localPosition.dx, constraints.maxWidth);
            if (index != null) onCursorChanged(index);
          },
          child: Stack(
            children: [
              Positioned.fill(
                child: CustomPaint(
                  painter: _ChartPainter(
                    log: log,
                    selected: selected,
                    cursor: cursor,
                  ),
                ),
              ),
              if (selected.isEmpty)
                const Center(
                  child: Text(
                    'Pick a channel on the left',
                    style: TextStyle(color: kMuted, fontSize: 13),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _ChartPainter extends CustomPainter {
  _ChartPainter({
    required this.log,
    required this.selected,
    required this.cursor,
  });

  final VehicleLog log;
  final List<int> selected;
  final int? cursor;

  @override
  void paint(Canvas canvas, Size size) {
    final plot = Rect.fromLTRB(
      kPadLeft,
      kPadTop,
      size.width - kPadRight,
      size.height - kPadBottom,
    );
    if (plot.width <= 1 || plot.height <= 1) return;

    final gridPaint = Paint()
      ..color = kBorder
      ..strokeWidth = 1;
    for (var i = 0; i <= 4; i++) {
      final y = plot.top + plot.height * i / 4;
      canvas.drawLine(Offset(plot.left, y), Offset(plot.right, y), gridPaint);
    }

    final duration = log.duration;
    if (duration <= 0) return;

    for (var slot = 0; slot < selected.length; slot++) {
      final channel = log.channels[selected[slot]];
      if (!channel.hasData) continue;

      final paint = Paint()
        ..color = kTraceColors[slot % kTraceColors.length]
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4
        ..isAntiAlias = true;

      final range = channel.max - channel.min;
      // Keep at most ~2 samples per pixel.
      final step = math.max(1, (log.sampleCount / (plot.width * 2)).ceil());

      final path = Path();
      var started = false;
      var lastTime = double.negativeInfinity;

      for (var i = 0; i < log.sampleCount; i += step) {
        final value = channel.values[i];
        final t = log.time[i];
        if (!value.isFinite || !t.isFinite) {
          started = false;
          continue;
        }
        if (t - lastTime > kGapSeconds) started = false;
        lastTime = t;

        final x = plot.left + (t / duration).clamp(0.0, 1.0) * plot.width;
        final normalised =
            range <= 0 ? 0.5 : ((value - channel.min) / range).clamp(0.0, 1.0);
        final y = plot.bottom - normalised * plot.height;

        if (started) {
          path.lineTo(x, y);
        } else {
          path.moveTo(x, y);
          started = true;
        }
      }

      canvas.drawPath(path, paint);
    }

    _paintTimeAxis(canvas, plot, duration);
    _paintCursor(canvas, plot, duration);
  }

  void _paintTimeAxis(Canvas canvas, Rect plot, double duration) {
    const style = TextStyle(color: kMuted, fontSize: 10);
    for (var i = 0; i <= 4; i++) {
      final label = formatClock(duration * i / 4);
      final painter = TextPainter(
        text: TextSpan(text: label, style: style),
        textDirection: TextDirection.ltr,
      )..layout();
      final x = plot.left + plot.width * i / 4;
      painter.paint(canvas, Offset(x - painter.width / 2, plot.bottom + 6));
    }
  }

  void _paintCursor(Canvas canvas, Rect plot, double duration) {
    final index = cursor;
    if (index == null || index < 0 || index >= log.sampleCount) return;

    final t = log.time[index];
    if (!t.isFinite) return;

    final x = plot.left + (t / duration).clamp(0.0, 1.0) * plot.width;
    final linePaint = Paint()
      ..color = const Color(0x8CFFFFFF)
      ..strokeWidth = 1;
    canvas.drawLine(Offset(x, plot.top), Offset(x, plot.bottom), linePaint);

    for (var slot = 0; slot < selected.length; slot++) {
      final channel = log.channels[selected[slot]];
      if (!channel.hasData) continue;

      final value = channel.values[index];
      if (!value.isFinite) continue;

      final range = channel.max - channel.min;
      final normalised =
          range <= 0 ? 0.5 : ((value - channel.min) / range).clamp(0.0, 1.0);
      final y = plot.bottom - normalised * plot.height;

      canvas.drawCircle(
        Offset(x, y),
        3.2,
        Paint()..color = kTraceColors[slot % kTraceColors.length],
      );
    }
  }

  @override
  bool shouldRepaint(covariant _ChartPainter oldDelegate) {
    return oldDelegate.cursor != cursor ||
        oldDelegate.log != log ||
        !listEquals(oldDelegate.selected, selected);
  }
}
