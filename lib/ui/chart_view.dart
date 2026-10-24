import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/vehicle_log.dart';
import '../util/units.dart';
import 'minimap.dart';
import 'stats_bar.dart';
import 'theme.dart';

const double kPadLeft = 16;
const double kPadRight = 16;
const double kPadTop = 22;
const double kPadBottom = 26;

/// Where the min / max readout lives relative to the chart.
enum StatsDock { bottom, left, right }

class ChartView extends StatefulWidget {
  const ChartView({
    super.key,
    required this.log,
    required this.selected,
    required this.cursor,
    required this.onCursorChanged,
    this.showStats = false,
    this.showTags = true,
    this.highlighted,
    this.laneMode = false,
    this.statsDock = StatsDock.bottom,
    this.cursorLocked = false,
    this.onToggleLock,
    this.aliases = const <int, String>{},
    this.initialStart,
    this.initialEnd,
    this.onViewport,
    this.onEditChannels,
  });

  final VehicleLog log;
  final List<int> selected;
  final int? cursor;
  final ValueChanged<int> onCursorChanged;
  final bool showStats;
  final bool showTags;

  /// Channel index to emphasise; everything else is dimmed.
  final int? highlighted;

  /// When true each channel gets its own band with a real value scale.
  final bool laneMode;

  final StatsDock statsDock;

  /// Freezes the cursor: dragging pans the view instead of scrubbing.
  final bool cursorLocked;

  final VoidCallback? onToggleLock;

  /// Custom display names for channels.
  final Map<int, String> aliases;

  /// Restores the viewport when this widget is rebuilt from scratch.
  final double? initialStart;
  final double? initialEnd;
  final void Function(double start, double end)? onViewport;
  final VoidCallback? onEditChannels;

  @override
  State<ChartView> createState() => _ChartViewState();
}

class _ChartViewState extends State<ChartView> {
  double _start = 0;
  double _end = 1;
  double _width = 1;
  double _chartHeight = 1;

  // Vertical window in normalised units: 0 = channel minimum, 1 = maximum.
  double _yTop = 0;
  double _ySpan = 1;

  double _spanAtGesture = 0;
  double _anchorTime = 0;
  double _ySpanAtGesture = 1;
  double _anchorNorm = 0;
  bool _panZoomActive = false;
  bool _gestureHadTwoFingers = false;
  double? _lastPanX;

  @override
  void initState() {
    super.initState();
    final savedStart = widget.initialStart;
    final savedEnd = widget.initialEnd;
    if (savedStart != null &&
        savedEnd != null &&
        savedEnd > savedStart &&
        savedEnd <= widget.log.duration + 0.001) {
      _start = savedStart;
      _end = savedEnd;
    } else {
      _fit();
    }
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
    _yTop = 0;
    _ySpan = 1;
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

    // Zoom around whatever the user is reading: the cursor when it is in view.
    var anchor = (_start + _end) / 2;
    final cursor = widget.cursor;
    if (cursor != null && cursor >= 0 && cursor < widget.log.sampleCount) {
      final t = widget.log.time[cursor];
      if (t.isFinite && t >= _start && t <= _end) anchor = t;
    }

    final fraction = ((anchor - _start) / span).clamp(0.0, 1.0).toDouble();
    final newStart = (anchor - fraction * newSpan)
        .clamp(0.0, math.max(0.0, duration - newSpan))
        .toDouble();

    setState(() {
      _start = newStart;
      _end = newStart + newSpan;
    });
  }

  void _panBySeconds(double seconds) {
    final duration = widget.log.duration;
    if (duration <= 0) return;

    final span = _end - _start;
    final newStart = (_start + seconds)
        .clamp(0.0, math.max(0.0, duration - span))
        .toDouble();

    if (newStart == _start) return;
    setState(() {
      _start = newStart;
      _end = newStart + span;
    });
  }

  void _seekToStart(double requested) {
    final duration = widget.log.duration;
    if (duration <= 0) return;

    final span = _end - _start;
    final newStart =
        requested.clamp(0.0, math.max(0.0, duration - span)).toDouble();

    setState(() {
      _start = newStart;
      _end = newStart + span;
    });
  }

  double _verticalFraction(double dy) {
    final plotHeight = math.max(1.0, _chartHeight - kPadTop - kPadBottom);
    return ((dy - kPadTop) / plotHeight).clamp(0.0, 1.0).toDouble();
  }

