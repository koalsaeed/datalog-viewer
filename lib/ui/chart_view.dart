import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/vehicle_log.dart';
import '../util/units.dart';
import 'minimap.dart';
import 'theme.dart';

const double kPadLeft = 16;
const double kPadRight = 16;
const double kPadTop = 16;
const double kPadBottom = 26;

/// A gap larger than this (seconds) breaks the trace instead of drawing a
/// straight line across missing samples.
const double kGapSeconds = 0.10;

class ChartView extends StatefulWidget {
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

  @override
  State<ChartView> createState() => _ChartViewState();
}

class _ChartViewState extends State<ChartView> {
  double _start = 0;
  double _end = 1;
  double _width = 1;

  double _spanAtGesture = 0;
  double _anchorTime = 0;

  @override
  void initState() {
    super.initState();
    _fit();
  }

  @override
  void didUpdateWidget(covariant ChartView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.log, widget.log)) _fit();
  }

  double get _minSpan {
    final duration = widget.log.duration;
    return math.max(duration / 2000, 0.05);
  }

  void _fit() {
    final duration = widget.log.duration;
    _start = 0;
    _end = duration > 0 ? duration : 1;
  }

  double _fractionAt(double dx) {
    final plotWidth = _width - kPadLeft - kPadRight;
    if (plotWidth <= 0) return 0;
    return ((dx - kPadLeft) / plotWidth).clamp(0.0, 1.0).toDouble();
  }

  double _timeAt(double dx) {
    return _start + _fractionAt(dx) * (_end - _start);
  }

  void _zoomBy(double factor) {
    final duration = widget.log.duration;
    if (duration <= 0) return;

    final span = _end - _start;
    final newSpan = (span * factor).clamp(_minSpan, duration).toDouble();
    final center = (_start + _end) / 2;
    final newStart = (center - newSpan / 2)
        .clamp(0.0, math.max(0.0, duration - newSpan))
        .toDouble();

    setState(() {
      _start = newStart;
      _end = newStart + newSpan;
    });
  }

  void _seekTo(double fraction) {
    final duration = widget.log.duration;
    if (duration <= 0) return;

    final span = _end - _start;
    final newStart = (fraction * duration - span / 2)
        .clamp(0.0, math.max(0.0, duration - span))
        .toDouble();

    setState(() {
      _start = newStart;
      _end = newStart + span;
    });
  }

  void _handleScaleUpdate(ScaleUpdateDetails details) {
    final duration = widget.log.duration;
    if (duration <= 0) return;

    final newSpan =
        (_spanAtGesture / details.scale).clamp(_minSpan, duration).toDouble();
    final fraction = _fractionAt(details.localFocalPoint.dx);
    final newStart = (_anchorTime - fraction * newSpan)
        .clamp(0.0, math.max(0.0, duration - newSpan))
        .toDouble();

    setState(() {
      _start = newStart;
      _end = newStart + newSpan;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              _width = constraints.maxWidth;

              return Stack(
                children: [
                  Positioned.fill(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTapUp: (details) {
                        final index = widget.log
                            .nearestIndex(_timeAt(details.localPosition.dx));
                        widget.onCursorChanged(index);
                      },
                      onDoubleTap: () => setState(_fit),
                      onScaleStart: (details) {
                        _spanAtGesture = _end - _start;
                        _anchorTime = _timeAt(details.localFocalPoint.dx);
                      },
                      onScaleUpdate: _handleScaleUpdate,
                      child: CustomPaint(
                        painter: _ChartPainter(
                          log: widget.log,
                          selected: widget.selected,
                          cursor: widget.cursor,
                          start: _start,
                          end: _end,
                        ),
                        child: widget.selected.isEmpty
                            ? const Center(
                                child: Text(
                                  'Pick a channel on the left',
                                  style:
                                      TextStyle(color: kMuted, fontSize: 13),
                                ),
                              )
                            : const SizedBox.expand(),
                      ),
                    ),
                  ),
                  Positioned(
                    top: 10,
                    right: 10,
                    child: _ZoomControls(
                      onZoomIn: () => _zoomBy(0.5),
                      onZoomOut: () => _zoomBy(2),
                      onFit: () => setState(_fit),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
        Minimap(
          log: widget.log,
          selected: widget.selected,
          start: _start,
          end: _end,
          onSeek: _seekTo,
        ),
      ],
    );
  }
}

class _ZoomControls extends StatelessWidget {
  const _ZoomControls({
    required this.onZoomIn,
    required this.onZoomOut,
    required this.onFit,
  });

  final VoidCallback onZoomIn;
  final VoidCallback onZoomOut;
  final VoidCallback onFit;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 34,
      decoration: BoxDecoration(
        color: kSurfaceAlt,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: kBorder),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _button(Icons.add, onZoomIn, 'Zoom in'),
          const SizedBox(height: 1, child: ColoredBox(color: kBorder)),
          _button(Icons.remove, onZoomOut, 'Zoom out'),
          const SizedBox(height: 1, child: ColoredBox(color: kBorder)),
          _button(Icons.crop_free, onFit, 'Fit'),
        ],
      ),
    );
  }

  Widget _button(IconData icon, VoidCallback onTap, String tooltip) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          width: 34,
          height: 32,
          child: Icon(icon, size: 16, color: kMuted),
        ),
      ),
    );
  }
}

