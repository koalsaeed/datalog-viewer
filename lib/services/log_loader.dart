import 'dart:convert';

import 'package:file_selector/file_selector.dart';

import '../models/vehicle_log.dart';
import '../parsers/csv_parser.dart';

/// Opens the platform file picker and turns the chosen file into a [VehicleLog].
class LogLoader {
  static const List<String> _extensions = <String>['csv', 'tsv', 'txt', 'log'];

  /// Returns `null` when the user cancels the picker.
  static Future<VehicleLog?> pickLog() async {
    final XFile? file = await openFile(
      acceptedTypeGroups: <XTypeGroup>[
        XTypeGroup(label: 'Datalogs', extensions: _extensions),
      ],
    );
    if (file == null) return null;

    final bytes = await file.readAsBytes();
    return parseCsvLog(_decode(bytes), fileName: file.name);
  }

  /// SCT writes plain ASCII/UTF-8, but a BOM or a Windows codepage sneaks in
  /// often enough that a hard failure is not acceptable.
  static String _decode(List<int> bytes) {
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
