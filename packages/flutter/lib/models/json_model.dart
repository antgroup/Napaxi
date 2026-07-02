/// Shared helpers for decoding SDK JSON model maps.
///
/// The SDK model layer intentionally remains thin: it accepts contract-owned
/// camelCase/snake_case aliases, preserves unknown adapter fields, and lets the
/// core/contract own business semantics and validation defaults.
library;

/// Returns a shallow copy that model instances can keep as their raw payload.
Map<String, dynamic> jsonModelRaw(Map<String, dynamic> map) =>
    Map<String, dynamic>.from(map);

/// Merges a model's canonical encoded fields over its raw payload.
///
/// Unknown fields survive round-trips while normalized fields use the SDK's
/// canonical camelCase representation.
Map<String, dynamic> mergePreservedJsonModel(
  Map<String, dynamic> raw,
  Map<String, dynamic> canonical,
) {
  final merged = Map<String, dynamic>.from(raw);
  merged.addAll(canonical);
  return merged;
}

DateTime? jsonDateTimeField(Map<String, dynamic> map, List<String> keys) {
  for (final key in keys) {
    final value = map[key];
    if (value is String) return DateTime.tryParse(value);
  }
  return null;
}

int jsonIntField(
  Map<String, dynamic> map,
  List<String> keys, {
  int defaultValue = 0,
}) {
  for (final key in keys) {
    final value = map[key];
    if (value is int) return value;
    if (value is num) return value.toInt();
  }
  return defaultValue;
}

double jsonDoubleField(
  Map<String, dynamic> map,
  List<String> keys, {
  double defaultValue = 0,
}) {
  for (final key in keys) {
    final value = map[key];
    if (value is num) return value.toDouble();
  }
  return defaultValue;
}

bool jsonBoolField(
  Map<String, dynamic> map,
  List<String> keys, {
  bool defaultValue = false,
}) {
  for (final key in keys) {
    final value = map[key];
    if (value is bool) return value;
  }
  return defaultValue;
}

String? jsonStringField(
  Map<String, dynamic> map,
  List<String> keys, {
  bool nonEmpty = true,
}) {
  for (final key in keys) {
    final value = map[key];
    if (value is String && (!nonEmpty || value.isNotEmpty)) return value;
  }
  return null;
}

List<String> jsonStringListField(Map<String, dynamic> map, List<String> keys) {
  for (final key in keys) {
    final value = map[key];
    if (value is List) return value.map((item) => item.toString()).toList();
  }
  return const [];
}

List<T> jsonObjectListField<T>(
  Object? value,
  T Function(Map<String, dynamic>) convert,
) {
  if (value is! List) return const [];
  return value
      .whereType<Map>()
      .map((item) => convert(Map<String, dynamic>.from(item)))
      .toList();
}
