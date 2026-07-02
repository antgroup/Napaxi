import 'dart:convert';

Object? decodeJsonValue(String jsonStr) => jsonDecode(jsonStr);

Map<String, dynamic> decodeJsonObject(String jsonStr) {
  final decoded = decodeJsonValue(jsonStr);
  final object = asJsonObject(decoded);
  if (object != null) return object;
  throw FormatException('Expected a JSON object', jsonStr);
}

List<dynamic> decodeJsonArray(String jsonStr) {
  final decoded = decodeJsonValue(jsonStr);
  if (decoded is List) return decoded;
  throw FormatException('Expected a JSON array', jsonStr);
}

Map<String, dynamic>? asJsonObject(Object? value) {
  if (value is Map) return Map<String, dynamic>.from(value);
  return null;
}

List<dynamic>? asJsonArray(Object? value) {
  if (value is List) return value;
  return null;
}

String? jsonErrorMessage(Object? decoded) {
  final object = asJsonObject(decoded);
  final error = object?['error'];
  return error == null ? null : '$error';
}

void throwIfJsonError(Object? decoded) {
  final error = jsonErrorMessage(decoded);
  if (error != null) throw Exception(error);
}

List<T> decodeJsonObjectListFromValue<T>(
  Object? decoded,
  T Function(Map<String, dynamic>) convert,
) {
  final items = asJsonArray(decoded);
  if (items == null) {
    throw FormatException('Expected a JSON array', '$decoded');
  }
  return items
      .whereType<Map>()
      .map((item) => convert(Map<String, dynamic>.from(item)))
      .toList(growable: false);
}

List<T> decodeJsonObjectList<T>(
  String jsonStr,
  T Function(Map<String, dynamic>) convert,
) {
  return decodeJsonObjectListFromValue(decodeJsonValue(jsonStr), convert);
}
