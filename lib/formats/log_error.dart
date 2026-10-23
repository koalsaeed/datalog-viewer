/// Raised when a log file cannot be understood.
class LogParseException implements Exception {
  LogParseException(this.message);

  final String message;

  @override
  String toString() => message;
}
