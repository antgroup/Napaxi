import 'package:flutter_test/flutter_test.dart';
import 'package:napaxi_flutter/models/custom_tool.dart';

void main() {
  group('CustomToolDef', () {
    test('round-trips through fromJson/toJson', () {
      final original = CustomToolDef(
        name: 'lookup',
        description: 'Look something up',
        parameters: {
          'type': 'object',
          'properties': {
            'query': {'type': 'string'},
          },
        },
        effect: 'read',
      );

      final decoded = CustomToolDef.fromJson(original.toJson());

      expect(decoded.name, 'lookup');
      expect(decoded.description, 'Look something up');
      expect(decoded.parameters, original.parameters);
      expect(decoded.effect, 'read');
    });

    test('effect defaults to unknown when missing', () {
      final tool = CustomToolDef.fromJson({
        'name': 'x',
        'description': 'd',
        'parameters': {'type': 'object'},
      });
      expect(tool.effect, 'unknown');
    });

    test('name and description default to empty when missing', () {
      final tool = CustomToolDef.fromJson({});
      expect(tool.name, '');
      expect(tool.description, '');
    });

    test('non-map parameters fall back to an empty object schema', () {
      final tool = CustomToolDef.fromJson({
        'name': 'x',
        'parameters': 'not-a-map',
      });
      expect(tool.parameters, {'type': 'object', 'properties': {}});
    });

    test('missing parameters fall back to an empty object schema', () {
      final tool = CustomToolDef.fromJson({'name': 'x'});
      expect(tool.parameters, {'type': 'object', 'properties': {}});
    });
  });

  group('McToolApprovalRequest.parameters', () {
    McToolApprovalRequest requestWith(String parametersJson) =>
        McToolApprovalRequest(
          requestId: BigInt.from(1),
          toolName: 'shell',
          description: 'run a command',
          parametersJson: parametersJson,
          allowAlways: true,
        );

    test('decodes a valid JSON object', () {
      final request = requestWith('{"cmd":"ls","timeout":30}');
      expect(request.parameters, {'cmd': 'ls', 'timeout': 30});
    });

    test('returns empty map for a non-object JSON value', () {
      final request = requestWith('[1,2,3]');
      expect(request.parameters, isEmpty);
    });
  });

  group('McToolApprovalResponse.toJson', () {
    test('omits message when null', () {
      final json = const McToolApprovalResponse(approved: true).toJson();
      expect(json, {'approved': true, 'always': false});
      expect(json.containsKey('message'), isFalse);
    });

    test('includes message and flags when provided', () {
      final json = const McToolApprovalResponse(
        approved: false,
        always: true,
        message: 'denied by user',
      ).toJson();
      expect(json, {
        'approved': false,
        'always': true,
        'message': 'denied by user',
      });
    });
  });
}