  void _beginPanZoom(double dx, double dy) {
    _spanAtGesture = _end - _start;
    _anchorTime = _timeAt(dx);
    _ySpanAtGesture = _ySpan;
    _anchorNorm = _yTop + _verticalFraction(dy) * _ySpan;
    _panZoomActive = true;
  }

  void _onScaleUpdate(ScaleUpdateDetails details) {
    // One finger scrubs the cursor unless the cursor is locked, in which case
    // it pans the view like a scroll.
    if (details.pointerCount < 2) {
      if (_gestureHadTwoFingers) return;
      if (widget.cursorLocked) {
        _panWithFinger(details.localFocalPoint.dx);
        return;
      }
      final index =
          widget.log.nearestIndex(_timeAt(details.localFocalPoint.dx));
      if (index != widget.cursor) widget.onCursorChanged(index);
      return;
    }

    _gestureHadTwoFingers = true;
    _lastPanX = null;
    if (!_panZoomActive) {
      _beginPanZoom(details.localFocalPoint.dx, details.localFocalPoint.dy);
    }

    final duration = widget.log.duration;
    if (duration <= 0) return;

    final newSpan =
        (_spanAtGesture / details.scale).clamp(_minSpan, duration).toDouble();
    final fraction = _fractionAt(details.localFocalPoint.dx);
    final newStart = (_anchorTime - fraction * newSpan)
        .clamp(0.0, math.max(0.0, duration - newSpan))
        .toDouble();

    // Vertical pinch zooms the value axis the same way horizontal pinch zooms
    // the time axis.
    final newYSpan =
        (_ySpanAtGesture / details.verticalScale).clamp(0.08, 3.0).toDouble();
    final fy = _verticalFraction(details.localFocalPoint.dy);
    var newYTop = _anchorNorm - fy * newYSpan;
    final minTop = math.min(0.0, 1.0 - newYSpan);
    final maxTop = math.max(0.0, 1.0 - newYSpan);
    newYTop = newYTop.clamp(minTop, maxTop).toDouble();

    setState(() {
      _start = newStart;
      _end = newStart + newSpan;
      _yTop = newYTop;
      _ySpan = newYSpan;
    });
  }

  void _onScaleEnd(ScaleEndDetails details) {
    _panZoomActive = false;
    _gestureHadTwoFingers = false;
    _lastPanX = null;
  }

  void _panWithFinger(double x) {
    final duration = widget.log.duration;
    if (duration <= 0) return;

    final plotWidth = _width - kPadLeft - kPadRight;
    if (plotWidth <= 0) return;

    final previous = _lastPanX;
    _lastPanX = x;
    if (previous == null) return;

    final span = _end - _start;
    final seconds = -(x - previous) / plotWidth * span;
    final newStart = (_start + seconds)
        .clamp(0.0, math.max(0.0, duration - span))
        .toDouble();

    if (newStart == _start) return;
    setState(() {
      _start = newStart;
      _end = newStart + span;
    });
  }

  /// Moves the cursor from the minimap and scrolls the view along with it.
  void _setCursorFromTime(double t) {
    final index = widget.log.nearestIndex(t);
    if (index != widget.cursor) widget.onCursorChanged(index);

    final duration = widget.log.duration;
    if (duration <= 0) return;

    final span = _end - _start;
    var newStart = _start;
    if (t > _end) {
      newStart = t - span;
    } else if (t < _start) {
      newStart = t;
    }
    newStart =
        newStart.clamp(0.0, math.max(0.0, duration - span)).toDouble();

    if (newStart == _start) return;
    setState(() {
      _start = newStart;
      _end = newStart + span;
    });
  }

