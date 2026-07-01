import 'dart:convert';

import 'api/json_codec.dart';
import 'models/mcp.dart';
import 'generated/bridge/mcp.dart' as rust_mcp;

/// MCP server management API.
///
/// Provides methods to add, remove, activate, deactivate, and list MCP servers,
/// as well as list the tools they provide.
///
/// Obtain an instance via [NapaxiEngine.mcp].
class McpApi {
  final int Function() _getHandle;
  final String _userId;

  McpApi(this._getHandle, this._userId);

  int get _handle => _getHandle();

  // ==========================================================================
  // Server lifecycle
  // ==========================================================================

  /// Add an MCP server and immediately activate it.
  ///
  /// [name] is a unique server name (e.g. "notion", "github").
  /// [url] is the server endpoint URL.
  /// [headers] is an optional map of custom HTTP headers (e.g. auth tokens).
  ///
  /// Returns an [McpServerActionResult] indicating whether the server was
  /// added successfully and which tools were loaded.
  Future<McpServerActionResult> addServer(
    String name,
    String url, {
    Map<String, String>? headers,
    String? transport,
  }) async {
    try {
      final effectiveHeaders = <String, String>{
        if (headers != null) ...headers,
        if (transport != null && transport.isNotEmpty)
          '__napaxi_transport': transport,
      };
      final headersJson =
          effectiveHeaders.isNotEmpty ? jsonEncode(effectiveHeaders) : '{}';
      final resultJson = await rust_mcp.mcpAddServer(
        handle: _handle,
        name: name,
        url: url,
        headersJson: headersJson,
        userId: _userId,
      );
      return McpServerActionResult.fromJson(
        decodeJsonObject(resultJson),
      );
    } catch (e) {
      return McpServerActionResult(
        name: name,
        error: 'addServer failed: $e',
      );
    }
  }

  /// Remove an MCP server (unregister tools, disconnect, delete config).
  ///
  /// Returns `true` on success, `false` on failure.
  Future<bool> removeServer(String name) async {
    try {
      final resultJson = await rust_mcp.mcpRemoveServer(
        handle: _handle,
        name: name,
        userId: _userId,
      );
      final map = decodeJsonObject(resultJson);
      return map['success'] as bool? ?? false;
    } catch (e) {
      return false;
    }
  }

  /// List all configured MCP servers with their status.
  ///
  /// Returns a list of [McpServerInfo] describing each server's connection
  /// state and available tools.
  Future<List<McpServerInfo>> listServers() async {
    try {
      final resultJson = await rust_mcp.mcpListServers(
        handle: _handle,
        userId: _userId,
      );
      return decodeJsonObjectList(resultJson, McpServerInfo.fromMap);
    } catch (e) {
      return [];
    }
  }

  /// Activate an MCP server — connects and registers its tools.
  ///
  /// The server must have been previously added with [addServer].
  /// Returns an [McpServerActionResult] with the tools loaded on success.
  Future<McpServerActionResult> activate(String name) async {
    try {
      final resultJson = await rust_mcp.mcpActivateServer(
        handle: _handle,
        name: name,
        userId: _userId,
      );
      return McpServerActionResult.fromJson(
        decodeJsonObject(resultJson),
      );
    } catch (e) {
      return McpServerActionResult(
        name: name,
        error: 'activate failed: $e',
      );
    }
  }

  /// Start an OAuth authorization flow for an MCP server.
  ///
  /// The returned [McpOAuthStartResult.authorizationUrl] should be opened by
  /// the host app. After the provider redirects back, pass the callback code
  /// and state to [finishOAuth].
  Future<McpOAuthStartResult> startOAuth(
    String name, {
    String redirectUri = 'napaxi://oauth/mcp',
    String? clientId,
    String? clientSecret,
    String? authorizationUrl,
    String? tokenUrl,
    List<String> scopes = const [],
    bool? usePkce,
    Map<String, String> extraParams = const {},
    String? resource,
  }) async {
    try {
      final oauth = <String, dynamic>{
        if (clientId != null && clientId.isNotEmpty) 'client_id': clientId,
        if (clientSecret != null && clientSecret.isNotEmpty)
          'client_secret': clientSecret,
        if (authorizationUrl != null && authorizationUrl.isNotEmpty)
          'authorization_url': authorizationUrl,
        if (tokenUrl != null && tokenUrl.isNotEmpty) 'token_url': tokenUrl,
        if (scopes.isNotEmpty) 'scopes': scopes,
        if (usePkce != null) 'use_pkce': usePkce,
        if (extraParams.isNotEmpty) 'extra_params': extraParams,
        if (resource != null && resource.isNotEmpty) 'resource': resource,
      };
      final resultJson = await rust_mcp.mcpStartOauth(
        handle: _handle,
        name: name,
        userId: _userId,
        redirectUri: redirectUri,
        oauthJson: oauth.isEmpty ? '{}' : jsonEncode(oauth),
      );
      return McpOAuthStartResult.fromJson(
        decodeJsonObject(resultJson),
      );
    } catch (e) {
      return McpOAuthStartResult(
        name: name,
        authorizationUrl: '',
        state: '',
        redirectUri: redirectUri,
        error: 'startOAuth failed: $e',
      );
    }
  }

  /// Finish an MCP OAuth flow and activate the server with the received token.
  Future<McpServerActionResult> finishOAuth(
    String name, {
    required String code,
    required String state,
  }) async {
    try {
      final resultJson = await rust_mcp.mcpFinishOauth(
        handle: _handle,
        name: name,
        userId: _userId,
        code: code,
        state: state,
      );
      return McpServerActionResult.fromJson(
        decodeJsonObject(resultJson),
      );
    } catch (e) {
      return McpServerActionResult(
        name: name,
        error: 'finishOAuth failed: $e',
      );
    }
  }

  /// Deactivate an MCP server — unregisters tools and disconnects, but keeps
  /// the config so it can be activated later.
  ///
  /// Returns `true` on success, `false` on failure.
  Future<bool> deactivate(String name) async {
    try {
      final resultJson = await rust_mcp.mcpDeactivateServer(
        handle: _handle,
        name: name,
        userId: _userId,
      );
      final map = decodeJsonObject(resultJson);
      return map['success'] as bool? ?? false;
    } catch (e) {
      return false;
    }
  }

  // ==========================================================================
  // Tools
  // ==========================================================================

  /// List tools provided by MCP servers.
  ///
  /// If [serverName] is provided, only tools from that server are returned.
  /// Otherwise, all MCP tools from all active servers are listed.
  Future<List<McpToolInfo>> listTools({String? serverName}) async {
    try {
      final resultJson = await rust_mcp.mcpListTools(
        handle: _handle,
        serverName: serverName ?? '',
        userId: _userId,
      );
      return decodeJsonObjectList(resultJson, McpToolInfo.fromMap);
    } catch (e) {
      return [];
    }
  }
}
