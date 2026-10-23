import 'dart:convert';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';

import '../formats/log_error.dart';
import '../formats/mlg_reader.dart';
import '../formats/vbo_reader.dart';
import '../models/vehicle_log.dart';
import '../parsers/csv_parser.dart';

/// Opens a datalog and turns it into a [VehicleLog].
///
/// Detection is content-first: a file renamed to `.csv` still parses as MLG,
/// and a `.txt` VBO still works. The extension list below only tells the
/// Android picker what to show.
class LogLoader {
  static const List<String> _extensions = <String>[
    'csv',
    'tsv',
    'txt',
    'log',
    'msl',
    'vbo',
    'mlg',
  ];

  /// Returns `null` when the user cancels the picker.
  static Future<VehicleLog?> pickLog() async {
    final XFile? file = await openFile(
      acceptedTypeGroups: <XTypeGroup>[
        XTypeGroup(label: 'Datalogs', extensions: _extensions),
      ],
    );
    if (file == null) return null;

    final bytes = await file.readAsBytes();
    return parseLogBytes(bytes, fileName: file.name);
  }

  static VehicleLog parseLogBytes(
    Uint8List bytes, {
    required String fileName,
  }) {
    try {
      if (_isHpLog(bytes)) {
        throw LogParseException(
          'HP Tuners .hpl is a binary format that is not supported yet.',
        );
      }

      if (looksLikeMlg(bytes)) {
        return parseMlg(bytes, fileName: fileName);
      }

      final text = _decode(bytes);
      if (looksLikeVbo(text)) {
        return parseVbo(text, fileName: fileName);
      }
      return parseCsvLog(text, fileName: fileName);
    } on LogParseException {
      rethrow;
    } on RangeError {
      throw LogParseException('The file ends unexpectedly (truncated?).');
    } on FormatException catch (error) {
      throw LogParseException('Unreadable file: ${error.message}');
    }
  }

  /// `HPT ` — HP Tuners VCM Scanner.
  static bool _isHpLog(Uint8List bytes) {
    return bytes.length >= 4 &&
        bytes[0] == 0x48 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x54 &&
        bytes[3] == 0x20;
  }

  /// SCT writes plain ASCII/UTF-8, but a BOM or a Windows codepage sneaks in
  /// often enough that a hard failure is not acceptable.
  static String _decode(Uint8List bytes) {
    if (bytes.length >= 3 &&
        bytes[0] == 0xEF &&
        bytes[1] == 0xBB &&
        bytes[2] == 0xBF) {
      return utf8.decode(bytes.sublist(3), allowMalformed: true);
    }
    try {
      return utf8.decode(bytes);
    } on FormatException {
      return latin1.decode(bytes);
    }
  }
}
