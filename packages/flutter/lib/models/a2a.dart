import 'dart:convert';

/// Advertised capabilities and routing details of an agent, exchanged during
/// agent-to-agent (A2A) discovery so a peer knows how to address and invoke it.
class A2AAgentCard {
  /// Creates an agent card describing how this agent can be reached.
  const A2AAgentCard({
    required this.agentId,
    required this.displayName,
    this.description = '',
    this.acceptedInputModes = const [],
    this.acceptedOutputModes = const [],
    this.deepLinkUrl = '',
    this.universalLinkUrl,
    this.capabilities = const [],
    this.requiresUserConfirmation = true,
  });

  final String agentId;
  final String displayName;
  final String description;
  final List<String> acceptedInputModes;
  final List<String> acceptedOutputModes;
  final String deepLinkUrl;
  final String? universalLinkUrl;
  final List<String> capabilities;
  final bool requiresUserConfirmation;

  /// Parses an agent card from its JSON map (accepts camelCase or snake_case).
  factory A2AAgentCard.fromJson(Map<String, dynamic> json) {
    return A2AAgentCard(
      agentId: json['agentId'] as String? ?? json['agent_id'] as String? ?? '',
      displayName: json['displayName'] as String? ??
          json['display_name'] as String? ??
          '',
      description: json['description'] as String? ?? '',
      acceptedInputModes: _strings(
        json['acceptedInputModes'] ?? json['accepted_input_modes'],
      ),
      acceptedOutputModes: _strings(
        json['acceptedOutputModes'] ?? json['accepted_output_modes'],
      ),
      deepLinkUrl: json['deepLinkUrl'] as String? ??
          json['deep_link_url'] as String? ??
          '',
      universalLinkUrl: json['universalLinkUrl'] as String? ??
          json['universal_link_url'] as String?,
      capabilities: _strings(json['capabilities']),
      requiresUserConfirmation: json['requiresUserConfirmation'] as bool? ??
          json['requires_user_confirmation'] as bool? ??
          true,
    );
  }

  Map<String, dynamic> toJson() => {
        'agentId': agentId,
        'displayName': displayName,
        'description': description,
        'acceptedInputModes': acceptedInputModes,
        'acceptedOutputModes': acceptedOutputModes,
        'deepLinkUrl': deepLinkUrl,
        if (universalLinkUrl != null) 'universalLinkUrl': universalLinkUrl,
        'capabilities': capabilities,
        'requiresUserConfirmation': requiresUserConfirmation,
      };
}

/// Identifies one side of an A2A exchange (the sender or recipient), carrying
/// its agent/peer identity and the deep link used to reach it.
class A2AParty {
  /// Creates a party reference for an A2A envelope.
  const A2AParty({
    required this.agentId,
    this.peerId = '',
    this.displayName = '',
    this.deepLinkUrl = '',
  });

  final String agentId;
  final String peerId;
  final String displayName;
  final String deepLinkUrl;

  factory A2AParty.fromJson(Map<String, dynamic> json) => A2AParty(
        agentId:
            json['agentId'] as String? ?? json['agent_id'] as String? ?? '',
        peerId: json['peerId'] as String? ?? json['peer_id'] as String? ?? '',
        displayName: json['displayName'] as String? ??
            json['display_name'] as String? ??
            '',
        deepLinkUrl: json['deepLinkUrl'] as String? ??
            json['deep_link_url'] as String? ??
            '',
      );

  Map<String, dynamic> toJson() => {
        'agentId': agentId,
        if (peerId.isNotEmpty) 'peerId': peerId,
        if (displayName.isNotEmpty) 'displayName': displayName,
        if (deepLinkUrl.isNotEmpty) 'deepLinkUrl': deepLinkUrl,
      };
}

/// Signed, expiring envelope carried over a deep link to deliver an A2A task
/// request, result, or callback between two agents.
class A2ADeepLinkEnvelope {
  /// Creates a deep-link envelope wrapping an A2A payload with anti-replay
  /// metadata (nonce, expiry, idempotency key) and an optional signature.
  const A2ADeepLinkEnvelope({
    this.protocolVersion = 1,
    required this.envelopeId,
    required this.kind,
    required this.sender,
    this.recipient,
    this.task,
    this.result,
    this.callback,
    required this.createdAt,
    required this.expiresAt,
    required this.nonce,
    required this.idempotencyKey,
    this.signatureAlgorithm = '',
    this.signature,
  });

  final int protocolVersion;
  final String envelopeId;
  final String kind;
  final A2AParty sender;
  final A2AParty? recipient;
  final A2ATaskRequest? task;
  final A2ATaskResult? result;
  final A2ACallback? callback;
  final String createdAt;
  final String expiresAt;
  final String nonce;
  final String idempotencyKey;
  final String signatureAlgorithm;
  final String? signature;

