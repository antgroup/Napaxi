import 'dart:convert';

/// Definition of a custom tool to register with the Napaxi engine.
///
/// Custom tools are executed on the host (Dart) side when called by the AI agent.
/// The engine dispatches tool requests via a stream; the host processes them
/// asynchronously; the engine forwards results back to the agent. Register a
/// host-side executor with [NapaxiEngine.startToolRequestListener].
class CustomToolDef {
  final String name;
  final String description;
  final Map<String, dynamic> parameters;
  final String effect;

  const CustomToolDef({
    required this.name,
    required this.description,
    required this.parameters,
    this.effect = 'unknown',
  });

  factory CustomToolDef.fromJson(Map<String, dynamic> json) {
    final parameters = json['parameters'];
    return CustomToolDef(
      name: json['name'] as String? ?? '',
      description: json['description'] as String? ?? '',
      parameters: parameters is Map
          ? Map<String, dynamic>.from(parameters)
          : const {'type': 'object', 'properties': {}},
      effect: json['effect'] as String? ?? 'unknown',
    );
  }

  Map<String, dynamic> toJson() => {
        'name': name,
        'description': description,
        'parameters': parameters,
        'effect': effect,
      };
}

/// Request sent when a builtin tool needs explicit user approval.
class McToolApprovalRequest {
  final BigInt requestId;
  final String toolName;
  final String description;
  final String parametersJson;
  final bool allowAlways;

  const McToolApprovalRequest({
    required this.requestId,
    required this.toolName,
    required this.description,
    required this.parametersJson,
    required this.allowAlways,
  });

  Map<String, dynamic> get parameters {
    final decoded = jsonDecode(parametersJson);
    return decoded is Map<String, dynamic> ? decoded : <String, dynamic>{};
  }
}

/// Response returned by the host UI for a tool approval request.
class McToolApprovalResponse {
  final bool approved;
  final bool always;
  final String? message;

  const McToolApprovalResponse({
    required this.approved,
    this.always = false,
    this.message,
  });

  Map<String, dynamic> toJson() => {
        'approved': approved,
        'always': always,
        if (message != null) 'message': message,
      };
}

/// Host callback invoked to obtain a [McToolApprovalResponse] for a pending
/// tool approval request.
typedef McToolApprovalHandler = Future<McToolApprovalResponse> Function(
  McToolApprovalRequest request,
);
