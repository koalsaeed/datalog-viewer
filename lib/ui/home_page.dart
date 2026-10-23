import 'dart:ui' show FontFeature;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;

import '../models/vehicle_log.dart';
import '../parsers/csv_parser.dart';
import '../util/units.dart';
import 'channel_panel.dart';
import 'chart_view.dart';
import 'theme.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  VehicleLog? _log;
  String? _error;
  final List<int> _selected = <int>[];
  int? _cursor;

  @override
  void initState() {
    super.initState();
    _loadSample();
  }

  Future<void> _loadSample() async {
    try {
      final text = await rootBundle.loadString('assets/sample.csv');
      final log = parseCsvLog(text, fileName: 'datalog3.csv');

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
        _selected
          ..clear()
          ..addAll(picked);
        _cursor = log.sampleCount ~/ 2;
      });
    } catch (error) {
      setState(() => _error = error.toString());
    }
  }

  void _toggleChannel(int index) {
    setState(() {
      if (_selected.contains(index)) {
        _selected.remove(index);
        return;
      }
      if (_selected.length >= kTraceColors.length) {
        _selected.removeAt(0);
      }
      _selected.add(index);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            if (constraints.maxWidth < 620) {
              return const _Message(
                icon: Icons.screen_rotation,
                title: 'Rotate your phone',
                detail: 'This viewer is built for landscape.',
              );
            }
            return _buildBody(constraints.maxWidth);
          },
        ),
      ),
    );
  }

  Widget _buildBody(double width) {
    if (_error != null) {
      return _Message(
        icon: Icons.error_outline,
        title: 'Could not open the log',
        detail: _error!,
      );
    }

    final log = _log;
    if (log == null) {
      return const Center(child: CircularProgressIndicator());
    }

    return Column(
      children: [
        _TopBar(log: log, cursor: _cursor),
        const Divider(height: 1, color: kBorder),
        Expanded(
          child: Row(
            children: [
              SizedBox(
                width: width < 900 ? 248 : 320,
                child: ChannelPanel(
                  log: log,
                  selected: _selected,
                  cursor: _cursor,
                  onToggle: _toggleChannel,
                ),
              ),
              const VerticalDivider(width: 1, color: kBorder),
              Expanded(
                child: ChartView(
                  log: log,
                  selected: _selected,
                  cursor: _cursor,
                  onCursorChanged: (index) => setState(() => _cursor = index),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({required this.log, required this.cursor});

  final VehicleLog log;
  final int? cursor;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          const Icon(Icons.show_chart, size: 18, color: Color(0xFF4EA1FF)),
          const SizedBox(width: 10),
          Text(
            log.fileName,
            style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
          ),
          const SizedBox(width: 18),
          _Pill(text: '${log.channels.length} channels'),
          _Pill(text: '${log.sampleCount} samples'),
          _Pill(text: formatClock(log.duration)),
          const Spacer(),
          if (cursor != null)
            Text(
              't = ${formatClock(log.time[cursor!])}',
              style: const TextStyle(
                fontSize: 12,
                color: kMuted,
                fontFeatures: [FontFeature.tabularFigures()],
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
        color: kSurfaceSelected,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(text, style: const TextStyle(fontSize: 11, color: kMuted)),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({
    required this.icon,
    required this.title,
    required this.detail,
  });

  final IconData icon;
  final String title;
  final String detail;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 40, color: kMuted),
            const SizedBox(height: 14),
            Text(
              title,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            Text(
              detail,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12, color: kMuted),
            ),
          ],
        ),
      ),
    );
  }
}
