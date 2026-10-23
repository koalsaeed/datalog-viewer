import 'dart:ui' show FontFeature;

import 'package:flutter/material.dart';

import '../models/vehicle_log.dart';
import '../util/units.dart';
import 'theme.dart';

/// Current reading plus min / max for every selected channel.
///
/// Min and max are computed over the visible window only, so they answer the
/// question "how far did it go in this stretch?" rather than for the whole log.
class StatsBar extends StatelessWidget {
  const StatsBar({
    super.key,
    required this.log,
    required this.selected,
    required this.start,
    required this.end,
    required this.cursor,
  });

  final VehicleLog log;
  final List<int> selected;
  final double start;
  final double end;
  final int? cursor;

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];

    for (var slot = 0; slot < selected.length; slot++) {
      final channel = log.channels[selected[slot]];
      final stats = _rangeFor(channel);
      final current =
          cursor == null ? null : channel.valueAt(cursor!);

      rows.add(
        SizedBox(
          height: 20,
          child: Row(
            children: [
              const SizedBox(width: 12),
              Container(
                width: 3,
                height: 12,
                decoration: BoxDecoration(
                  color: kTraceColors[slot % kTraceColors.length],
                  borderRadius: BorderRadius.circular(1.5),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  channel.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 11, color: Colors.white70),
                ),
              ),
              _cell(
                formatValue(current),
                colour: current == null ? kMuted : Colors.white,
              ),
              _cell(stats.valid ? formatValue(stats.min) : '--'),
              _cell(stats.valid ? formatValue(stats.max) : '--'),
            ],
          ),
        ),
      );
    }

    final height = (rows.length * 20 + 20).clamp(40, 128).toDouble();

    return Container(
      height: height,
      decoration: const BoxDecoration(
        color: kSurface,
        border: Border(top: BorderSide(color: kBorder)),
      ),
      child: Column(
        children: [
          SizedBox(
            height: 20,
            child: Row(
              children: [
                const SizedBox(width: 23),
                const Expanded(child: SizedBox()),
                _label('NOW'),
                _label('MIN'),
                _label('MAX'),
              ],
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              child: Column(children: rows),
            ),
          ),
        ],
      ),
    );
  }

  Widget _label(String text) {
    return SizedBox(
      width: 64,
      child: Text(
        text,
        textAlign: TextAlign.right,
        style: const TextStyle(
          fontSize: 8.5,
          letterSpacing: 1,
          color: Color(0xFF5A6779),
        ),
      ),
    );
  }

  Widget _cell(String text, {Color colour = Colors.white}) {
    return SizedBox(
      width: 64,
      child: Text(
        text,
        textAlign: TextAlign.right,
        style: TextStyle(
          fontSize: 11,
          color: colour,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
    );
  }

  _Range _rangeFor(LogChannel channel) {
    final from = log.nearestIndex(start);
    final to = log.nearestIndex(end);

    var min = double.infinity;
    var max = double.negativeInfinity;

    for (var i = from; i <= to && i < log.sampleCount; i++) {
      final value = channel.values[i];
      if (!value.isFinite) continue;
      if (value < min) min = value;
      if (value > max) max = value;
    }

    if (!min.isFinite) return const _Range(false, 0, 0);
    return _Range(true, min, max);
  }
}

class _Range {
  const _Range(this.valid, this.min, this.max);

  final bool valid;
  final double min;
  final double max;
}