  /// Parses an envelope from its JSON map (accepts camelCase or snake_case).
  factory A2ADeepLinkEnvelope.fromJson(Map<String, dynamic> json) {
    return A2ADeepLinkEnvelope(
      protocolVersion:
          _int(json['protocolVersion'] ?? json['protocol_version']) ?? 1,
      envelopeId:
          json['envelopeId'] as String? ?? json['envelope_id'] as String? ?? '',
      kind: json['kind'] as String? ?? 'task_request',
      sender: A2AParty.fromJson(_map(json['sender'])),
      recipient: json['recipient'] is Map
          ? A2AParty.fromJson(_map(json['recipient']))
          : null,
      task: json['task'] is Map
          ? A2ATaskRequest.fromJson(_map(json['task']))
          : null,
      result: json['result'] is Map
          ? A2ATaskResult.fromJson(_map(json['result']))
          : null,
      callback: json['callback'] is Map
          ? A2ACallback.fromJson(_map(json['callback']))
          : null,
      createdAt:
          json['createdAt'] as String? ?? json['created_at'] as String? ?? '',
      expiresAt:
          json['expiresAt'] as String? ?? json['expires_at'] as String? ?? '',
      nonce: json['nonce'] as String? ?? '',
      idempotencyKey: json['idempotencyKey'] as String? ??
          json['idempotency_key'] as String? ??
          '',
      signatureAlgorithm: json['signatureAlgorithm'] as String? ??
          json['signature_algorithm'] as String? ??
          '',
      signature: json['signature'] as String?,
    );
  }

  /// Parses an envelope from a raw JSON string.
  factory A2ADeepLinkEnvelope.fromJsonString(String raw) =>
      A2ADeepLinkEnvelope.fromJson(jsonDecode(raw) as Map<String, dynamic>);

  Map<String, dynamic> toJson() => {
        'protocolVersion': protocolVersion,
        'envelopeId': envelopeId,
        'kind': kind,
        'sender': sender.toJson(),
        if (recipient != null) 'recipient': recipient!.toJson(),
        if (task != null) 'task': task!.toJson(),
        if (result != null) 'result': result!.toJson(),
        if (callback != null) 'callback': callback!.toJson(),
        'createdAt': createdAt,
        'expiresAt': expiresAt,
        'nonce': nonce,
        'idempotencyKey': idempotencyKey,
        if (signatureAlgorithm.isNotEmpty)
          'signatureAlgorithm': signatureAlgorithm,
        if (signature != null) 'signature': signature,
      };

  /// Serializes this envelope to a compact JSON string.
  String toJsonString() => jsonEncode(toJson());
}

/// A unit of work one agent asks another to perform, including the prompt,
/// attached artifacts, and session/output preferences.
class A2ATaskRequest {
  /// Creates an A2A task request.
  const A2ATaskRequest({
    required this.taskId,
    required this.message,
    this.artifacts = const [],
    this.context = const {},
    this.requestedOutputModes = const [],
    this.riskHint = '',
    this.sessionMode = 'isolated',
    this.parentTaskId,
  });

  final String taskId;
  final String message;
  final List<A2AArtifact> artifacts;
  final Map<String, dynamic> context;
  final List<String> requestedOutputModes;
  final String riskHint;
  final String sessionMode;
  final String? parentTaskId;

  /// Parses a task request from its JSON map.
  factory A2ATaskRequest.fromJson(Map<String, dynamic> json) => A2ATaskRequest(
        taskId: json['taskId'] as String? ?? json['task_id'] as String? ?? '',
        message: json['message'] as String? ?? '',
        artifacts: (json['artifacts'] as List? ?? const [])
            .whereType<Map>()
            .map(
                (item) => A2AArtifact.fromJson(Map<String, dynamic>.from(item)))
            .toList(growable: false),
        context: _map(json['context']),
        requestedOutputModes: _strings(
          json['requestedOutputModes'] ?? json['requested_output_modes'],
        ),
        riskHint:
            json['riskHint'] as String? ?? json['risk_hint'] as String? ?? '',
        sessionMode: json['sessionMode'] as String? ??
            json['session_mode'] as String? ??
            'isolated',
        parentTaskId: json['parentTaskId'] as String? ??
            json['parent_task_id'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'taskId': taskId,
        'message': message,
        if (artifacts.isNotEmpty)
          'artifacts': artifacts.map((item) => item.toJson()).toList(),
        if (context.isNotEmpty) 'context': context,
        if (requestedOutputModes.isNotEmpty)
          'requestedOutputModes': requestedOutputModes,
        if (riskHint.isNotEmpty) 'riskHint': riskHint,
        'sessionMode': sessionMode,
        if (parentTaskId != null) 'parentTaskId': parentTaskId,
      };
}

/// A piece of content (inline text or a referenced URI) attached to an A2A
/// task request or result.
class A2AArtifact {
  /// Creates an A2A artifact.
  const A2AArtifact({
    required this.artifactId,
    this.mimeType = '',
    this.name = '',
    this.uri,
    this.text,
    this.metadata = const {},
  });