  @override
  Widget build(BuildContext context) {
    widget.onViewport?.call(_start, _end);

    final chart = Expanded(
      child: LayoutBuilder(
        builder: (context, constraints) {
          _width = constraints.maxWidth;
          _chartHeight = constraints.maxHeight;

          return Stack(
            children: [
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTapUp: (details) {
                    if (widget.cursorLocked) return;
                    final index = widget.log
                        .nearestIndex(_timeAt(details.localPosition.dx));
                    widget.onCursorChanged(index);
                  },
                  onDoubleTap: () => setState(_fit),
                  onScaleStart: (_) {
                    _panZoomActive = false;
                    _gestureHadTwoFingers = false;
                    _lastPanX = null;
                  },
                  onScaleUpdate: _onScaleUpdate,
                  onScaleEnd: _onScaleEnd,
                  child: CustomPaint(
                    painter: _ChartPainter(
                      log: widget.log,
                      selected: widget.selected,
                      cursor: widget.cursor,
                      start: _start,
                      end: _end,
                      showTags: widget.showTags,
                      highlighted: widget.highlighted,
                      yTop: _yTop,
                      ySpan: _ySpan,
                      laneMode: widget.laneMode,
                      aliases: widget.aliases,
                    ),
                    child: widget.selected.isEmpty
                        ? const Center(
                            child: Text(
                              'Pick a channel on the left',
                              style: TextStyle(color: kMuted, fontSize: 13),
                            ),
                          )
                        : widget.log.duration <= 0
                            ? const Center(
                                child: Text(
                                  'No time range in this log',
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
                  locked: widget.cursorLocked,
                  onToggleLock: widget.onToggleLock,
                  onZoomIn: () => _zoomBy(0.5),
                  onZoomOut: () => _zoomBy(2),
                  onFit: () => setState(_fit),
                ),
              ),
            ],
          );
        },
      ),
    );

    final duration = widget.log.duration;
    final minimap = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Minimap(
          log: widget.log,
          selected: widget.selected,
          start: _start,
          end: _end,
          onSeekTo: _seekToStart,
          cursorTime:
              widget.cursor == null ? null : widget.log.time[widget.cursor!],
          locked: widget.cursorLocked,
          onCursorTime: _setCursorFromTime,
        ),
        _PanBar(
          centerFraction:
              duration <= 0 ? 0.5 : ((_start + _end) / 2) / duration,
          spanFraction: duration <= 0 ? 1 : (_end - _start) / duration,
          onPanBy: (fractionOfLog) =>
              _panBySeconds(fractionOfLog * duration),
          onStep: (direction) =>
              _panBySeconds(direction * (_end - _start) * 0.5),
        ),
      ],
    );

    if (!widget.showStats) {
      return Column(children: [chart, minimap]);
    }

    if (widget.statsDock == StatsDock.bottom) {
      return Column(
        children: [
          chart,
          StatsBar(
            log: widget.log,
            selected: widget.selected,
            start: _start,
            end: _end,
            cursor: widget.cursor,
            aliases: widget.aliases,
          ),
          minimap,
        ],
      );
    }

    final side = StatsSide(
      log: widget.log,
      selected: widget.selected,
      start: _start,
      end: _end,
      cursor: widget.cursor,
      borderRight: widget.statsDock == StatsDock.left,
      aliases: widget.aliases,
      onEdit: widget.onEditChannels,
    );

    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.statsDock == StatsDock.left) side,
        Expanded(child: Column(children: [chart, minimap])),
        if (widget.statsDock == StatsDock.right) side,
      ],
    );
  }
}

class _PanBar extends StatelessWidget {
  const _PanBar({
    required this.centerFraction,
    required this.spanFraction,
    required this.onPanBy,
    required this.onStep,
  });

  final double centerFraction;
  final double spanFraction;

  /// Called with a shift expressed as a fraction of the whole log.
  final ValueChanged<double> onPanBy;

  /// -1 = back, +1 = forward, by half a screen.
  final ValueChanged<int> onStep;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 38,
      decoration: const BoxDecoration(
        color: kSurface,
        border: Border(top: BorderSide(color: kBorder)),
      ),
      child: Row(
        children: [
          _button(Icons.chevron_left, () => onStep(-1)),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final width = constraints.maxWidth;
                final span = spanFraction.clamp(0.02, 1.0).toDouble();
                final left =
                    (centerFraction - span / 2).clamp(0.0, 1.0 - span).toDouble();
                final trackWidth = math.max(0.0, width - 12);
                final windowWidth =
                    (span * trackWidth).clamp(18.0, math.max(18.0, trackWidth));

                return GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onHorizontalDragUpdate: (details) {
                    if (width <= 0) return;
                    onPanBy(details.delta.dx / width);
                  },
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: Center(
                          child: Container(
                            height: 3,
                            margin: const EdgeInsets.symmetric(horizontal: 6),
                            color: kBorder,
                          ),
                        ),
                      ),
                      Positioned(
                        left: 6 + left * trackWidth,
                        width: windowWidth.toDouble(),
                        top: 9,
                        bottom: 9,
                        child: Container(
                          decoration: BoxDecoration(
                            color: const Color(0x334EA1FF),
                            border: Border.all(color: kAccent, width: 1),
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
          _button(Icons.chevron_right, () => onStep(1)),
        ],
      ),
    );
  }

