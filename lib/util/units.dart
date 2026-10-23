/// Unit inference and small display helpers.
///
/// SCT CSV headers embed the unit in the name ("engine coolant temp F",
/// "manifold absolute pressure kPA") and many channels have no unit at all.
/// This is the single place that maps names to display units, so the rest of
/// the app never guesses.
String inferUnit(String name) {
  final n = name.toLowerCase();

  if (n.contains('kpa')) return 'kPa';
  if (n.contains('psi')) return 'psi';
  if (n.contains('lb per min') || n.contains('lb/min')) return 'lb/min';
  if (n.contains('mph')) return 'mph';
  if (n.contains('km/h')) return 'km/h';
  if (n.contains('rpm')) return 'rpm';
  if (n.contains('voltage')) return 'V';
  if (n.contains('duty')) return '%';
  if (n.contains('trim')) return '%';
  if (n.contains(' afr') || n.startsWith('afr')) return 'AFR';
  if (n.contains('lambse') || n.contains('lambda')) return 'λ';
  if (n.endsWith(' f') || n.contains('temp f')) return '°F';
  if (n.endsWith(' c') || n.contains('temp c')) return '°C';
  if (n.contains('advance') || n.contains('timing') || n.contains('adv')) {
    return '°';
  }
  if (n.contains('%') || n.contains('percent') || n.contains('_pct')) {
    return '%';
  }

  return '';
}

/// Compact numeric formatting for a channel readout.
String formatValue(double? value, {int decimals = 2}) {
  if (value == null || !value.isFinite) return '--';
  final magnitude = value.abs();
  if (magnitude >= 1000) return value.toStringAsFixed(0);
  if (magnitude >= 100) return value.toStringAsFixed(1);
  return value.toStringAsFixed(decimals);
}

/// `m:ss.s` clock used on the time axis.
String formatClock(double seconds) {
  if (!seconds.isFinite || seconds < 0) return '0:00.0';
  final minutes = seconds ~/ 60;
  final rest = seconds - minutes * 60;
  return '$minutes:${rest.toStringAsFixed(1).padLeft(4, '0')}';
}