  final String artifactId;
  final String mimeType;
  final String name;
  final String? uri;
  final String? text;
  final Map<String, dynamic> metadata;

  /// Parses an artifact from its JSON map.
  factory A2AArtifact.fromJson(Map<String, dynamic> json) => A2AArtifact(
        artifactId: json['artifactId'] as String? ??
            json['artifact_id'] as String? ??
            '',
        mimeType:
            json['mimeType'] as String? ?? json['mime_type'] as String? ?? '',
        name: json['name'] as String? ?? '',
        uri: json['uri'] as String?,
        text: json['text'] as String?,
        metadata: _map(json['metadata']),
      );

  Map<String, dynamic> toJson() => {
        'artifactId': artifactId,
        if (mimeType.isNotEmpty) 'mimeType': mimeType,
        if (name.isNotEmpty) 'name': name,
        if (uri != null) 'uri': uri,
        if (text != null) 'text': text,
        if (metadata.isNotEmpty) 'metadata': metadata,
      };
}

/// Deep/universal link the recipient should use to return a task result to
/// the original sender.
class A2ACallback {
  /// Creates a callback target for returning A2A results.
  const A2ACallback({this.deepLinkUrl = '', this.universalLinkUrl});

  final String deepLinkUrl;
  final String? universalLinkUrl;

  /// Parses a callback from its JSON map.
  factory A2ACallback.fromJson(Map<String, dynamic> json) => A2ACallback(
        deepLinkUrl: json['deepLinkUrl'] as String? ??
            json['deep_link_url'] as String? ??
            '',
        universalLinkUrl: json['universalLinkUrl'] as String? ??
            json['universal_link_url'] as String?,
      );

  Map<String, dynamic> toJson() => {
        if (deepLinkUrl.isNotEmpty) 'deepLinkUrl': deepLinkUrl,
        if (universalLinkUrl != null) 'universalLinkUrl': universalLinkUrl,
      };
}

/// Outcome reported back for an A2A task: its status, any output artifacts,
/// and an optional error.
class A2ATaskResult {
  /// Creates an A2A task result.
  const A2ATaskResult({
    required this.taskId,
    required this.status,
    this.message,
    this.artifacts = const [],
    this.runId,
    this.completedAt,
    this.error,
  });

  final String taskId;
  final String status;
  final String? message;
  final List<A2AArtifact> artifacts;
  final String? runId;
  final String? completedAt;
  final String? error;

  /// Parses a task result from its JSON map.
  factory A2ATaskResult.fromJson(Map<String, dynamic> json) => A2ATaskResult(
        taskId: json['taskId'] as String? ?? json['task_id'] as String? ?? '',
        status: json['status'] as String? ?? 'received',
        message: json['message'] as String?,
        artifacts: (json['artifacts'] as List? ?? const [])
            .whereType<Map>()
            .map(
                (item) => A2AArtifact.fromJson(Map<String, dynamic>.from(item)))
            .toList(growable: false),
        runId: json['runId'] as String? ?? json['run_id'] as String?,
        completedAt:
            json['completedAt'] as String? ?? json['completed_at'] as String?,
        error: json['error'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'taskId': taskId,
        'status': status,
        if (message != null) 'message': message,
        if (artifacts.isNotEmpty)
          'artifacts': artifacts.map((item) => item.toJson()).toList(),
        if (runId != null) 'runId': runId,
        if (completedAt != null) 'completedAt': completedAt,
        if (error != null) 'error': error,
      };
}

/// A known remote agent this device has paired with, including its trust
/// level, shared secret, public key, and reachable transport endpoints.
class A2APeer {
  /// Creates a peer record.
  const A2APeer({
    required this.peerId,
    required this.agentId,
    this.displayName = '',
    this.deepLinkUrl = '',
    this.trustLevel = 'untrusted',
    this.sharedSecret = '',
    this.publicKey = '',
    this.endpoints = const [],
    this.lastSeenAt,
    this.createdAt = '',
    this.updatedAt = '',
  });