class _ChartPainter extends CustomPainter {
  _ChartPainter({
    required this.log,
    required this.selected,
    required this.cursor,
    required this.start,
    required this.end,
  });

  final VehicleLog log;
  final List<int> selected;
  final int? cursor;
  final double start;
  final double end;

  @override
  void paint(Canvas canvas, Size size) {
    final plot = Rect.fromLTRB(
      kPadLeft,
      kPadTop,
      size.width - kPadRight,
      size.height - kPadBottom,
    );
    if (plot.width <= 1 || plot.height <= 1) return;

    final span = end - start;
    if (span <= 0) return;

    final gridPaint = Paint()
      ..color = kBorder
      ..strokeWidth = 1;

    for (var i = 0; i <= 4; i++) {
      final y = plot.top + plot.height * i / 4;
      canvas.drawLine(Offset(plot.left, y), Offset(plot.right, y), gridPaint);
    }
    for (var i = 0; i <= 4; i++) {
      final x = plot.left + plot.width * i / 4;
      canvas.drawLine(Offset(x, plot.top), Offset(x, plot.bottom), gridPaint);
    }

    if (log.sampleCount < 2) return;

    final from = log.nearestIndex(start);
    final to = log.nearestIndex(end);
    final visible = math.max(1, to - from + 1);
    final step = math.max(1, (visible / (plot.width * 2)).ceil());

    for (var slot = 0; slot < selected.length; slot++) {
      final channel = log.channels[selected[slot]];
      if (!channel.hasData) continue;

      final colour = kTraceColors[slot % kTraceColors.length];
      final range = channel.max - channel.min;

      final path = Path();
      var started = false;
      var lastTime = double.negativeInfinity;

      for (var i = from; i <= to; i += step) {
        final value = channel.values[i];
        final t = log.time[i];
        if (!value.isFinite || !t.isFinite) {
          started = false;
          continue;
        }
        if (t - lastTime > kGapSeconds) started = false;
        lastTime = t;

        final x =
            plot.left + ((t - start) / span).clamp(0.0, 1.0) * plot.width;
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

      canvas.drawPath(
        path,
        Paint()
          ..color = colour
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..isAntiAlias = true,
      );
    }

    _paintTimeAxis(canvas, plot, span);
    _paintCursor(canvas, plot, span);
  }

  void _paintTimeAxis(Canvas canvas, Rect plot, double span) {
    const style = TextStyle(color: kMuted, fontSize: 10);
    for (var i = 0; i <= 4; i++) {
      final label = formatClock(start + span * i / 4);
      final painter = TextPainter(
        text: TextSpan(text: label, style: style),
        textDirection: TextDirection.ltr,
      )..layout();
      final x = plot.left + plot.width * i / 4;
      painter.paint(canvas, Offset(x - painter.width / 2, plot.bottom + 6));
    }
  }

  void _paintCursor(Canvas canvas, Rect plot, double span) {
    final index = cursor;
    if (index == null || index < 0 || index >= log.sampleCount) return;

    final t = log.time[index];
    if (!t.isFinite || t < start || t > end) return;

    final x = plot.left + ((t - start) / span).clamp(0.0, 1.0) * plot.width;

    canvas.drawLine(
      Offset(x, plot.top),
      Offset(x, plot.bottom),
      Paint()
        ..color = const Color(0x99FFFFFF)
        ..strokeWidth = 1,
    );

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
        3.4,
        Paint()..color = kTraceColors[slot % kTraceColors.length],
      );
    }
  }

  @override
  bool shouldRepaint(covariant _ChartPainter oldDelegate) {
    return oldDelegate.cursor != cursor ||
        oldDelegate.start != start ||
        oldDelegate.end != end ||
        oldDelegate.log != log ||
        !_sameSelection(oldDelegate.selected, selected);
  }

  static bool _sameSelection(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
