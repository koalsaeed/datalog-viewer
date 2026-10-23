import '../models/vehicle_log.dart';
import 'log_builder.dart';
import 'log_error.dart';

/// True when the text looks like a Race Technology VBO file.
bool looksLikeVbo(String text) {
  final head = text.trimLeft().toLowerCase();
  return head.startsWith('[header]');
}

/// Reads a Race Technology `.vbo` log.
///
/// The file is plain text split into `[header]`, `[column names]` and `[data]`
/// sections; the column-names section holds one comma-separated line.
VehicleLog parseVbo(String text, {required String fileName}) {
  final lines = text.split('\n');

  var namesAt = -1;
  var dataAt = -1;
  for (var i = 0; i < lines.length; i++) {
    final line = lines[i].trim().toLowerCase();
    if (line.startsWith('[column names]')) namesAt = i;
    if (line.startsWith('[data]')) dataAt = i;
  }

  if (namesAt < 0 || dataAt < 0 || dataAt <= namesAt) {
    throw LogParseException('VBO file is missing its column or data section.');
  }

  var headerLine = namesAt + 1;
  while (headerLine < lines.length && lines[headerLine].trim().isEmpty) {
    headerLine++;
  }
  if (headerLine >= dataAt) {
    throw LogParseException('VBO file has no column names.');
  }

  final names = lines[headerLine]
      .split(',')
      .map((cell) => cell.trim().replaceAll('"', ''))
      .toList();
  if (names.length < 2) {
    throw LogParseException('VBO file has only one column.');
  }

  final columns = List<List<double>>.generate(names.length, (_) => <double>[]);
  final time = <double>[];
  var timeIndex = names.indexWhere(
    (name) => name.toLowerCase().contains('time'),
  );
  if (timeIndex < 0) timeIndex = 0;

  for (var i = dataAt + 1; i < lines.length; i++) {
    final raw = lines[i].trim();
    if (raw.isEmpty) continue;

    final cells = raw.split(',');
    if (cells.length < names.length) continue;

    final t = double.tryParse(cells[timeIndex].trim());
    if (t == null || !t.isFinite) continue;

    time.add(t);
    for (var c = 0; c < names.length; c++) {
      final value = double.tryParse(cells[c].trim());
      columns[c].add(value == null ? double.nan : value);
    }
  }

  if (time.isEmpty) {
    throw LogParseException('No samples found in the VBO file.');
  }

  return buildLog(
    fileName: fileName,
    time: time,
    names: names,
    units: List<String>.filled(names.length, ''),
    columns: columns,
    skipColumn: timeIndex,
  );
}
