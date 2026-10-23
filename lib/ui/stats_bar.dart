import 'dart:math' as math;
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

/// Same numbers as [StatsBar], stacked in a column beside the chart.
class StatsSide extends StatelessWidget {
  const StatsSide({
    super.key,
    required this.log,
    required this.selected,
    required this.start,
    required this.end,
    required this.cursor,
    required this.borderRight,
  });

  final VehicleLog log;
  final List<int> selected;
  final double start;
  final double end;
  final int? cursor;
  final bool borderRight;

  @override
  Widget build(BuildContext context) {
    final width = math.min(198.0, MediaQuery.of(context).size.width * 0.42);

    return Container(
      width: width,
      decoration: BoxDecoration(
        color: kSurface,
        border: Border(
          right:
              borderRight ? const BorderSide(color: kBorder) : BorderSide.none,
          left: borderRight
              ? BorderSide.none
              : const BorderSide(color: kBorder),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(12, 10, 12, 4),
            child: Text('VALUES', style: kLabelStyle),
          ),
          Expanded(
            child: selected.isEmpty
                ? const Center(
                    child: Text(
                      'No channels',
                      style: TextStyle(color: kMuted, fontSize: 11),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.only(bottom: 8),
                    itemCount: selected.length,
                    itemBuilder: (context, slot) {
                      final channel = log.channels[selected[slot]];
                      final range = _rangeOf(channel);
                      return _SideRow(
                        channel: channel,
                        colour: kTraceColors[slot % kTraceColors.length],
                        current:
                            cursor == null ? null : channel.valueAt(cursor!),
                        min: range.min,
                        max: range.max,
                        valid: range.valid,
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  _Range _rangeOf(LogChannel channel) {
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

class _SideRow extends StatelessWidget {
  const _SideRow({
    required this.channel,
    required this.colour,
    required this.current,
    required this.min,
    required this.max,
    required this.valid,
  });

  final LogChannel channel;
  final Color colour;
  final double? current;
  final double min;
  final double max;
  final bool valid;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 5, 12, 5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 3,
                height: 12,
                decoration: BoxDecoration(
                  color: colour,
                  borderRadius: BorderRadius.circular(1.5),
                ),
              ),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  channel.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 11, color: Colors.white70),
                ),
              ),
              Text(
                formatValue(current),
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: current == null ? kMuted : Colors.white,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(left: 10, top: 2),
            child: Text(
              valid ? '${formatValue(min)} — ${formatValue(max)}' : '--',
              style: const TextStyle(
                fontSize: 9.5,
                color: kMuted,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

