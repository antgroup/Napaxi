/// MCP server connection state.
enum McpConnectionState {
  disconnected,
  configured,
  connecting,
  connected,
  error,
}

/// MCP server information.
class McpServerInfo {
  final String name;
  final String url;
  final bool connected;
  final String? status;
  final List<String> tools;
  final String? error;
  final bool authRequired;
  final bool oauthConnected;
  final bool oauthPending;

  const McpServerInfo({
    required this.name,
    required this.url,
    required this.connected,
    this.status,
    this.tools = const [],
    this.error,
    this.authRequired = false,
    this.oauthConnected = false,
    this.oauthPending = false,
  });

  McpConnectionState get connectionState {
    switch (status) {
      case 'connected':
        return McpConnectionState.connected;
      case 'connecting':
        return McpConnectionState.connecting;
      case 'error':
        return McpConnectionState.error;
      case 'configured':
        return McpConnectionState.configured;
    }
    // Fallback for cores that predate the explicit `status` field.
    if (error != null && error!.isNotEmpty) return McpConnectionState.error;
    if (oauthPending) return McpConnectionState.connecting;
    if (connected) return McpConnectionState.connected;
    return McpConnectionState.disconnected;
  }

  factory McpServerInfo.fromMap(Map<String, dynamic> map) {
    return McpServerInfo(
      name: map['name'] as String? ?? '',
      url: map['url'] as String? ?? '',
      connected: map['connected'] as bool? ?? false,
      status: map['status'] as String?,
      tools:
          (map['tools'] as List<dynamic>?)?.map((e) => e as String).toList() ??
              [],
      error: map['error'] as String?,
      authRequired: map['authRequired'] as bool? ?? false,
      oauthConnected: map['oauthConnected'] as bool? ?? false,
      oauthPending: map['oauthPending'] as bool? ?? false,
    );
  }

  @override
  String toString() => 'McpServerInfo($name, url=$url, connected=$connected, '
      'status=$status, tools=${tools.length}, authRequired=$authRequired, '
      'oauthConnected=$oauthConnected, oauthPending=$oauthPending, '
      'error=$error)';
}

/// MCP tool information.
class McpToolInfo {
  final String name;
  final String serverName;

  const McpToolInfo({
    required this.name,
    required this.serverName,
  });

  factory McpToolInfo.fromMap(Map<String, dynamic> map) {
    return McpToolInfo(
      name: map['name'] as String? ?? '',
      serverName: map['serverName'] as String? ?? '',
    );
  }

  @override
  String toString() => 'McpToolInfo($name, server=$serverName)';
}

/// Result from adding/activating an MCP server.
class McpServerActionResult {
  final String name;
  final List<String> toolsLoaded;
  final String? message;
  final String? error;

  const McpServerActionResult({
    required this.name,
    this.toolsLoaded = const [],
    this.message,
    this.error,
  });

  bool get isSuccess => error == null || error!.isEmpty;

  factory McpServerActionResult.fromJson(Map<String, dynamic> json) {
    return McpServerActionResult(
      name: json['name'] as String? ?? '',
      toolsLoaded: (json['tools_loaded'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          [],
      message: json['message'] as String?,
      error: json['error'] as String?,
    );
  }

  @override
  String toString() =>
      'McpServerActionResult($name, toolsLoaded=${toolsLoaded.length}, '
      'isSuccess=$isSuccess, error=$error)';
}

/// Result from starting an MCP OAuth authorization flow.
class McpOAuthStartResult {
  final String name;
  final String authorizationUrl;
  final String state;
  final String redirectUri;
  final String? error;

  const McpOAuthStartResult({
    required this.name,
    required this.authorizationUrl,
    required this.state,
    required this.redirectUri,
    this.error,
  });

  bool get isSuccess => error == null || error!.isEmpty;

  factory McpOAuthStartResult.fromJson(Map<String, dynamic> json) {
    return McpOAuthStartResult(
      name: json['name'] as String? ?? '',
      authorizationUrl: json['authorization_url'] as String? ?? '',
      state: json['state'] as String? ?? '',
      redirectUri: json['redirect_uri'] as String? ?? '',
      error: json['error'] as String?,
    );
  }

  @override
  String toString() =>
      'McpOAuthStartResult($name, isSuccess=$isSuccess, error=$error)';
}
