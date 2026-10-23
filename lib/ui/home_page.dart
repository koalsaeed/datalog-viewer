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

  /// `null` means "decide by screen width".
  bool? _panelOverride;
  bool _isNarrow = false;

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

            final panelVisible = _panelOverride ?? !_isNarrow;

            return Column(
              children: [
                _TopBar(
                  log: log,
                  cursor: _cursor,
                  narrow: _isNarrow,
                  panelVisible: panelVisible,
                  busy: _busy,
                  onOpen: _openLog,
                  onTogglePanel: () =>
                      setState(() => _panelOverride = !panelVisible),
                ),
                const Divider(height: 1, color: kBorder),
                Expanded(child: _viewer(log, panelVisible)),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _viewer(VehicleLog log, bool panelVisible) {
    final panel = ChannelPanel(
      log: log,
      selected: _selected,
      cursor: _cursor,
      onToggle: _toggleChannel,
      onClose: () => setState(() => _panelOverride = false),
    );

    final chart = ChartView(
      log: log,
      selected: _selected,
      cursor: _cursor,
      onCursorChanged: (index) => setState(() => _cursor = index),
    );

    if (!_isNarrow) {
      return Row(
        children: [
          if (panelVisible) ...[
            SizedBox(width: 300, child: panel),
            const VerticalDivider(width: 1, color: kBorder),
          ],
          Expanded(child: chart),
        ],
      );
    }

    final overlayWidth =
        math.min(320.0, MediaQuery.of(context).size.width * 0.86);

    return Stack(
      children: [
        Positioned.fill(child: chart),
        if (panelVisible) ...[
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
            width: overlayWidth,
            child: Material(
              color: kSurface,
              elevation: 12,
              child: panel,
            ),
          ),
        ],
      ],
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.log,
    required this.cursor,
    required this.narrow,
    required this.panelVisible,
    required this.busy,
    required this.onOpen,
    required this.onTogglePanel,
  });

  final VehicleLog log;
  final int? cursor;
  final bool narrow;
  final bool panelVisible;
  final bool busy;
  final VoidCallback onOpen;
  final VoidCallback onTogglePanel;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 54,
      child: Row(
        children: [
          const SizedBox(width: 4),
          IconButton(
            onPressed: busy ? null : onOpen,
            icon: const Icon(Icons.folder_open, size: 18),
            color: kMuted,
            tooltip: 'Open another log',
            visualDensity: VisualDensity.compact,
          ),
          IconButton(
            onPressed: onTogglePanel,
            icon: Icon(
              narrow
                  ? Icons.view_sidebar
                  : (panelVisible
                      ? Icons.chevron_left
                      : Icons.chevron_right),
              size: 18,
            ),
            color: kMuted,
            tooltip: panelVisible ? 'Hide channels' : 'Show channels',
            visualDensity: VisualDensity.compact,
          ),
          const SizedBox(width: 2),
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
          if (cursor != null)
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Text(
                't = ${formatClock(log.time[cursor!])}',
                style: const TextStyle(
                  fontSize: 12,
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
