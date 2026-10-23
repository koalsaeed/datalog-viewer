import 'dart:ui' show FontFeature;

import 'package:flutter/material.dart';

import '../models/vehicle_log.dart';
import '../util/units.dart';
import 'theme.dart';

class ChannelPanel extends StatelessWidget {
  const ChannelPanel({
    super.key,
    required this.log,
    required this.selected,
    required this.cursor,
    required this.onToggle,
  });

  final VehicleLog log;
  final List<int> selected;
  final int? cursor;
  final ValueChanged<int> onToggle;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: kSurface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
            child: Row(
              children: [
                const Text(
                  'CHANNELS',
                  style: TextStyle(
                    color: kMuted,
                    fontSize: 10,
                    letterSpacing: 1.2,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                Text(
                  '${log.channels.length}',
                  style: const TextStyle(color: kMuted, fontSize: 11),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: log.channels.length,
              itemBuilder: (context, index) {
                return _ChannelRow(
                  channel: log.channels[index],
                  color: _colorFor(index),
                  value: cursor == null
                      ? null
                      : log.channels[index].valueAt(cursor!),
                  onTap: () => onToggle(index),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Color? _colorFor(int index) {
    final slot = selected.indexOf(index);
    if (slot < 0) return null;
    return kTraceColors[slot % kTraceColors.length];
  }
}

class _ChannelRow extends StatelessWidget {
  const _ChannelRow({
    required this.channel,
    required this.color,
    required this.value,
    required this.onTap,
  });

  final LogChannel channel;
  final Color? color;
  final double? value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final active = color != null;

    return InkWell(
      onTap: onTap,
      child: Container(
        height: 46,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        color: active ? kSurfaceSelected : null,
        child: Row(
          children: [
            Container(
              width: 3,
              height: 24,
              decoration: BoxDecoration(
                color: color ?? const Color(0xFF2A3441),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    channel.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12.5,
                      color: active ? Colors.white : Colors.white70,
                    ),
                  ),
                  Text(
                    channel.unit.isEmpty ? '—' : channel.unit,
                    style: const TextStyle(fontSize: 10, color: kMuted),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(
              _readout(),
              style: TextStyle(
                fontSize: 12,
                fontFeatures: const [FontFeature.tabularFigures()],
                color: active ? Colors.white : kMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _readout() {
    if (!channel.hasData) return '--';
    if (value != null) return formatValue(value);
    return '${formatValue(channel.min)}–${formatValue(channel.max)}';
  }
}
