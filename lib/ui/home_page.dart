import 'dart:math' as math;
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

enum PanelDock { left, top }

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
  int? _isolated;

  bool? _panelOverride;
  PanelDock? _dockOverride;
  bool _showStats = false;
  StatsDock _statsDock = StatsDock.bottom;
  bool _showTags = true;
  bool _lanes = true;
  bool _cursorLocked = false;
  bool _focus = false;
  bool _isNarrow = false;

  double _leftWidth = 300;
  double _topHeight = 210;

  bool get _panelVisible => _panelOverride ?? true;

  PanelDock get _dock =>
      _dockOverride ?? (_isNarrow ? PanelDock.top : PanelDock.left);

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
      _isolated = null;
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
        if (_isolated == index) _isolated = null;
        return;
      }
      if (_selected.length >= kTraceColors.length) {
        final dropped = _selected.removeAt(0);
        if (_isolated == dropped) _isolated = null;
      }
      _selected.add(index);
    });
  }

  void _isolateChannel(int index) {
    setState(() {
      _isolated = _isolated == index ? null : index;
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
                  dock: _dock,
                  showStats: _showStats,
                  showTags: _showTags,
                  lanes: _lanes,
                  statsDock: _statsDock,
                  busy: _busy,
                  onOpen: _openLog,
                  onTogglePanel: () =>
                      setState(() => _panelOverride = !_panelVisible),
                  onToggleDock: () => setState(() {
                    _dockOverride =
                        _dock == PanelDock.left ? PanelDock.top : PanelDock.left;
                  }),
                  onToggleStats: () =>
                      setState(() => _showStats = !_showStats),
                  onToggleTags: () => setState(() => _showTags = !_showTags),
                  onToggleLanes: () => setState(() => _lanes = !_lanes),
                  onCycleStatsDock: () => setState(() {
                    _statsDock = switch (_statsDock) {
                      StatsDock.bottom => StatsDock.left,
                      StatsDock.left => StatsDock.right,
                      StatsDock.right => StatsDock.bottom,
                    };
                  }),
                  onToggleFocus: () => setState(() => _focus = true),
                ),
                const Divider(height: 1, color: kBorder),
                Expanded(
                  child: _viewer(log, constraints.maxWidth),
                ),
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
      statsDock: _statsDock,
      showTags: _showTags,
      highlighted: _isolated,
      laneMode: _lanes,
      cursorLocked: _cursorLocked,
      onToggleLock: () => setState(() => _cursorLocked = !_cursorLocked),
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

  Widget _viewer(VehicleLog log, double availableWidth) {
    final panel = ChannelPanel(
      log: log,
      selected: _selected,
      cursor: _cursor,
      onToggle: _toggleChannel,
      onClose: () => setState(() => _panelOverride = false),
      onIsolate: _isolateChannel,
      onClear: () => setState(() {
        _selected.clear();
        _isolated = null;
      }),
      highlighted: _isolated,
    );

    final chart = Stack(
      children: [
        Positioned.fill(child: _chart(log)),
        if (_isolated != null) _isolateChip(log),
      ],
    );

    if (!_panelVisible) return chart;

    if (_dock == PanelDock.left) {
      final maxWidth = math.max(240.0, availableWidth - 240);
      final width = _leftWidth.clamp(220.0, maxWidth).toDouble();
      return Row(
        children: [
          SizedBox(width: width, child: panel),
          _verticalHandle(),
          Expanded(child: chart),
        ],
      );
    }

    return Column(
      children: [
        SizedBox(height: _topHeight, child: panel),
        _horizontalHandle(),
        Expanded(child: chart),
      ],
    );
  }

  Widget _isolateChip(VehicleLog log) {
    final index = _isolated;
    if (index == null) return const SizedBox.shrink();

    final slot = _selected.indexOf(index);
    final colour = slot < 0
        ? kAccent
        : kTraceColors[slot % kTraceColors.length];

    return Positioned(
      left: 10,
      top: 10,
      child: Material(
        color: const Color(0xE61B2432),
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () => setState(() => _isolated = null),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 6, 8, 6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration:
                      BoxDecoration(color: colour, shape: BoxShape.circle),
                ),
                const SizedBox(width: 7),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 170),
                  child: Text(
                    log.channels[index].name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 11, color: Colors.white),
                  ),
                ),
                const SizedBox(width: 6),
                const Icon(Icons.close, size: 12, color: kMuted),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _verticalHandle() {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onHorizontalDragUpdate: (details) {
        setState(() {
          _leftWidth =
              (_leftWidth + details.delta.dx).clamp(220.0, 520.0).toDouble();
        });
      },
      child: Container(
        width: 10,
        decoration: const BoxDecoration(
          color: kSurface,
          border: Border(
            left: BorderSide(color: kBorder),
            right: BorderSide(color: kBorder),
          ),
        ),
        child: Center(
          child: Container(
            width: 2,
            height: 36,
            decoration: BoxDecoration(
              color: kBorder,
              borderRadius: BorderRadius.circular(1),
            ),
          ),
        ),
      ),
    );
  }

  Widget _horizontalHandle() {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onVerticalDragUpdate: (details) {
        setState(() {
          _topHeight =
              (_topHeight + details.delta.dy).clamp(120.0, 480.0).toDouble();
        });
      },
      child: Container(
        height: 14,
        color: kSurface,
        child: Center(
          child: Container(
            width: 44,
            height: 2,
            decoration: BoxDecoration(
              color: kBorder,
              borderRadius: BorderRadius.circular(1),
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
    required this.dock,
    required this.showStats,
    required this.showTags,
    required this.lanes,
    required this.statsDock,
    required this.busy,
    required this.onOpen,
    required this.onTogglePanel,
    required this.onToggleDock,
    required this.onToggleStats,
    required this.onToggleTags,
    required this.onToggleLanes,
    required this.onToggleFocus,
    required this.onCycleStatsDock,
  });

  final VehicleLog log;
  final int? cursor;
  final bool narrow;
  final bool panelVisible;
  final PanelDock dock;
  final bool showStats;
  final bool showTags;
  final bool lanes;
  final StatsDock statsDock;
  final bool busy;
  final VoidCallback onOpen;
  final VoidCallback onTogglePanel;
  final VoidCallback onToggleDock;
  final VoidCallback onToggleStats;
  final VoidCallback onToggleTags;
  final VoidCallback onToggleLanes;
  final VoidCallback onToggleFocus;
  final VoidCallback onCycleStatsDock;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 54,
      child: Row(
        children: [
          const SizedBox(width: 2),
          _icon(Icons.folder_open, 'Open another log', busy ? null : onOpen),
          _icon(
            panelVisible ? Icons.chevron_left : Icons.chevron_right,
            panelVisible ? 'Hide panel' : 'Show panel',
            onTogglePanel,
          ),
          _icon(
            dock == PanelDock.left ? Icons.view_agenda : Icons.view_sidebar,
            dock == PanelDock.left ? 'Dock panel on top' : 'Dock panel on left',
            onToggleDock,
            active: panelVisible,
          ),
          const SizedBox(width: 4),
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
          const SizedBox(width: 12),
          if (!narrow) ...[
            _pill('${log.channels.length} ch'),
            _pill('${log.sampleCount} samples'),
            _pill(formatClock(log.duration)),
          ],
          const Spacer(),
          if (cursor != null && !narrow)
            Padding(
              padding: const EdgeInsets.only(right: 8),
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
            lanes ? Icons.view_stream : Icons.show_chart,
            lanes ? 'Switch to overlay' : 'Switch to stacked lanes',
            onToggleLanes,
            active: lanes,
          ),
          _icon(
            showTags ? Icons.label : Icons.label_outline,
            showTags ? 'Hide value labels' : 'Show value labels',
            onToggleTags,
            active: showTags,
          ),
          if (showStats)
            _icon(
              statsDock == StatsDock.bottom
                  ? Icons.view_agenda
                  : Icons.view_sidebar,
              switch (statsDock) {
                StatsDock.bottom => 'Move values to the left',
                StatsDock.left => 'Move values to the right',
                StatsDock.right => 'Move values below the chart',
              },
              onCycleStatsDock,
              active: statsDock != StatsDock.bottom,
            ),
          _icon(
            Icons.straighten,
            showStats ? 'Hide min / max' : 'Show min / max',
            onToggleStats,
            active: showStats,
          ),
          _icon(Icons.fullscreen, 'Focus mode', onToggleFocus),
          const SizedBox(width: 2),
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
      icon: Icon(icon, size: 17),
      color: active ? kAccent : kMuted,
      tooltip: tooltip,
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
    );
  }

  Widget _pill(String text) {
    return Container(
      margin: const EdgeInsets.only(right: 6),
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: kSurfaceAlt,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(text, style: const TextStyle(fontSize: 10.5, color: kMuted)),
    );
  }
}
