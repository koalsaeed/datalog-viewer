import 'dart:typed_data';

import '../models/vehicle_log.dart';
import '../util/units.dart';

class LogParseException implements Exception {
  LogParseException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Parses SCT LiveLink II style CSV datalogs.
///
/// The header carries ECU metadata after a pipe, for example:
///
///     rpm|1|224|29|0|0
///
/// Only the first segment is the channel name. The rest is protocol metadata
/// that a viewer does not need, so it is dropped here.
///
/// Design notes derived from real logs:
///  * sample rate is whatever the ECU produced (50 Hz, 83 Hz, 333 Hz...)
///  * the time column is authoritative — never infer time from row numbers
///  * duplicate / truncated names exist, so names are made unique
///  * some logs start at a non-zero timestamp
VehicleLog parseCsvLog(String content, {String fileName = 'log.csv'}) {
  final lines = <String>[];
  for (final raw in content.split('\n')) {
    final line = raw.endsWith('\r') ? raw.substring(0, raw.length - 1) : raw;
    if (line.trim().isNotEmpty) lines.add(line);
  }

  if (lines.length < 2) {
    throw LogParseException('No data rows found in $fileName.');
  }

  final delimiter = _detectDelimiter(lines.first);
  final headerCells = _splitLine(lines.first, delimiter);
  final names = _resolveNames(headerCells);
  final columnCount = names.length;

  if (columnCount < 2) {
    throw LogParseException('Only one column detected — this is not a datalog.');
  }

  var timeColumn = names.indexWhere((n) => n.toLowerCase().contains('time'));
  if (timeColumn < 0) timeColumn = 0;

  // Read every row first so malformed lines are dropped cleanly instead of
  // leaving NaN holes at the end of the typed arrays.
  final rows = <List<double>>[];
  for (var i = 1; i < lines.length; i++) {
    final cells = _splitLine(lines[i], delimiter);
    if (cells.length < columnCount) continue;

    final row = List<double>.filled(columnCount, double.nan);
    for (var c = 0; c < columnCount; c++) {
      final text = cells[c].trim();
      if (text.isEmpty) continue;
      final value = double.tryParse(text);
      if (value != null) row[c] = value;
    }
    rows.add(row);
  }

  if (rows.isEmpty) {
    throw LogParseException('Every data row was malformed in $fileName.');
  }

  final sampleCount = rows.length;

  final time = Float64List(sampleCount);
  var start = 0.0;
  var startSet = false;
  for (var i = 0; i < sampleCount; i++) {
    var t = rows[i][timeColumn];
    if (!t.isFinite) {
      // Keep the axis monotonic when the ECU omits a timestamp.
      t = i == 0 ? 0.0 : time[i - 1];
    }
    if (!startSet) {
      start = t;
      startSet = true;
    }
    time[i] = t - start;
  }

  final channels = <LogChannel>[];
  for (var c = 0; c < columnCount; c++) {
    if (c == timeColumn) continue;

    final values = Float64List(sampleCount);
    var min = double.infinity;
    var max = double.negativeInfinity;
    var valid = 0;

    for (var i = 0; i < sampleCount; i++) {
      final value = rows[i][c];
      values[i] = value;
      if (value.isFinite) {
        valid++;
        if (value < min) min = value;
        if (value > max) max = value;
      }
    }

    channels.add(
      LogChannel(
        name: names[c],
        unit: inferUnit(names[c]),
        values: values,
        min: valid == 0 ? 0 : min,
        max: valid == 0 ? 0 : max,
        validCount: valid,
      ),
    );
  }

  return VehicleLog(
    fileName: fileName,
    time: time,
    channels: channels,
    startTime: start,
    sampleCount: sampleCount,
  );
}

String _detectDelimiter(String headerLine) {
  const candidates = <String>[',', ';', '\t'];
  var best = ',';
  var bestCount = -1;

  for (final candidate in candidates) {
    final count = candidate.allMatches(headerLine).length;
    if (count > bestCount) {
      bestCount = count;
      best = candidate;
    }
  }

  return best;
}

List<String> _splitLine(String line, String delimiter) => line.split(delimiter);

/// LiveLink II truncates ECU PID names to 31 characters (a 32-byte field with
/// a terminator), so two genuinely different channels can arrive with
/// byte-identical names:
///
///     variable valve timing exhaust bank 1 actual  ->  variable valve timing exhaust b
///     variable valve timing exhaust bank 2 actual  ->  variable valve timing exhaust b
///
/// This table restores the full name from a richer export of the same vehicle.
/// The order matches the order in which the channels appear in the file.
const Map<String, List<String>> _truncatedFamily = {
  'variable valve timing exhaust b': [
    'variable valve timing exhaust bank 1 actual',
    'variable valve timing exhaust bank 2 actual',
  ],
  'variable valve timing intake ba': [
    'variable valve timing intake bank 1 actual',
    'variable valve timing intake bank 2 actual',
  ],
};

List<String> _resolveNames(List<String> headerCells) {
  final raw = <String>[];
  for (var i = 0; i < headerCells.length; i++) {
    var name = headerCells[i].split('|').first.trim();
    if (name.isEmpty) name = 'Channel ${i + 1}';
    raw.add(name);
  }

  final occurrences = <String, int>{};
  for (final name in raw) {
    occurrences[name] = (occurrences[name] ?? 0) + 1;
  }

  final seen = <String, int>{};
  final resolved = <String>[];

  for (final name in raw) {
    final total = occurrences[name]!;
    final index = seen[name] ?? 0;
    seen[name] = index + 1;

    if (total == 1) {
      resolved.add(name);
      continue;
    }

    final family = _truncatedFamily[name];
    if (family != null && family.length == total) {
      resolved.add(family[index]);
    } else {
      resolved.add('$name (${index + 1})');
    }
  }

  return resolved;
}
