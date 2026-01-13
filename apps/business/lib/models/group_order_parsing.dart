int parseGroupOrderInt(dynamic value) {
  if (value == null) return 0;
  if (value is num) return value.round();
  final raw = value.toString().trim();
  if (raw.isEmpty) return 0;
  final parsed = int.tryParse(raw);
  if (parsed != null) return parsed;
  final parsedDouble = double.tryParse(raw);
  if (parsedDouble != null) return parsedDouble.round();
  return 0;
}
