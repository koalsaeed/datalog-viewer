import 'dart:ui' show FontFeature;

import 'package:flutter/material.dart';

import '../models/vehicle_log.dart';
import '../util/units.dart';
import 'theme.dart';

/// Two lists in one scroll view:
///  * **IN CHART** — picked channels, reorderable with a long press, hidden
///    temporarily with a double tap (or the eye button).
///  * **ALL CHANNELS** — everything else, tap to add.
class ChannelPanel extends StatefulWidget {
  const ChannelPanel({
    super.key,
    required this.log,
    required this.selected,
    required this.hidden,
    required this.visibleOrder,
    required this.aliases,
    required this.onEdit,
    required this.onPickChannels,
    required this.cursor,
    required this.onToggle,
    required this.onToggleHidden,
    required this.onReorder,
    required this.onClose,
    required this.onIsolate,
    required this.onClear,
    required this.highlighted,
  });

  final VehicleLog log;

  /// Picked channels, in the user's order.
  final List<int> selected;

  /// Picked but temporarily muted.
  final Set<int> hidden;

  /// Picked and visible — decides trace colours so they never shift.
  final List<int> visibleOrder;

  /// Custom display names for picked channels.
  final Map<int, String> aliases;

  final VoidCallback onEdit;
  final VoidCallback onPickChannels;

  final int? cursor;
  final ValueChanged<int> onToggle;
  final ValueChanged<int> onToggleHidden;
  final void Function(int oldIndex, int newIndex) onReorder;
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

  Color? _colourFor(int channelIndex) {
    final slot = widget.visibleOrder.indexOf(channelIndex);
    if (slot < 0) return null;
    return kTraceColors[slot % kTraceColors.length];
  }

  @override
  Widget build(BuildContext context) {
    final query = _search.text.trim().toLowerCase();
    final others = <int>[];
    for (var i = 0; i < widget.log.channels.length; i++) {
      if (widget.selected.contains(i)) continue;
      final channel = widget.log.channels[i];
      if (query.isEmpty || channel.name.toLowerCase().contains(query)) {
        others.add(i);
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
            child: CustomScrollView(
              slivers: [
                if (widget.selected.isNotEmpty) ...[
                  _section('IN CHART', '${widget.selected.length}'),
                  SliverReorderableList(
                    itemCount: widget.selected.length,
                    onReorder: widget.onReorder,
                    itemBuilder: (context, index) {
                      final channelIndex = widget.selected[index];
                      final channel = widget.log.channels[channelIndex];
                      return ReorderableDelayedDragStartListener(
                        key: ValueKey<int>(channelIndex),
                        index: index,
                        child: _SelectedRow(
                          channel: channel,
                          label: (widget.aliases[channelIndex] ?? '').trim().isEmpty
                              ? channel.name
                              : widget.aliases[channelIndex]!,
                          colour: _colourFor(channelIndex),
                          muted: widget.hidden.contains(channelIndex),
                          isolated: widget.highlighted == channelIndex,
                          value: widget.cursor == null
                              ? null
                              : channel.valueAt(widget.cursor!),
                          unit: channel.unit,
                          range: channel.hasData
                              ? '${formatValue(channel.min)}–${formatValue(channel.max)}'
                              : '',
                          onToggleHidden: () =>
                              widget.onToggleHidden(channelIndex),
                          onIsolate: () => widget.onIsolate(channelIndex),
                        ),
                      );
                    },
                  ),
                ],
                _section('ALL CHANNELS', '${others.length}'),
                SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, position) {
                      final channelIndex = others[position];
                      final channel = widget.log.channels[channelIndex];
                      return _ChannelRow(
                        channel: channel,
                        value: widget.cursor == null
                            ? null
                            : channel.valueAt(widget.cursor!),
                        onTap: () => widget.onToggle(channelIndex),
                      );
                    },
                    childCount: others.length,
                  ),
                ),
                const SliverToBoxAdapter(child: SizedBox(height: 12)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  SliverToBoxAdapter _section(String title, String count, {Widget? trailing}) {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 8, 4),
        child: Row(
          children: [
            Text(title, style: kLabelStyle),
            const SizedBox(width: 8),
            Text(
              count,
              style: const TextStyle(fontSize: 10, color: Color(0xFF4C5866)),
            ),
            if (trailing != null) ...[const Spacer(), trailing],
          ],
        ),
      ),
    );
  }

