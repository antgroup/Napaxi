import 'package:flutter_test/flutter_test.dart';
import 'package:napaxi_flutter/api/json_codec.dart';

/// `json_codec.dart` is the FRB/FFI unwrap layer: every bridge call returns a
/// JSON string and these helpers turn it into typed Dart values, surface the
/// `{"error": ...}` envelope the Rust `wire_string_or_envelope` path emits, and
/// reject malformed shapes. The runtime contract is exercised here so a drift
/// in envelope handling is caught in unit tests, not in the field.
void main() {
  group('decode helpers', () {
    test('decodeJsonObject returns a string-keyed map', () {
      final map = decodeJsonObject('{"a": 1, "b": "two"}');
      expect(map['a'], 1);
      expect(map['b'], 'two');
    });

    test('decodeJsonObject throws when the payload is not an object', () {
      expect(() => decodeJsonObject('[1, 2, 3]'), throwsFormatException);
    });

    test('decodeJsonArray returns the list', () {
      expect(decodeJsonArray('[1, 2, 3]'), [1, 2, 3]);
    });

    test('decodeJsonArray throws when the payload is not an array', () {
      expect(() => decodeJsonArray('{"a": 1}'), throwsFormatException);
    });

    test('asJsonObject / asJsonArray return null for the wrong shape', () {
      expect(asJsonObject([1, 2]), isNull);
      expect(asJsonArray({'a': 1}), isNull);
      expect(asJsonObject({'a': 1}), isNotNull);
      expect(asJsonArray([1]), isNotNull);
    });
  });

  group('error envelope handling', () {
    test('jsonErrorMessage extracts the bridge error envelope', () {
      final decoded = decodeJsonValue('{"error": {"code": "x", "message": "boom"}}');
      final message = jsonErrorMessage(decoded);
      expect(message, isNotNull);
      expect(message, contains('boom'));
    });

    test('jsonErrorMessage returns null for a success envelope', () {
      final decoded = decodeJsonValue('{"ok": true, "value": []}');
      expect(jsonErrorMessage(decoded), isNull);
    });

    test('throwIfJsonError throws on an error envelope and is a no-op on success', () {
      expect(
        () => throwIfJsonError(decodeJsonValue('{"error": "nope"}')),
        throwsException,
      );
      expect(
        () => throwIfJsonError(decodeJsonValue('{"ok": true}')),
        returnsNormally,
      );
    });
  });

  group('typed list decoding', () {
    test('decodeJsonObjectList converts each object and skips non-objects', () {
      final names = decodeJsonObjectList<String>(
        '[{"name": "a"}, 7, {"name": "b"}]',
        (m) => m['name'] as String,
      );
      expect(names, ['a', 'b']);
    });

    test('decodeJsonObjectList throws when the root is not an array', () {
      expect(
        () => decodeJsonObjectList<String>('{"name": "a"}', (m) => m['name'] as String),
        throwsFormatException,
      );
    });
  });
}