  final String peerId;
  final String agentId;
  final String displayName;
  final String deepLinkUrl;
  final String trustLevel;
  final String sharedSecret;
  final String publicKey;
  final List<A2APeerEndpoint> endpoints;
  final String? lastSeenAt;
  final String createdAt;
  final String updatedAt;

  /// Parses a peer from its JSON map.
  factory A2APeer.fromJson(Map<String, dynamic> json) => A2APeer(
        peerId: json['peerId'] as String? ?? json['peer_id'] as String? ?? '',
        agentId:
            json['agentId'] as String? ?? json['agent_id'] as String? ?? '',
        displayName: json['displayName'] as String? ??
            json['display_name'] as String? ??
            '',
        deepLinkUrl: json['deepLinkUrl'] as String? ??
            json['deep_link_url'] as String? ??
            '',
        trustLevel: json['trustLevel'] as String? ??
            json['trust_level'] as String? ??
            '',
        sharedSecret: json['sharedSecret'] as String? ??
            json['shared_secret'] as String? ??
            '',
        publicKey:
            json['publicKey'] as String? ?? json['public_key'] as String? ?? '',
        endpoints: (json['endpoints'] as List? ?? const [])
            .whereType<Map>()
            .map((item) =>
                A2APeerEndpoint.fromJson(Map<String, dynamic>.from(item)))
            .toList(growable: false),
        lastSeenAt:
            json['lastSeenAt'] as String? ?? json['last_seen_at'] as String?,
        createdAt:
            json['createdAt'] as String? ?? json['created_at'] as String? ?? '',
        updatedAt:
            json['updatedAt'] as String? ?? json['updated_at'] as String? ?? '',
      );

  Map<String, dynamic> toJson() => {
        'peerId': peerId,
        'agentId': agentId,
        if (displayName.isNotEmpty) 'displayName': displayName,
        if (deepLinkUrl.isNotEmpty) 'deepLinkUrl': deepLinkUrl,
        'trustLevel': trustLevel,
        if (sharedSecret.isNotEmpty) 'sharedSecret': sharedSecret,
        if (publicKey.isNotEmpty) 'publicKey': publicKey,
        if (endpoints.isNotEmpty)
          'endpoints': endpoints.map((item) => item.toJson()).toList(),
        if (lastSeenAt != null) 'lastSeenAt': lastSeenAt,
        'createdAt': createdAt,
        'updatedAt': updatedAt,
      };
}

/// Locally persisted state of an inbound A2A task: the original request and
/// sender plus tracking fields (status, trust, linked session/run, result).
class A2ATaskRecord {
  /// Creates an A2A task record.
  const A2ATaskRecord({
    required this.taskId,
    required this.envelopeId,
    required this.idempotencyKey,
    required this.agentId,
    required this.sender,
    this.callback,
    required this.request,
    required this.status,
    required this.trust,
    required this.source,
    required this.createdAt,
    required this.updatedAt,
    this.sessionId,
    this.peerMessageId,
    this.sessionKey,
    this.runId,
    this.summary,
    this.resultArtifacts = const [],
    this.error,
  });

  final String taskId;
  final String envelopeId;
  final String idempotencyKey;
  final String agentId;
  final A2AParty sender;
  final A2ACallback? callback;
  final A2ATaskRequest request;
  final String status;
  final String trust;
  final String source;
  final String createdAt;
  final String updatedAt;
  final String? sessionId;
  final String? peerMessageId;
  final String? sessionKey;
  final String? runId;
  final String? summary;
  final List<A2AArtifact> resultArtifacts;
  final String? error;

  /// Parses a task record from its JSON map.
  factory A2ATaskRecord.fromJson(Map<String, dynamic> json) => A2ATaskRecord(
        taskId: json['taskId'] as String? ?? json['task_id'] as String? ?? '',
        envelopeId: json['envelopeId'] as String? ??
            json['envelope_id'] as String? ??
            '',
        idempotencyKey: json['idempotencyKey'] as String? ??
            json['idempotency_key'] as String? ??
            '',
        agentId:
            json['agentId'] as String? ?? json['agent_id'] as String? ?? '',
        sender: A2AParty.fromJson(_map(json['sender'])),
        callback: json['callback'] is Map
            ? A2ACallback.fromJson(_map(json['callback']))
            : null,
        request: A2ATaskRequest.fromJson(_map(json['request'])),
        status: json['status'] as String? ?? 'received',
        trust: json['trust'] as String? ?? 'untrusted',
        source: json['source'] as String? ?? '',
        createdAt:
            json['createdAt'] as String? ?? json['created_at'] as String? ?? '',
        updatedAt:
            json['updatedAt'] as String? ?? json['updated_at'] as String? ?? '',
        sessionId:
            json['sessionId'] as String? ?? json['session_id'] as String?,
        peerMessageId: json['peerMessageId'] as String? ??
            json['peer_message_id'] as String?,
        sessionKey:
            json['sessionKey'] as String? ?? json['session_key'] as String?,
        runId: json['runId'] as String? ?? json['run_id'] as String?,
        summary: json['summary'] as String?,
        resultArtifacts: (json['resultArtifacts'] as List? ??
                json['result_artifacts'] as List? ??
                const [])
            .whereType<Map>()
            .map(
                (item) => A2AArtifact.fromJson(Map<String, dynamic>.from(item)))
            .toList(growable: false),
        error: json['error'] as String?,
      );
}

/// Pairing offer generated for a new peer: the allocated peer id and shared
/// secret bundled with the deep-link envelope (and its URL) to send them.
class A2APeerInvite {
  /// Creates a peer invite.
  const A2APeerInvite({
    required this.peerId,
    required this.sharedSecret,
    required this.envelope,
    required this.deepLinkUrl,
  });

