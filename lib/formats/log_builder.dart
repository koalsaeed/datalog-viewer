import 'dart:typed_data';

import '../models/vehicle_log.dart';
import '../util/units.dart';

/// Turns parallel channel lists into the app's [VehicleLog] shape.
VehicleLog buildLog({
  required String fileName,
  required List<double> time,
  required List<String> names,
  required List<String> units,
  required List<List<double>> columns,
  int? skipColumn,
}) {
  final count = time.length;
  final start = count > 0 ? time.first : 0.0;

  final timeArray = Float64List(count);
  for (var i = 0; i < count; i++) {
    timeArray[i] = time[i] - start;
  }

  final channels = <LogChannel>[];
  for (var c = 0; c < columns.length; c++) {
    if (c == skipColumn) continue;

    final values = Float64List(count);
    var min = double.infinity;
    var max = double.negativeInfinity;
    var valid = 0;

    for (var i = 0; i < count; i++) {
      final value = columns[c][i];
      values[i] = value;
      if (value.isFinite) {
        valid++;
        if (value < min) min = value;
        if (value > max) max = value;
      }
    }

    final unit = units[c].isEmpty ? inferUnit(names[c]) : units[c];
    channels.add(
      LogChannel(
        name: names[c],
        unit: unit,
        values: values,
        min: valid == 0 ? 0 : min,
        max: valid == 0 ? 0 : max,
        validCount: valid,
      ),
    );
  }

  return VehicleLog(
    fileName: fileName,
    time: timeArray,
    channels: channels,
    startTime: start,
    sampleCount: count,
  );
}
