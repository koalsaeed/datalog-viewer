import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/vehicle_log.dart';
import 'theme.dart';

/// Full-length overview strip with the current viewport highlighted.
///
/// Tap or drag anywhere on it to centre the chart there.
class Minimap extends StatelessWidget {
  const Minimap({
    super.key,
    required this.log,
    required this.selected,
    required this.start,
    required this.end,
    required this.onSeek,
  });

  final VehicleLog log;
  final List<int> selected;
  final double start;
  final double end;
  final ValueChanged<double> onSeek;

  int get _referenceChannel {
    if (selected.isNotEmpty) return selected.first;
    final rpm = log.channels
        .indexWhere((channel) => channel.name.toLowerCase().contains('rpm'));
    if (rpm >= 0) return rpm;
    for (var i = 0; i < log.channels.length; i++) {
      if (log.channels[i].hasData) return i;
    }
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        void seek(Offset local) {
          if (width <= 0) return;
          onSeek((local.dx / width).clamp(0.0, 1.0).toDouble());
        }

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (details) => seek(details.localPosition),
          onHorizontalDragUpdate: (details) => seek(details.localPosition),
          child: Container(
            height: 52,
            decoration: const BoxDecoration(
              color: kSurface,
              border: Border(top: BorderSide(color: kBorder)),
            ),
            child: CustomPaint(
              painter: _MinimapPainter(
                log: log,
                channelIndex: _referenceChannel,
                start: start,
                end: end,
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
  });

  final VehicleLog log;
  final int channelIndex;
  final double start;
  final double end;

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
        final y1 = size.height - 4 - normalisedHigh.toDouble() * (size.height - 8);
        final y2 = size.height - 4 - normalisedLow.toDouble() * (size.height - 8);
        canvas.drawLine(Offset(x.toDouble(), y1), Offset(x.toDouble(), y2), paint);
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
    canvas.drawRect(
      Rect.fromLTRB(left + 0.5, 0.5, right - 0.5, size.height - 0.5),
      Paint()
        ..color = const Color(0xCC4EA1FF)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
  }

  @override
  bool shouldRepaint(covariant _MinimapPainter oldDelegate) {
    return oldDelegate.start != start ||
        oldDelegate.end != end ||
        oldDelegate.log != log ||
        oldDelegate.channelIndex != channelIndex;
  }
}