  final String peerId;
  final String sharedSecret;
  final A2ADeepLinkEnvelope envelope;
  final String deepLinkUrl;

  /// Parses a peer invite from its JSON map.
  factory A2APeerInvite.fromJson(Map<String, dynamic> json) => A2APeerInvite(
        peerId: json['peerId'] as String? ?? '',
        sharedSecret: json['sharedSecret'] as String? ?? '',
        envelope: A2ADeepLinkEnvelope.fromJson(_map(json['envelope'])),
        deepLinkUrl: json['deepLinkUrl'] as String? ?? '',
      );
}

/// A task result packaged as a deep-link envelope and ready-to-share URL for
/// returning to the originating agent.
class A2AResultLink {
  /// Creates a result link.
  const A2AResultLink({
    required this.taskId,
    required this.envelope,
    required this.deepLinkUrl,
  });

  final String taskId;
  final A2ADeepLinkEnvelope envelope;
  final String deepLinkUrl;

  /// Parses a result link from its JSON map.
  factory A2AResultLink.fromJson(Map<String, dynamic> json) => A2AResultLink(
        taskId: json['taskId'] as String? ?? json['task_id'] as String? ?? '',
        envelope: A2ADeepLinkEnvelope.fromJson(_map(json['envelope'])),
        deepLinkUrl: json['deepLinkUrl'] as String? ??
            json['deep_link_url'] as String? ??
            '',
      );
}

/// A single reachable address for a peer over a given transport, with a
/// priority used to pick between multiple endpoints.
class A2APeerEndpoint {
  /// Creates a peer endpoint.
  const A2APeerEndpoint({
    required this.transport,
    required this.uri,
    this.priority = 0,
    this.lastSeenAt,
  });

  final String transport;
  final String uri;
  final int priority;
  final String? lastSeenAt;

  /// Parses a peer endpoint from its JSON map.
  factory A2APeerEndpoint.fromJson(Map<String, dynamic> json) =>
      A2APeerEndpoint(
        transport: json['transport'] as String? ?? 'unknown',
        uri: json['uri'] as String? ?? '',
        priority: _int(json['priority']) ?? 0,
        lastSeenAt:
            json['lastSeenAt'] as String? ?? json['last_seen_at'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'transport': _coreA2ATransport(transport),
        'uri': uri,
        'priority': priority,
        if (lastSeenAt != null) 'lastSeenAt': lastSeenAt,
      };
}

/// An established messaging session between the local peer and a remote peer
/// over a chosen transport, tracking status and activity timestamps.
class A2APeerSession {
  /// Creates a peer session.
  const A2APeerSession({
    required this.sessionId,
    required this.localPeerId,
    required this.remotePeerId,
    this.remoteAgentId = '',
    required this.status,
    required this.transport,
    this.endpoint = '',
    required this.createdAt,
    required this.updatedAt,
    this.lastMessageAt,
  });

  final String sessionId;
  final String localPeerId;
  final String remotePeerId;
  final String remoteAgentId;
  final String status;
  final String transport;
  final String endpoint;
  final String createdAt;
  final String updatedAt;
  final String? lastMessageAt;

