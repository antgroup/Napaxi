import 'dart:convert';
import 'dart:io';

Map<String, dynamic> contractFixtureObject(String relativePath) {
  return contractFixtureValue(relativePath) as Map<String, dynamic>;
}

/// Decodes a contract fixture into its raw JSON value (object or array).
Object? contractFixtureValue(String relativePath) {
  final file = File('${contractFixtureRoot().path}/$relativePath');
  return jsonDecode(file.readAsStringSync());
}

List<Map<String, dynamic>> contractObjectList(Object? value) => (value as List)
    .map((item) => Map<String, dynamic>.from(item as Map))
    .toList();

Directory contractFixtureRoot() {
  final candidates = [
    Directory('../api_contract/fixtures'),
    Directory('packages/api_contract/fixtures'),
  ];
  for (final candidate in candidates) {
    if (candidate.existsSync()) return candidate;
  }
  throw StateError(
    'Cannot find packages/api_contract/fixtures from ${Directory.current.path}',
  );
}
