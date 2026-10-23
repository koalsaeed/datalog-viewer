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
    required this.onIsolate,
    required this.onClear,
    required this.highlighted,
  });

  final VehicleLog log;
  final List<int> selected;
  final int? cursor;
  final ValueChanged<int> onToggle;
  final VoidCallback onClose;
  final ValueChanged<int> onIsolate;
  final VoidCallback onClear;
  final int? highlighted;

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
                      final slot = widget.selected.indexOf(index);
                      return _ChannelRow(
                        channel: widget.log.channels[index],
                        color: slot < 0
                            ? null
                            : kTraceColors[slot % kTraceColors.length],
                        value: widget.cursor == null
                            ? null
                            : widget.log.channels[index].valueAt(widget.cursor!),
                        isolated: widget.highlighted == index,
                        onTap: () => widget.onToggle(index),
                        onLongPress: () => widget.onIsolate(index),
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
      padding: const EdgeInsets.fromLTRB(14, 10, 6, 6),
      child: Row(
        children: [
          const Text('CHANNELS', style: kLabelStyle),
          const SizedBox(width: 8),
          Text(
            '${widget.log.channels.length}',
            style: const TextStyle(color: kMuted, fontSize: 11),
          ),
          const Spacer(),
          if (widget.selected.isNotEmpty) ...[
            TextButton(
              onPressed: widget.onClear,
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                minimumSize: const Size(0, 28),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: const Text(
                'Clear',
                style: TextStyle(fontSize: 11, color: kMuted),
              ),
            ),
          ],
          IconButton(
            onPressed: widget.onClose,
            icon: const Icon(Icons.close, size: 16),
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
}

class _ChannelRow extends StatelessWidget {
  const _ChannelRow({
    required this.channel,
    required this.color,
    required this.value,
    required this.isolated,
    required this.onTap,
    required this.onLongPress,
  });

  final LogChannel channel;
  final Color? color;
  final double? value;
  final bool isolated;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final active = color != null;

    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Container(
        height: 46,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: isolated
              ? const Color(0xFF223047)
              : (active ? kSurfaceAlt : null),
          border: isolated
              ? Border(left: BorderSide(color: color ?? kAccent, width: 2))
              : null,
        ),
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
                      color: isolated
                          ? Colors.white
                          : (active ? Colors.white : Colors.white70),
                      fontWeight:
                          isolated ? FontWeight.w600 : FontWeight.normal,
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
            if (isolated)
              const Padding(
                padding: EdgeInsets.only(right: 6),
                child: Icon(Icons.center_focus_strong, size: 12, color: kAccent),
              ),
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
