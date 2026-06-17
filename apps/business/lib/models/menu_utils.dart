List<String> splitCsv(String value) {
  return value
      .split(',')
      .map((entry) => entry.trim())
      .where((entry) => entry.isNotEmpty)
      .toList();
}
