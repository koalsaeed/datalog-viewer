import 'dart:typed_data';

/// One channel (PID) of a datalog: its samples plus the cached value range.
class LogChannel {
  LogChannel({
    required this.name,
    required this.unit,
    required this.values,
    required this.min,
    required this.max,
    required this.validCount,
  });

  final String name;
  final String unit;

  /// One sample per row, aligned with [VehicleLog.time]. May contain NaN.
  final Float64List values;

  final double min;
  final double max;
  final int validCount;

  bool get hasData => validCount > 0 && max > min;

  double? valueAt(int index) {
    if (index < 0 || index >= values.length) return null;
    final value = values[index];
    return value.isFinite ? value : null;
  }
}

/// A parsed datalog file.
class VehicleLog {
  VehicleLog({
    required this.fileName,
    required this.time,
    required this.channels,
    required this.startTime,
    required this.sampleCount,
    this.gapSeconds = 0.1,
  });

  final String fileName;

  /// Seconds relative to [startTime]. Non-uniform by design: the ECU decides.
  final Float64List time;

  final List<LogChannel> channels;

  /// Absolute timestamp of the first sample (some logs do not start at 0).
  final double startTime;

  final int sampleCount;

  /// A sample-to-sample jump larger than this is treated as missing data.
  ///
  /// Derived from the log's own median interval, never a fixed constant: a
  /// 1 Hz logger would otherwise look like one continuous gap.
  final double gapSeconds;

  double get duration => time.isEmpty ? 0 : time.last;

  /// Index of the sample closest to [seconds] (binary search).
  int nearestIndex(double seconds) {
    if (time.isEmpty) return 0;
    if (seconds <= time.first) return 0;
    if (seconds >= time.last) return time.length - 1;

    var low = 0;
    var high = time.length - 1;
    while (low + 1 < high) {
      final mid = (low + high) >> 1;
      if (time[mid] <= seconds) {
        low = mid;
      } else {
        high = mid;
      }
    }
    final lowerGap = seconds - time[low];
    final upperGap = time[high] - seconds;
    return lowerGap <= upperGap ? low : high;
  }
}

/// Picks a gap threshold from the log's own sampling interval.
///
/// Median rather than mean, so a handful of long dropouts cannot drag the
/// threshold up and hide real breaks.
double estimateGapSeconds(Float64List time) {
  if (time.length < 4) return 0.1;

  final deltas = <double>[];
  for (var i = 1; i < time.length; i++) {
    final delta = time[i] - time[i - 1];
    if (delta.isFinite && delta > 0) deltas.add(delta);
  }
  if (deltas.isEmpty) return 0.1;

  deltas.sort();
  final median = deltas[deltas.length ~/ 2];
  final threshold = median * 3;
  return threshold < 0.02 ? 0.02 : threshold;
}