  Widget _header() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 6, 4),
      child: Row(
        children: [
          const Text('CHANNELS', style: kLabelStyle),
          const SizedBox(width: 8),
          Text(
            '${widget.log.channels.length}',
            style: const TextStyle(color: kMuted, fontSize: 11),
          ),
          const Spacer(),
          IconButton(
            onPressed: widget.onPickChannels,
            icon: const Icon(Icons.add_circle_outline, size: 17),
            color: kMuted,
            visualDensity: VisualDensity.compact,
            tooltip: 'Add channels',
          ),
          IconButton(
            onPressed: widget.selected.isEmpty ? null : widget.onEdit,
            icon: const Icon(Icons.tune, size: 16),
            color: widget.selected.isEmpty ? const Color(0xFF3A4452) : kMuted,
            visualDensity: VisualDensity.compact,
            tooltip: 'Rename / reorder',
          ),
          if (widget.selected.isNotEmpty)
            IconButton(
              onPressed: widget.onClear,
              icon: const Icon(Icons.layers_clear, size: 16),
              color: kMuted,
              visualDensity: VisualDensity.compact,
              tooltip: 'Clear all',
            ),
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

/// A row inside IN CHART: draggable, muteable, isolatable.
class _SelectedRow extends StatelessWidget {
  const _SelectedRow({
    required this.channel,
    required this.label,
    required this.colour,
    required this.muted,
    required this.isolated,
    required this.value,
    required this.unit,
    required this.range,
    required this.onToggleHidden,
    required this.onIsolate,
  });

  final LogChannel channel;
  final String label;
  final Color? colour;
  final bool muted;
  final bool isolated;
  final double? value;
  final String unit;
  final String range;
  final VoidCallback onToggleHidden;
  final VoidCallback onIsolate;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onDoubleTap: onToggleHidden,
      child: Container(
        height: 46,
        padding: const EdgeInsets.only(right: 6),
        decoration: BoxDecoration(
          color: isolated
              ? const Color(0xFF223047)
              : (muted ? null : kSurfaceAlt),
        ),
        child: Row(
          children: [
            GestureDetector(
              onTap: onIsolate,
              behavior: HitTestBehavior.opaque,
              child: SizedBox(
                width: 22,
                height: 46,
                child: Center(
                  child: Container(
                    width: 3,
                    height: 24,
                    decoration: BoxDecoration(
                      color: muted
                          ? const Color(0xFF39424F)
                          : (colour ?? const Color(0xFF2A3441)),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
              ),
            ),
            Expanded(
              child: Opacity(
                opacity: muted ? 0.45 : 1,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12.5,
                        color: muted ? Colors.white54 : Colors.white,
                        fontWeight:
                            isolated ? FontWeight.w600 : FontWeight.normal,
                      ),
                    ),
                    Text(
                      unit.isEmpty
                          ? range
                          : (range.isEmpty ? unit : '$unit · $range'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 10, color: kMuted),
                    ),
                  ],
                ),
              ),
            ),
            Text(
              channel.hasData ? formatValue(value) : '--',
              style: TextStyle(
                fontSize: 12,
                fontFeatures: const [FontFeature.tabularFigures()],
                color: muted ? kMuted : Colors.white,
              ),
            ),
            IconButton(
              onPressed: onToggleHidden,
              icon: Icon(
                muted ? Icons.visibility_off : Icons.visibility,
                size: 15,
              ),
              color: muted ? kMuted : kAccent,
              visualDensity: VisualDensity.compact,
              tooltip: muted ? 'Show on chart' : 'Hide from chart',
            ),
          ],
        ),
      ),
    );
  }
}

/// A row in ALL CHANNELS: tap to add.
class _ChannelRow extends StatelessWidget {
  const _ChannelRow({
    required this.channel,
    required this.value,
    required this.onTap,
  });

  final LogChannel channel;
  final double? value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        height: 44,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(
          children: [
            Container(
              width: 3,
              height: 22,
              decoration: BoxDecoration(
                color: const Color(0xFF2A3441),
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
                    style: const TextStyle(
                      fontSize: 12.5,
                      color: Colors.white70,
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
              style: const TextStyle(
                fontSize: 12,
                fontFeatures: [FontFeature.tabularFigures()],
                color: kMuted,
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
