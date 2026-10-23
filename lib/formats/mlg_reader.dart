import 'dart:typed_data';

import '../models/vehicle_log.dart';
import 'log_builder.dart';
import 'log_error.dart';

/// True when the bytes open with the EFI Analytics `MLVLG` signature.
bool looksLikeMlg(Uint8List bytes) {
  if (bytes.length < 8) return false;
  final head = String.fromCharCodes(bytes.sublist(0, 6)).replaceAll('"', '');
  return head == 'MLVLG';
}

/// Reads a TunerStudio / MegaLogViewer binary log (`.mlg`, versions 1 and 2).
///
/// Layout follows the published EFI Analytics specification:
///   header, field descriptors, bit-field names, free-form info text,
///   then fixed-size blocks. Block type 0 is a sample, type 1 is a marker.
///
/// The per-record timestamp is a 16-bit millisecond counter, so it wraps every
/// 65.5 s; the delta is unwrapped here to keep the time axis monotonic.
VehicleLog parseMlg(Uint8List bytes, {required String fileName}) {
  final data = ByteData.sublistView(bytes);
  var offset = 0;

  String readTrimmed(int length) {
    final start = offset;
    offset += length;
    if (start >= bytes.length) return '';
    final limit = start + length < bytes.length ? start + length : bytes.length;
    var end = start;
    while (end < limit && bytes[end] != 0) {
      end++;
    }
    return String.fromCharCodes(bytes.sublist(start, end)).trim();
  }

  int readInt8() {
    final value = data.getInt8(offset);
    offset += 1;
    return value;
  }

  int readInt16() {
    final value = data.getInt16(offset, Endian.little);
    offset += 2;
    return value;
  }

  int readInt32() {
    final value = data.getInt32(offset, Endian.little);
    offset += 4;
    return value;
  }

  final magic = readTrimmed(6).replaceAll('"', '');
  if (magic != 'MLVLG') {
    throw LogParseException('Not an MLG file.');
  }

  final version = readInt16();
  if (version != 1 && version != 2) {
    throw LogParseException('MLG version $version is not supported.');
  }

  readInt32(); // capture timestamp, not needed for display

  final infoDataStart = version == 2 ? readInt32() : readInt16();
  final dataBeginIndex = readInt32();
  final recordLength = readInt16();
  final fieldCount = readInt16();

  if (fieldCount <= 0 || fieldCount > 512) {
    throw LogParseException('MLG header is damaged.');
  }

  final descriptorSize = version == 2 ? 89 : 55;
  final names = <String>[];
  final units = <String>[];
  final types = <int>[];
  final scales = <double>[];
  final transforms = <double>[];

  for (var i = 0; i < fieldCount; i++) {
    final start = offset;
    final type = readInt8();
    final name = readTrimmed(34);
    final unit = readTrimmed(10);
    readInt8(); // display style

    var scale = 1.0;
    var transform = 0.0;

    if (type < 10) {
      scale = data.getFloat32(offset, Endian.little);
      offset += 4;
      transform = data.getFloat32(offset, Endian.little);
      offset += 4;
      offset += 1; // digits
      if (version == 2) offset += 34; // category
    } else {
      offset += 1; // bit-field style
      offset += 4; // bit-field names index
      offset += 1; // bit count
      offset += 3; // unused
      if (version == 2) offset += 34; // category
    }

    // Trust the spec's descriptor size over the hand-counted fields.
    offset = start + descriptorSize;

    names.add(name.isEmpty ? 'Channel ${i + 1}' : name);
    units.add(unit);
    types.add(type);
    scales.add(scale);
    transforms.add(transform);
  }

  // Field metadata is followed by free-form text; skip straight to the data.
  offset = dataBeginIndex;
  if (offset <= 0 || offset >= bytes.length) {
    throw LogParseException('MLG data offset is out of range.');
  }

  final columns = List<List<double>>.generate(fieldCount, (_) => <double>[]);
  final timestamps = <double>[];

  var previousRaw = 0;
  var absoluteMs = 0.0;
  var first = true;

  while (offset + 4 <= bytes.length) {
    final recordStart = offset;
    final blockType = bytes[offset];
    offset += 2; // type + counter

    if (blockType == 1) {
      offset += 2 + 50; // timestamp + marker message
      offset = recordLength > 0 ? recordStart + recordLength : offset;
      continue;
    }
    if (blockType != 0) break;

    final raw = data.getUint16(offset, Endian.little);
    offset += 2;

    if (first) {
      absoluteMs = raw.toDouble();
      first = false;
    } else {
      var delta = raw - previousRaw;
      if (delta < 0) delta += 65536;
      absoluteMs += delta;
    }
    previousRaw = raw;
    timestamps.add(absoluteMs / 1000.0);

    for (var f = 0; f < fieldCount; f++) {
      double value;
      switch (types[f]) {
        case 0:
          value = bytes[offset].toDouble();
          offset += 1;
          break;
        case 1:
          value = data.getInt8(offset).toDouble();
          offset += 1;
          break;
        case 2:
          value = data.getUint16(offset, Endian.little).toDouble();
          offset += 2;
          break;
        case 3:
          value = data.getInt16(offset, Endian.little).toDouble();
          offset += 2;
          break;
        case 4:
          value = data.getUint32(offset, Endian.little).toDouble();
          offset += 4;
          break;
        case 5:
          value = data.getInt32(offset, Endian.little).toDouble();
          offset += 4;
          break;
        case 6:
          value = data.getInt64(offset, Endian.little).toDouble();
          offset += 8;
          break;
        case 7:
          value = data.getFloat32(offset, Endian.little);
          offset += 4;
          break;
        case 10:
          value = bytes[offset].toDouble();
          offset += 1;
          break;
        case 11:
          value = data.getUint16(offset, Endian.little).toDouble();
          offset += 2;
          break;
        case 12:
          value = data.getUint32(offset, Endian.little).toDouble();
          offset += 4;
          break;
        default:
          value = double.nan;
          offset += 1;
          break;
      }
      columns[f].add(value * scales[f] + transforms[f]);
    }

    offset = recordLength > 0 ? recordStart + recordLength : offset + 1;
  }

  if (timestamps.isEmpty) {
    throw LogParseException('No samples found in the MLG file.');
  }

  // A `Time` channel is authoritative when the logger wrote one.
  var timeColumn = -1;
  for (var f = 0; f < fieldCount; f++) {
    final lower = names[f].toLowerCase();
    if (lower == 'time' || lower.contains('time')) {
      timeColumn = f;
      break;
    }
  }

  final time = timeColumn >= 0 && columns[timeColumn].isNotEmpty
      ? columns[timeColumn]
      : timestamps;

  return buildLog(
    fileName: fileName,
    time: time,
    names: names,
    units: units,
    columns: columns,
    skipColumn: timeColumn >= 0 ? timeColumn : null,
  );
}
