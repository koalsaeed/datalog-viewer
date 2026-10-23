import 'dart:ui' show FontFeature;

import 'package:flutter/material.dart';

import '../models/vehicle_log.dart';
import '../util/units.dart';
import 'theme.dart';

class ChannelPanel extends StatefulWidget {
  const ChannelPanel({
    super.key,
    required this.log,
    required this.selected,
    required this.cursor,
    required this.onToggle,
    required this.onClose,
  });

  final VehicleLog log;
  final List<int> selected;
  final int? cursor;
  final ValueChanged<int> onToggle;
  final VoidCallback onClose;

  @override
  State<ChannelPanel> createState() => _ChannelPanelState();
}

class _ChannelPanelState extends State<ChannelPanel> {
  final TextEditingController _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final query = _search.text.trim().toLowerCase();
    final matches = <int>[];
    for (var i = 0; i < widget.log.channels.length; i++) {
      final channel = widget.log.channels[i];
      if (query.isEmpty || channel.name.toLowerCase().contains(query)) {
        matches.add(i);
      }
    }

    return Container(
      color: kSurface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _header(),
          _searchField(),
          Expanded(
            child: matches.isEmpty
                ? const Center(
                    child: Text(
                      'No channel matches',
                      style: TextStyle(color: kMuted, fontSize: 12),
                    ),
                  )
                : ListView.builder(
                    itemCount: matches.length,
                    itemBuilder: (context, position) {
                      final index = matches[position];
                      return _ChannelRow(
                        channel: widget.log.channels[index],
                        color: _colourFor(index),
                        value: widget.cursor == null
                            ? null
                            : widget.log.channels[index].valueAt(widget.cursor!),
                        onTap: () => widget.onToggle(index),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _header() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 8, 6),
      child: Row(
        children: [
          const Text('CHANNELS', style: kLabelStyle),
          const SizedBox(width: 8),
          Text(
            '${widget.log.channels.length}',
            style: const TextStyle(color: kMuted, fontSize: 11),
          ),
          const Spacer(),
          if (widget.selected.isNotEmpty)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                color: kSurfaceAlt,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                '${widget.selected.length} shown',
                style: const TextStyle(color: kMuted, fontSize: 10),
              ),
            ),
          IconButton(
            onPressed: widget.onClose,
            icon: const Icon(Icons.chevron_left, size: 18),
            color: kMuted,
            visualDensity: VisualDensity.compact,
            tooltip: 'Hide panel',
          ),
        ],
      ),
    );
  }

  Widget _searchField() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: TextField(
        controller: _search,
        onChanged: (_) => setState(() {}),
        style: const TextStyle(fontSize: 12.5, color: Colors.white),
        cursorColor: kAccent,
        decoration: InputDecoration(
          isDense: true,
          filled: true,
          fillColor: kSurfaceAlt,
          hintText: 'Search channels',
          hintStyle: const TextStyle(color: kMuted, fontSize: 12.5),
          prefixIcon: const Icon(Icons.search, size: 16, color: kMuted),
          prefixIconConstraints:
              const BoxConstraints(minWidth: 34, minHeight: 34),
          suffixIcon: _search.text.isEmpty
              ? null
              : IconButton(
                  icon: const Icon(Icons.close, size: 14, color: kMuted),
                  onPressed: () {
                    _search.clear();
                    setState(() {});
                  },
                  visualDensity: VisualDensity.compact,
                ),
          contentPadding: const EdgeInsets.symmetric(vertical: 9),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(6),
            borderSide: BorderSide.none,
          ),
        ),
      ),
    );
  }

  Color? _colourFor(int index) {
    final slot = widget.selected.indexOf(index);
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
        padding: const EdgeInsets.symmetric(horizontal: 12),
        color: active ? kSurfaceAlt : null,
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