  /// Parses a peer session from its JSON map.
  factory A2APeerSession.fromJson(Map<String, dynamic> json) => A2APeerSession(
        sessionId:
            json['sessionId'] as String? ?? json['session_id'] as String? ?? '',
        localPeerId: json['localPeerId'] as String? ??
            json['local_peer_id'] as String? ??
            '',
        remotePeerId: json['remotePeerId'] as String? ??
            json['remote_peer_id'] as String? ??
            '',
        remoteAgentId: json['remoteAgentId'] as String? ??
            json['remote_agent_id'] as String? ??
            '',
        status: json['status'] as String? ?? 'active',
        transport: json['transport'] as String? ?? 'unknown',
        endpoint: json['endpoint'] as String? ?? '',
        createdAt:
            json['createdAt'] as String? ?? json['created_at'] as String? ?? '',
        updatedAt:
            json['updatedAt'] as String? ?? json['updated_at'] as String? ?? '',
        lastMessageAt: json['lastMessageAt'] as String? ??
            json['last_message_at'] as String?,
      );
}

/// A single signed message exchanged within an A2A peer session, carrying an
/// arbitrary payload plus anti-replay metadata (nonce, expiry, idempotency).
class A2APeerMessage {
  /// Creates a peer message.
  const A2APeerMessage({
    required this.messageId,
    required this.sessionId,
    required this.fromPeerId,
    required this.toPeerId,
    required this.kind,
    required this.createdAt,
    required this.expiresAt,
    required this.nonce,
    required this.idempotencyKey,
    this.payload = const {},
    this.signatureAlgorithm = '',
    this.signature,
  });

  final String messageId;
  final String sessionId;
  final String fromPeerId;
  final String toPeerId;
  final String kind;
  final String createdAt;
  final String expiresAt;
  final String nonce;
  final String idempotencyKey;
  final Map<String, dynamic> payload;
  final String signatureAlgorithm;
  final String? signature;

  /// Parses a peer message from its JSON map.
  factory A2APeerMessage.fromJson(Map<String, dynamic> json) => A2APeerMessage(
        messageId:
            json['messageId'] as String? ?? json['message_id'] as String? ?? '',
        sessionId:
            json['sessionId'] as String? ?? json['session_id'] as String? ?? '',
        fromPeerId: json['fromPeerId'] as String? ??
            json['from_peer_id'] as String? ??
            '',
        toPeerId:
            json['toPeerId'] as String? ?? json['to_peer_id'] as String? ?? '',
        kind: json['kind'] as String? ?? 'task_request',
        createdAt:
            json['createdAt'] as String? ?? json['created_at'] as String? ?? '',
        expiresAt:
            json['expiresAt'] as String? ?? json['expires_at'] as String? ?? '',
        nonce: json['nonce'] as String? ?? '',
        idempotencyKey: json['idempotencyKey'] as String? ??
            json['idempotency_key'] as String? ??
            '',
        payload: _map(json['payload']),
        signatureAlgorithm: json['signatureAlgorithm'] as String? ??
            json['signature_algorithm'] as String? ??
            '',
        signature: json['signature'] as String?,
      );

  /// Parses a peer message from a raw JSON string.
  factory A2APeerMessage.fromJsonString(String raw) =>
      A2APeerMessage.fromJson(jsonDecode(raw) as Map<String, dynamic>);

  Map<String, dynamic> toJson() => {
        'messageId': messageId,
        'sessionId': sessionId,
        'fromPeerId': fromPeerId,
        'toPeerId': toPeerId,
        'kind': kind,
        'createdAt': createdAt,
        'expiresAt': expiresAt,
        'nonce': nonce,
        'idempotencyKey': idempotencyKey,
        'payload': payload,
        if (signatureAlgorithm.isNotEmpty)
          'signatureAlgorithm': signatureAlgorithm,
        if (signature != null) 'signature': signature,
      };

  /// Serializes this message to a compact JSON string.
  String toJsonString() => jsonEncode(toJson());
}

/// Audit entry recording the delivery attempt of a peer message in a given
/// direction (inbound/outbound), with its status and any error.
class A2ADeliveryRecord {
  /// Creates a delivery record.
  const A2ADeliveryRecord({
    required this.messageId,
    required this.sessionId,
    required this.direction,
    required this.kind,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    this.taskId,
    this.error,
  });

  final String messageId;
  final String sessionId;
  final String direction;
  final String kind;
  final String status;
  final String createdAt;
  final String updatedAt;
  final String? taskId;
  final String? error;

