import 'dart:ui' show FontFeature;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;

import '../models/vehicle_log.dart';
import '../parsers/csv_parser.dart';
import '../services/log_loader.dart';
import '../util/units.dart';
import 'channel_panel.dart';
import 'chart_view.dart';
import 'landing_view.dart';
import 'theme.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  VehicleLog? _log;
  bool _busy = false;
  String? _error;

  final List<int> _selected = <int>[];
  int? _cursor;

  bool? _panelOverride;
  bool _pinned = true;
  bool _showStats = false;
  bool _focus = false;
  bool _isNarrow = false;
  double _topPanelHeight = 210;

  bool get _panelVisible => _panelOverride ?? true;

  Future<void> _openLog() async {
    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      final log = await LogLoader.pickLog();
      if (log == null) {
        setState(() => _busy = false);
        return;
      }
      _applyLog(log);
    } catch (error) {
      setState(() {
        _busy = false;
        _error = error.toString();
      });
    }
  }

  Future<void> _loadSample() async {
    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      final text = await rootBundle.loadString('assets/sample.csv');
      _applyLog(parseCsvLog(text, fileName: 'datalog3.csv'));
    } catch (error) {
      setState(() {
        _busy = false;
        _error = error.toString();
      });
    }
  }

  void _applyLog(VehicleLog log) {
    const wanted = <String>[
      'rpm',
      'throttle angle Actual',
      'lambse bank 1',
      'vehicle speed mph',
    ];

    final picked = <int>[];
    for (final name in wanted) {
      final index = log.channels.indexWhere(
        (channel) => channel.name.toLowerCase() == name.toLowerCase(),
      );
      if (index >= 0 && !picked.contains(index)) picked.add(index);
    }
    if (picked.isEmpty) {
      for (var i = 0; i < log.channels.length && picked.length < 3; i++) {
        if (log.channels[i].hasData) picked.add(i);
      }
    }

    setState(() {
      _log = log;
      _busy = false;
      _focus = false;
      _selected
        ..clear()
        ..addAll(picked);
      _cursor = log.sampleCount > 0 ? log.sampleCount ~/ 2 : null;
    });
  }

  void _toggleChannel(int index) {
    setState(() {
      if (_selected.contains(index)) {
        _selected.remove(index);
        return;
      }
      if (_selected.length >= kTraceColors.length) _selected.removeAt(0);
      _selected.add(index);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            _isNarrow = constraints.maxWidth < 760;

            final log = _log;
            if (log == null) {
              return LandingView(
                busy: _busy,
                error: _error,
                onOpen: _openLog,
                onSample: _loadSample,
              );
            }

            if (_focus) return _focusBody(log);

            return Column(
              children: [
                _TopBar(
                  log: log,
                  cursor: _cursor,
                  narrow: _isNarrow,
                  panelVisible: _panelVisible,
                  showStats: _showStats,
                  busy: _busy,
                  onOpen: _openLog,
                  onTogglePanel: () =>
                      setState(() => _panelOverride = !_panelVisible),
                  onToggleStats: () =>
                      setState(() => _showStats = !_showStats),
                  onToggleFocus: () => setState(() => _focus = true),
                  onTogglePin: _isNarrow
                      ? () => setState(() => _pinned = !_pinned)
                      : null,
                  pinned: _pinned,
                ),
                const Divider(height: 1, color: kBorder),
                Expanded(child: _viewer(log)),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _chart(VehicleLog log) {
    return ChartView(
      log: log,
      selected: _selected,
      cursor: _cursor,
      onCursorChanged: (index) => setState(() => _cursor = index),
      showStats: _showStats,
    );
  }

  Widget _focusBody(VehicleLog log) {
    return Stack(
      children: [
        Positioned.fill(child: _chart(log)),
        Positioned(
          top: 8,
          left: 8,
          child: Material(
            color: const Color(0xCC1B2432),
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: () => setState(() => _focus = false),
              child: const SizedBox(
                width: 38,
                height: 38,
                child: Icon(Icons.close_fullscreen, size: 17, color: kMuted),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _viewer(VehicleLog log) {
    final panel = ChannelPanel(
      log: log,
      selected: _selected,
      cursor: _cursor,
      onToggle: _toggleChannel,
      onClose: () => setState(() => _panelOverride = false),
    );

    final chart = _chart(log);

    if (!_isNarrow) {
      return Row(
        children: [
          if (_panelVisible) ...[
            SizedBox(width: 300, child: panel),
            const VerticalDivider(width: 1, color: kBorder),
          ],
          Expanded(child: chart),
        ],
      );
    }

    if (!_panelVisible) return chart;

    if (_pinned) {
      return Column(
        children: [
          SizedBox(height: _topPanelHeight, child: panel),
          _resizeHandle(),
          Expanded(child: chart),
        ],
      );
    }

    return Stack(
      children: [
        Positioned.fill(child: chart),
        Positioned.fill(
          child: GestureDetector(
            onTap: () => setState(() => _panelOverride = false),
            child: Container(color: const Color(0x99000000)),
          ),
        ),
        Positioned(
          left: 0,
          top: 0,
          bottom: 0,
          width: MediaQuery.of(context).size.width * 0.86,
          child: Material(color: kSurface, elevation: 12, child: panel),
        ),
      ],
    );
  }

  Widget _resizeHandle() {
    final maxHeight = MediaQuery.of(context).size.height * 0.6;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onVerticalDragUpdate: (details) {
        setState(() {
          _topPanelHeight =
              (_topPanelHeight + details.delta.dy).clamp(120.0, maxHeight).toDouble();
        });
      },
      child: Container(
        height: 16,
        color: kSurface,
        child: Center(
          child: Container(
            width: 44,
            height: 3,
            decoration: BoxDecoration(
              color: kBorder,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.log,
    required this.cursor,
    required this.narrow,
    required this.panelVisible,
    required this.showStats,
    required this.busy,
    required this.onOpen,
    required this.onTogglePanel,
    required this.onToggleStats,
    required this.onToggleFocus,
    required this.onTogglePin,
    required this.pinned,
  });

  final VehicleLog log;
  final int? cursor;
  final bool narrow;
  final bool panelVisible;
  final bool showStats;
  final bool busy;
  final VoidCallback onOpen;
  final VoidCallback onTogglePanel;
  final VoidCallback onToggleStats;
  final VoidCallback onToggleFocus;
  final VoidCallback? onTogglePin;
  final bool pinned;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 54,
      child: Row(
        children: [
          const SizedBox(width: 4),
          _icon(Icons.folder_open, 'Open another log', busy ? null : onOpen),
          _icon(
            panelVisible ? Icons.chevron_left : Icons.chevron_right,
            panelVisible ? 'Hide channels' : 'Show channels',
            onTogglePanel,
          ),
          if (onTogglePin != null)
            _icon(
              pinned ? Icons.push_pin : Icons.push_pin_outlined,
              pinned ? 'Unpin panel' : 'Pin panel to top',
              onTogglePin,
              active: pinned,
            ),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              log.fileName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 14),
          if (!narrow) ...[
            _Pill(text: '${log.channels.length} ch'),
            _Pill(text: '${log.sampleCount} samples'),
            _Pill(text: formatClock(log.duration)),
          ],
          const Spacer(),
          if (cursor != null && !narrow)
            Padding(
              padding: const EdgeInsets.only(right: 10),
              child: Text(
                't = ${formatClock(log.time[cursor!])}',
                style: const TextStyle(
                  fontSize: 12,
                  color: kMuted,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
            ),
          _icon(
            Icons.straighten,
            showStats ? 'Hide min / max' : 'Show min / max',
            onToggleStats,
            active: showStats,
          ),
          _icon(Icons.fullscreen, 'Focus mode', onToggleFocus),
          const SizedBox(width: 4),
        ],
      ),
    );
  }

  Widget _icon(
    IconData icon,
    String tooltip,
    VoidCallback? onPressed, {
    bool active = false,
  }) {
    return IconButton(
      onPressed: onPressed,
      icon: Icon(icon, size: 18),
      color: active ? kAccent : kMuted,
      tooltip: tooltip,
      visualDensity: VisualDensity.compact,
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(right: 8),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: kSurfaceAlt,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(text, style: const TextStyle(fontSize: 11, color: kMuted)),
    );
  }
}
