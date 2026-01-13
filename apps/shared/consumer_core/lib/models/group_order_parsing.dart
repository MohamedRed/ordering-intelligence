int parseGroupOrderInt(dynamic value) {
  if (value is int) return value;
  return int.tryParse((value ?? '0').toString()) ?? 0;
}