  /// Parses a delivery record from its JSON map.
  factory A2ADeliveryRecord.fromJson(Map<String, dynamic> json) =>
      A2ADeliveryRecord(
        messageId:
            json['messageId'] as String? ?? json['message_id'] as String? ?? '',
        sessionId:
            json['sessionId'] as String? ?? json['session_id'] as String? ?? '',
        direction: json['direction'] as String? ?? 'inbound',
        kind: json['kind'] as String? ?? '',
        status: json['status'] as String? ?? '',
        createdAt:
            json['createdAt'] as String? ?? json['created_at'] as String? ?? '',
        updatedAt:
            json['updatedAt'] as String? ?? json['updated_at'] as String? ?? '',
        taskId: json['taskId'] as String? ?? json['task_id'] as String?,
        error: json['error'] as String?,
      );
}

/// Snapshot of the local on-device A2A transport (e.g. LAN discovery): whether
/// it is supported and running, plus identity, listener, and traffic counters.
class A2ALocalTransportStatus {
  /// Creates a local transport status snapshot.
  const A2ALocalTransportStatus({
    required this.supported,
    required this.running,
    this.transport = '',
    this.serviceType = '',
    this.peerId = '',
    this.agentId = '',
    this.displayName = '',
    this.endpoint = '',
    this.listenerPort = 0,
    this.registeredName = '',
    this.discoveredPeerCount = 0,
    this.activeDiscoveryCount = 0,
    this.sentMessageCount = 0,
    this.receivedMessageCount = 0,
    this.multicastLockHeld = false,
    this.lastError = '',
    this.reason = '',
  });

  final bool supported;
  final bool running;
  final String transport;
  final String serviceType;
  final String peerId;
  final String agentId;
  final String displayName;
  final String endpoint;
  final int listenerPort;
  final String registeredName;
  final int discoveredPeerCount;
  final int activeDiscoveryCount;
  final int sentMessageCount;
  final int receivedMessageCount;
  final bool multicastLockHeld;
  final String lastError;
  final String reason;

  /// Parses a transport status from its JSON map.
  factory A2ALocalTransportStatus.fromJson(Map<String, dynamic> json) =>
      A2ALocalTransportStatus(
        supported: json['supported'] as bool? ?? false,
        running: json['running'] as bool? ?? false,
        transport: json['transport'] as String? ?? '',
        serviceType: json['serviceType'] as String? ??
            json['service_type'] as String? ??
            '',
        peerId: json['peerId'] as String? ?? json['peer_id'] as String? ?? '',
        agentId:
            json['agentId'] as String? ?? json['agent_id'] as String? ?? '',
        displayName: json['displayName'] as String? ??
            json['display_name'] as String? ??
            '',
        endpoint: json['endpoint'] as String? ?? '',
        listenerPort: _int(json['listenerPort'] ?? json['listener_port']) ?? 0,
        registeredName: json['registeredName'] as String? ??
            json['registered_name'] as String? ??
            '',
        discoveredPeerCount: _int(
              json['discoveredPeerCount'] ?? json['discovered_peer_count'],
            ) ??
            0,
        activeDiscoveryCount: _int(
              json['activeDiscoveryCount'] ?? json['active_discovery_count'],
            ) ??
            0,
        sentMessageCount:
            _int(json['sentMessageCount'] ?? json['sent_message_count']) ?? 0,
        receivedMessageCount: _int(
              json['receivedMessageCount'] ?? json['received_message_count'],
            ) ??
            0,
        multicastLockHeld: json['multicastLockHeld'] as bool? ??
            json['multicast_lock_held'] as bool? ??
            false,
        lastError:
            json['lastError'] as String? ?? json['last_error'] as String? ?? '',
        reason: json['reason'] as String? ?? '',
      );
}

/// A peer discovered on the local network, advertising its identity, public
/// key, and transport endpoint so it can be added as an [A2APeer].
class A2ALocalPeerAdvertisement {
  /// Creates a local peer advertisement.
  const A2ALocalPeerAdvertisement({
    required this.peerId,
    this.agentId = '',
    this.displayName = '',
    this.publicKey = '',
    this.transport = 'lan_tcp_jsonl',
    this.endpoint = '',
    this.host = '',
    this.port = 0,
  });

  final String peerId;
  final String agentId;
  final String displayName;
  final String publicKey;
  final String transport;
  final String endpoint;
  final String host;
  final int port;

  /// The normalized core transport name for this advertisement's transport.
  String get coreTransport => _coreA2ATransport(transport);

  /// Parses a local peer advertisement from its JSON map.
  factory A2ALocalPeerAdvertisement.fromJson(Map<String, dynamic> json) =>
      A2ALocalPeerAdvertisement(
        peerId: json['peerId'] as String? ?? json['peer_id'] as String? ?? '',
        agentId:
            json['agentId'] as String? ?? json['agent_id'] as String? ?? '',
        displayName: json['displayName'] as String? ??
            json['display_name'] as String? ??
            '',
        publicKey:
            json['publicKey'] as String? ?? json['public_key'] as String? ?? '',
        transport: json['transport'] as String? ?? 'lan_tcp_jsonl',
        endpoint: json['endpoint'] as String? ?? '',
        host: json['host'] as String? ?? '',
        port: _int(json['port']) ?? 0,
      );