  Widget _button(IconData icon, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      child: SizedBox(
        width: 44,
        height: 38,
        child: Icon(icon, size: 20, color: kMuted),
      ),
    );
  }
}

class _ZoomControls extends StatelessWidget {
  const _ZoomControls({
    required this.locked,
    required this.onToggleLock,
    required this.onZoomIn,
    required this.onZoomOut,
    required this.onFit,
  });

  final bool locked;
  final VoidCallback? onToggleLock;
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
          _button(
            locked ? Icons.lock : Icons.lock_open,
            onToggleLock,
            locked ? 'Unlock cursor' : 'Lock cursor',
            active: locked,
          ),
          const SizedBox(height: 1, child: ColoredBox(color: kBorder)),
          _button(Icons.add, onZoomIn, 'Zoom in'),
          const SizedBox(height: 1, child: ColoredBox(color: kBorder)),
          _button(Icons.remove, onZoomOut, 'Zoom out'),
          const SizedBox(height: 1, child: ColoredBox(color: kBorder)),
          _button(Icons.crop_free, onFit, 'Fit'),
        ],
      ),
    );
  }

  Widget _button(
    IconData icon,
    VoidCallback? onTap,
    String tooltip, {
    bool active = false,
  }) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          width: 34,
          height: 32,
          child: Icon(icon, size: 16, color: active ? kAccent : kMuted),
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
    required this.showTags,
    required this.highlighted,
    required this.yTop,
    required this.ySpan,
    required this.laneMode,
    required this.aliases,
  });

  final VehicleLog log;
  final List<int> selected;
  final int? cursor;
  final double start;
  final double end;
  final bool showTags;
  final int? highlighted;
  final double yTop;
  final double ySpan;
  final bool laneMode;
  final Map<int, String> aliases;

  String _labelFor(int channelIndex) {
    final alias = aliases[channelIndex];
    if (alias != null && alias.trim().isNotEmpty) return alias;
    return log.channels[channelIndex].name;
  }

  /// Vertical slot for one trace: the whole plot when overlaying, or its own
  /// band when stacking.
  Rect _areaFor(int slot, Rect plot) {
    if (!laneMode || selected.isEmpty) return plot;
    final count = selected.length;
    final height = plot.height / count;
    final top = plot.top + slot * height;
    final pad = height >= 60
        ? 10.0
        : height >= 40
            ? 6.0
            : 3.0;
    final inset = math.max(2.0, height - pad * 2);
    return Rect.fromLTRB(plot.left, top + pad, plot.right, top + pad + inset);
  }

  double _yForValue(LogChannel channel, double value, Rect plot) {
    final range = channel.max - channel.min;
    final norm = range <= 0 ? 0.5 : (value - channel.min) / range;
    final frac = (norm - yTop) / ySpan;
    return plot.bottom - frac * plot.height;
  }

  bool _isVisible(LogChannel channel, double value) {
    final range = channel.max - channel.min;
    final norm = range <= 0 ? 0.5 : (value - channel.min) / range;
    return norm >= yTop - 0.02 && norm <= yTop + ySpan + 0.02;
  }

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

    if (!laneMode) {
      for (var i = 0; i <= 4; i++) {
        final y = plot.top + plot.height * i / 4;
        canvas.drawLine(Offset(plot.left, y), Offset(plot.right, y), gridPaint);
      }
    }
    for (var i = 0; i <= 4; i++) {
      final x = plot.left + plot.width * i / 4;
      canvas.drawLine(Offset(x, plot.top), Offset(x, plot.bottom), gridPaint);
    }

    if (log.sampleCount < 2) return;

    final from = log.nearestIndex(start);
    final to = log.nearestIndex(end);

    if (laneMode) _paintLaneFrames(canvas, plot);

    // Dimmed traces first so the emphasised one sits on top.
    for (var slot = 0; slot < selected.length; slot++) {
      if (highlighted != null && selected[slot] == highlighted) continue;
      _drawTrace(canvas, plot, span, slot, from, to,
          area: _areaFor(slot, plot),
          opacity: highlighted == null ? 1.0 : 0.18);
    }
    for (var slot = 0; slot < selected.length; slot++) {
      if (highlighted == null || selected[slot] != highlighted) continue;
      _drawTrace(canvas, plot, span, slot, from, to,
          area: _areaFor(slot, plot), opacity: 1.0, width: 2.2);
    }

    _paintTimeAxis(canvas, plot, span);
    _paintCursor(canvas, plot, span);

    if (showTags) _paintTags(canvas, plot, span);
  }

  void _paintLaneFrames(Canvas canvas, Rect plot) {
    final count = selected.length;
    if (count == 0) return;

    final height = plot.height / count;

    for (var slot = 0; slot < count; slot++) {
      final top = plot.top + slot * height;

      if (slot > 0) {
        canvas.drawLine(
          Offset(plot.left, top),
          Offset(plot.right, top),
          Paint()
            ..color = kBorder
            ..strokeWidth = 1,
        );
      }

      final channel = log.channels[selected[slot]];
      final colour = kTraceColors[slot % kTraceColors.length];
      final dim = highlighted != null && selected[slot] != highlighted;
      final labelColour = dim ? colour.withAlpha(80) : colour;

      _label(
        canvas,
        _labelFor(selected[slot]),
        Offset(plot.left + 2, top + 4),
        labelColour,
        9.5,
      );

      final range = channel.max - channel.min;
      if (height >= 44 && range > 0) {
        final high = channel.min + (yTop + ySpan) * range;
        final low = channel.min + yTop * range;
        _labelRight(
            canvas, formatValue(high), plot.right - 3, top + 4, labelColour);
        _labelRight(canvas, formatValue(low), plot.right - 3,
            top + height - 16, labelColour);
      }
    }
  }

  void _label(
    Canvas canvas,
    String text,
    Offset at,
    Color colour,
    double size,
  ) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(color: colour, fontSize: size),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    painter.paint(canvas, at);
  }

  void _labelRight(
    Canvas canvas,
    String text,
    double right,
    double top,
    Color colour,
  ) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(color: colour, fontSize: 9),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    painter.paint(canvas, Offset(right - painter.width, top));
  }

  void _drawTrace(
    Canvas canvas,
    Rect plot,
    double span,
    int slot,
    int from,
    int to, {
    required Rect area,
    required double opacity,
    double width = 1.5,
  }) {
    final channel = log.channels[selected[slot]];
    if (!channel.hasData) return;

    final base = kTraceColors[slot % kTraceColors.length];
    final colour = opacity >= 1
        ? base
        : base.withAlpha(((255 * opacity).round()).clamp(0, 255).toInt());

    final visible = to - from + 1;
    if (visible <= 0) return;

    final columns = math.max(1, area.width.round());

    canvas.save();
    canvas.clipRect(area);

    // Zoomed in far enough that every sample owns a pixel: draw them all.
    if (visible <= columns) {
      final paint = Paint()
        ..color = colour
        ..style = PaintingStyle.stroke
        ..strokeWidth = width
        ..isAntiAlias = true;

      final path = Path();
      var started = false;
      var lastTime = double.negativeInfinity;

      for (var i = from; i <= to; i++) {
        final value = channel.values[i];
        final t = log.time[i];
        if (!value.isFinite || !t.isFinite) {
          started = false;
          continue;
        }
        if (t - lastTime > log.gapSeconds) started = false;
        lastTime = t;

        final x = area.left + ((t - start) / span) * area.width;
        final y = _yForValue(channel, value, area);
        if (started) {
          path.lineTo(x, y);
        } else {
          path.moveTo(x, y);
          started = true;
        }
      }

      canvas.drawPath(path, paint);
      canvas.restore();
      return;
    }

    // Dense view: keep the min AND max of every pixel column, so a spike that
    // lasts one sample still shows. Plain downsampling would erase it.
    final mins = List<double>.filled(columns, double.infinity);
    final maxs = List<double>.filled(columns, double.negativeInfinity);

    for (var i = from; i <= to; i++) {
      final value = channel.values[i];
      final t = log.time[i];
      if (!value.isFinite || !t.isFinite) continue;
      var c = (((t - start) / span) * columns).floor();
      if (c < 0) c = 0;
      if (c >= columns) c = columns - 1;
      if (value < mins[c]) mins[c] = value;
      if (value > maxs[c]) maxs[c] = value;
    }

    final barPaint = Paint()
      ..color = colour
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1.0, width)
      ..isAntiAlias = true;

    for (var c = 0; c < columns; c++) {
      if (!mins[c].isFinite) continue;
      final x = area.left + (c + 0.5) * area.width / columns;
      final yHigh = _yForValue(channel, maxs[c], area);
      final yLow = _yForValue(channel, mins[c], area);
      if ((yLow - yHigh).abs() < 0.8) {
        canvas.drawLine(Offset(x, yHigh - 0.5), Offset(x, yHigh + 0.5), barPaint);
      } else {
        canvas.drawLine(Offset(x, yHigh), Offset(x, yLow), barPaint);
      }
    }

    canvas.restore();
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
      if (!value.isFinite || !_isVisible(channel, value)) continue;

      final y = _yForValue(channel, value, _areaFor(slot, plot));

      final base = kTraceColors[slot % kTraceColors.length];
      final dim =
          highlighted != null && selected[slot] != highlighted;

      canvas.drawCircle(
        Offset(x, y),
        dim ? 2.4 : 3.6,
        Paint()
          ..color = dim ? base.withAlpha(70) : base,
      );
    }

    _paintCursorTag(canvas, plot, x, t);
  }

  void _paintCursorTag(Canvas canvas, Rect plot, double x, double t) {
    final painter = TextPainter(
      text: TextSpan(
        text: formatClock(t),
        style: const TextStyle(color: Colors.white, fontSize: 10),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    const padding = 5.0;
    final width = painter.width + padding * 2;
    final left =
        (x - width / 2).clamp(plot.left, plot.right - width).toDouble();
    final rect = Rect.fromLTWH(left, plot.top - 18, width, painter.height + 4);

    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(3)),
      Paint()..color = const Color(0xCC1B2432),
    );
    painter.paint(canvas, Offset(left + padding, plot.top - 16));
  }

  /// Value label attached to each trace at the cursor.
  void _paintTags(Canvas canvas, Rect plot, double span) {
    final index = cursor;
    if (index == null || index < 0 || index >= log.sampleCount) return;

    final t = log.time[index];
    if (!t.isFinite || t < start || t > end) return;

    final x = plot.left + ((t - start) / span).clamp(0.0, 1.0) * plot.width;

    // Highlighted trace last so its label wins any overlap.
    for (var pass = 0; pass < 2; pass++) {
      for (var slot = 0; slot < selected.length; slot++) {
        final isHighlighted = selected[slot] == highlighted;
        if ((pass == 0) == isHighlighted) continue;

        final channel = log.channels[selected[slot]];
        if (!channel.hasData) continue;

        final value = channel.values[index];
        if (!value.isFinite || !_isVisible(channel, value)) continue;

        final y = _yForValue(channel, value, _areaFor(slot, plot));

        final base = kTraceColors[slot % kTraceColors.length];
        final dim = highlighted != null && !isHighlighted;

        final unitLabel = channel.unit.isEmpty || channel.unit.length > 3
            ? ''
            : ' ${channel.unit}';

        final painter = TextPainter(
          text: TextSpan(
            text: '${formatValue(value)}$unitLabel',
            style: TextStyle(
              color: dim ? base.withAlpha(90) : base,
              fontSize: 10,
              fontWeight: FontWeight.w600,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();

        const padH = 4.0;
        const padV = 2.0;
        final width = painter.width + padH * 2;
        final height = painter.height + padV * 2;

        var left = x + 9;
        if (left + width > plot.right) left = x - 9 - width;
        left = left
            .clamp(plot.left, math.max(plot.left, plot.right - width))
            .toDouble();
        final area = _areaFor(slot, plot);
        final top = (y - height / 2)
            .clamp(area.top, math.max(area.top, area.bottom - height))
            .toDouble();

        final rect = Rect.fromLTWH(left, top, width, height);

        canvas.drawRRect(
          RRect.fromRectAndRadius(rect, const Radius.circular(3)),
          Paint()..color = const Color(0xE60B0E13),
        );
        canvas.drawRRect(
          RRect.fromRectAndRadius(rect, const Radius.circular(3)),
          Paint()
            ..color = dim ? base.withAlpha(70) : base
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1,
        );
        painter.paint(canvas, Offset(left + padH, top + padV));
      }
    }
  }

  @override
  bool shouldRepaint(covariant _ChartPainter oldDelegate) {
    return oldDelegate.cursor != cursor ||
        oldDelegate.start != start ||
        oldDelegate.end != end ||
        oldDelegate.yTop != yTop ||
        oldDelegate.ySpan != ySpan ||
        oldDelegate.log != log ||
        oldDelegate.showTags != showTags ||
        oldDelegate.highlighted != highlighted ||
        oldDelegate.laneMode != laneMode ||
        oldDelegate.aliases != aliases ||
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
