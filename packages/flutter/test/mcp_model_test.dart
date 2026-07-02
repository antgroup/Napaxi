import 'package:flutter_test/flutter_test.dart';
import 'package:napaxi_flutter/models/mcp.dart';

void main() {
  group('McpServerInfo.fromMap', () {
    test('decodes a full map', () {
      final info = McpServerInfo.fromMap({
        'name': 'files',
        'url': 'https://mcp.example/files',
        'connected': true,
        'tools': ['read', 'write'],
        'error': null,
        'authRequired': true,
        'oauthConnected': true,
        'oauthPending': false,
      });

      expect(info.name, 'files');
      expect(info.url, 'https://mcp.example/files');
      expect(info.connected, isTrue);
      expect(info.tools, ['read', 'write']);
      expect(info.authRequired, isTrue);
      expect(info.oauthConnected, isTrue);
    });

    test('applies defaults for missing fields', () {
      final info = McpServerInfo.fromMap({});

      expect(info.name, '');
      expect(info.url, '');
      expect(info.connected, isFalse);
      expect(info.tools, isEmpty);
      expect(info.error, isNull);
      expect(info.authRequired, isFalse);
      expect(info.oauthConnected, isFalse);
      expect(info.oauthPending, isFalse);
    });
  });

  group('McpServerInfo.connectionState precedence', () {
    test('non-empty error wins over every other flag', () {
      final info = McpServerInfo.fromMap({
        'connected': true,
        'oauthPending': true,
        'error': 'boom',
      });
      expect(info.connectionState, McpConnectionState.error);
    });

    test('empty error string is not treated as an error', () {
      final info = McpServerInfo.fromMap({'connected': true, 'error': ''});
      expect(info.connectionState, McpConnectionState.connected);
    });

    test('oauthPending maps to connecting when no error', () {
      final info = McpServerInfo.fromMap({
        'connected': true,
        'oauthPending': true,
      });
      expect(info.connectionState, McpConnectionState.connecting);
    });

    test('connected with no error or pending maps to connected', () {
      final info = McpServerInfo.fromMap({'connected': true});
      expect(info.connectionState, McpConnectionState.connected);
    });

    test('default maps to disconnected', () {
      final info = McpServerInfo.fromMap({});
      expect(info.connectionState, McpConnectionState.disconnected);
    });
  });

  group('McpToolInfo.fromMap', () {
    test('decodes name and server', () {
      final tool = McpToolInfo.fromMap({'name': 'read', 'serverName': 'files'});
      expect(tool.name, 'read');
      expect(tool.serverName, 'files');
    });

    test('defaults to empty strings', () {
      final tool = McpToolInfo.fromMap({});
      expect(tool.name, '');
      expect(tool.serverName, '');
    });
  });

  group('McpServerActionResult.fromJson', () {
    test('maps the snake_case tools_loaded key', () {
      final result = McpServerActionResult.fromJson({
        'name': 'files',
        'tools_loaded': ['read', 'write'],
        'message': 'ok',
      });
      expect(result.name, 'files');
      expect(result.toolsLoaded, ['read', 'write']);
      expect(result.isSuccess, isTrue);
    });

    test('isSuccess is false when error is non-empty', () {
      final result = McpServerActionResult.fromJson({
        'name': 'files',
        'error': 'failed',
      });
      expect(result.isSuccess, isFalse);
      expect(result.toolsLoaded, isEmpty);
    });

    test('isSuccess is true for empty error string', () {
      final result = McpServerActionResult.fromJson({'name': 'x', 'error': ''});
      expect(result.isSuccess, isTrue);
    });
  });

  group('McpOAuthStartResult.fromJson', () {
    test('maps snake_case url and redirect keys', () {
      final result = McpOAuthStartResult.fromJson({
        'name': 'files',
        'authorization_url': 'https://auth.example/start',
        'state': 'state-token',
        'redirect_uri': 'app://oauth/callback',
      });
      expect(result.authorizationUrl, 'https://auth.example/start');
      expect(result.state, 'state-token');
      expect(result.redirectUri, 'app://oauth/callback');
      expect(result.isSuccess, isTrue);
    });

    test('defaults missing fields and flags error', () {
      final result = McpOAuthStartResult.fromJson({'error': 'denied'});
      expect(result.name, '');
      expect(result.authorizationUrl, '');
      expect(result.state, '');
      expect(result.redirectUri, '');
      expect(result.isSuccess, isFalse);
    });
  });
}