  /// Converts this advertisement into a persistable [A2APeer], optionally
  /// setting the trust level and shared secret to record on pairing.
  A2APeer toPeer({
    String trustLevel = 'untrusted',
    String sharedSecret = '',
  }) =>
      A2APeer(
        peerId: peerId,
        agentId: agentId,
        displayName: displayName,
        trustLevel: trustLevel,
        sharedSecret: sharedSecret,
        publicKey: publicKey,
        endpoints: [
          if (endpoint.isNotEmpty)
            A2APeerEndpoint(
              transport: _coreA2ATransport(transport),
              uri: endpoint,
            ),
        ],
        createdAt: '',
        updatedAt: '',
      );
}

String _coreA2ATransport(String transport) {
  return switch (transport.trim().toLowerCase()) {
    'lan_tcp_jsonl' || 'tcp_jsonl' || 'jsonl_tcp' => 'lan_tcp',
    'lan_websocket' || 'websocket' || 'ws' => 'lan_web_socket',
    'tcp' => 'lan_tcp',
    'bluetooth' => 'ble',
    'deeplink' => 'deep_link',
    'host' => 'host_provided',
    final value when value.isNotEmpty => value,
    _ => 'unknown',
  };
}

/// An event emitted by the local A2A transport, such as a peer being found or
/// a message arriving, with the decoded peer/message and raw payload.
class A2ALocalTransportEvent {
  /// Creates a local transport event.
  const A2ALocalTransportEvent({
    required this.action,
    this.peer,
    this.message,
    this.messageJson = '',
    this.payload = const {},
  });

  final String action;
  final A2ALocalPeerAdvertisement? peer;
  final A2APeerMessage? message;
  final String messageJson;
  final Map<String, dynamic> payload;

  /// Builds a transport event from a raw platform event object.
  factory A2ALocalTransportEvent.fromEvent(Object? event) {
    final map = _map(event);
    final action = map['action'] as String? ?? '';
    final payload = _decodePayload(map['payload']);
    final messageJson = payload['messageJson'] as String? ?? '';
    A2APeerMessage? message;
    if (messageJson.isNotEmpty) {
      try {
        final decoded = jsonDecode(messageJson);
        if (decoded is Map &&
            (decoded['messageId'] != null || decoded['message_id'] != null)) {
          message = A2APeerMessage.fromJson(Map<String, dynamic>.from(decoded));
        }
      } catch (_) {
        message = null;
      }
    }
    return A2ALocalTransportEvent(
      action: action,
      peer: action == 'a2aLocalPeerFound'
          ? A2ALocalPeerAdvertisement.fromJson(payload)
          : null,
      message: message,
      messageJson: messageJson,
      payload: payload,
    );
  }
}

List<A2APeer> decodeA2APeers(String raw) => (jsonDecode(raw) as List)
    .whereType<Map>()
    .map((item) => A2APeer.fromJson(Map<String, dynamic>.from(item)))
    .toList(growable: false);

List<A2ATaskRecord> decodeA2ATasks(String raw) => (jsonDecode(raw) as List)
    .whereType<Map>()
    .map((item) => A2ATaskRecord.fromJson(Map<String, dynamic>.from(item)))
    .toList(growable: false);

List<A2APeerSession> decodeA2APeerSessions(String raw) =>
    (jsonDecode(raw) as List)
        .whereType<Map>()
        .map((item) => A2APeerSession.fromJson(Map<String, dynamic>.from(item)))
        .toList(growable: false);

List<A2APeerMessage> decodeA2APeerMessages(String raw) =>
    (jsonDecode(raw) as List)
        .whereType<Map>()
        .map((item) => A2APeerMessage.fromJson(Map<String, dynamic>.from(item)))
        .toList(growable: false);

List<A2ADeliveryRecord> decodeA2ADeliveryRecords(String raw) =>
    (jsonDecode(raw) as List)
        .whereType<Map>()
        .map(
          (item) => A2ADeliveryRecord.fromJson(Map<String, dynamic>.from(item)),
        )
        .toList(growable: false);

Map<String, dynamic> _map(Object? value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) return Map<String, dynamic>.from(value);
  return <String, dynamic>{};
}

List<String> _strings(Object? value) =>
    (value as List? ?? const []).map((item) => item.toString()).toList();

int? _int(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '');
}

Map<String, dynamic> _decodePayload(Object? value) {
  if (value is String && value.isNotEmpty) {
    final decoded = jsonDecode(value);
    return _map(decoded);
  }
  return _map(value);
}
