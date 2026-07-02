import 'dart:convert';

class NapaxiChannelSurfaceKind {
  static const im = 'im';
  static const device = 'device';
  static const app = 'app';
  static const system = 'system';
  static const custom = 'custom';

  const NapaxiChannelSurfaceKind._();
}

class NapaxiChannelEndpointKind {
  static const direct = 'direct';
  static const group = 'group';
  static const room = 'room';
  static const thread = 'thread';
  static const broadcast = 'broadcast';
  static const device = 'device';
  static const custom = 'custom';

  const NapaxiChannelEndpointKind._();
}

class NapaxiChannelModality {
  static const text = 'text';
  static const audio = 'audio';
  static const image = 'image';
  static const file = 'file';
  static const control = 'control';
  static const sensor = 'sensor';
  static const presence = 'presence';

  const NapaxiChannelModality._();
}

class NapaxiChannelContentFormat {
  static const plainText = 'plain_text';
  static const markdown = 'markdown';

  const NapaxiChannelContentFormat._();
}

class NapaxiChannelCapability {
  static const im = 'napaxi.channel.im';
  static const device = 'napaxi.channel.device';

  const NapaxiChannelCapability._();
}

class NapaxiChannelRegistration {
  final String name;
  final String? type;
  final String? accountId;
  final String? surfaceKind;
  final String? endpointKind;
  final List<String> modalities;
  final List<String> contentFormats;
  final String? transport;
  final Map<String, dynamic> config;

  const NapaxiChannelRegistration({
    required this.name,
    this.type,
    this.accountId,
    this.surfaceKind,
    this.endpointKind,
    this.modalities = const [],
    this.contentFormats = const [],
    this.transport,
    this.config = const {},
  });

  const NapaxiChannelRegistration.im({
    required this.name,
    required String this.type,
    this.accountId,
    this.endpointKind,
    this.modalities = const [NapaxiChannelModality.text],
    this.contentFormats = const [NapaxiChannelContentFormat.plainText],
    this.transport,
    this.config = const {},
  }) : surfaceKind = NapaxiChannelSurfaceKind.im;

  Map<String, dynamic> toJson() => {
    'name': name,
    if (type != null) 'type': type,
    if (accountId != null) 'account_id': accountId,
    if (surfaceKind != null) 'surface_kind': surfaceKind,
    if (endpointKind != null) 'endpoint_kind': endpointKind,
    if (modalities.isNotEmpty) 'modalities': modalities,
    if (contentFormats.isNotEmpty) 'content_formats': contentFormats,
    if (transport != null) 'transport': transport,
    if (config.isNotEmpty) 'config': config,
  };

  String toJsonString() => jsonEncode(toJson());
}

class NapaxiChannelRecord {
  final String name;
  final String? type;
  final String? surfaceKind;
  final String? endpointKind;
  final List<String> modalities;
  final List<String> contentFormats;
  final String? transport;
  final String? capabilityId;
  final Map<String, dynamic> config;
  final String registeredAt;
  final String updatedAt;

  const NapaxiChannelRecord({
    required this.name,
    this.type,
    this.surfaceKind,
    this.endpointKind,
    this.modalities = const [],
    this.contentFormats = const [],
    this.transport,
    this.capabilityId,
    this.config = const {},
    this.registeredAt = '',
    this.updatedAt = '',
  });

  factory NapaxiChannelRecord.fromJson(Map<String, dynamic> json) {
    return NapaxiChannelRecord(
      name: json['name'] as String? ?? '',
      type: json['type'] as String?,
      surfaceKind: json['surface_kind'] as String?,
      endpointKind: json['endpoint_kind'] as String?,
      modalities: (json['modalities'] as List? ?? const [])
          .map((item) => item.toString())
          .toList(growable: false),
      contentFormats:
          (json['content_formats'] as List? ??
                  json['contentFormats'] as List? ??
                  const [])
              .map((item) => item.toString())
              .toList(growable: false),
      transport: json['transport'] as String?,
      capabilityId: json['capability_id'] as String?,
      config: json['config'] is Map
          ? Map<String, dynamic>.from(json['config'] as Map)
          : const <String, dynamic>{},
      registeredAt: json['registered_at'] as String? ?? '',
      updatedAt: json['updated_at'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
    'name': name,
    if (type != null) 'type': type,
    if (surfaceKind != null) 'surface_kind': surfaceKind,
    if (endpointKind != null) 'endpoint_kind': endpointKind,
    if (modalities.isNotEmpty) 'modalities': modalities,
    if (contentFormats.isNotEmpty) 'content_formats': contentFormats,
    if (transport != null) 'transport': transport,
    if (capabilityId != null) 'capability_id': capabilityId,
    'config': config,
    'registered_at': registeredAt,
    'updated_at': updatedAt,
  };
}

class NapaxiChannelPeer {
  final String kind;
  final String id;
  final String? displayName;

  const NapaxiChannelPeer({
    required this.kind,
    required this.id,
    this.displayName,
  });

  factory NapaxiChannelPeer.fromJson(Map<String, dynamic> json) {
    return NapaxiChannelPeer(
      kind: json['kind'] as String? ?? NapaxiChannelEndpointKind.direct,
      id: json['id'] as String? ?? '',
      displayName: json['display_name'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
    'kind': kind,
    'id': id,
    if (displayName != null) 'display_name': displayName,
  };
}

class NapaxiChannelActor {
  final String id;
  final String? displayName;
  final bool? isBot;

  const NapaxiChannelActor({required this.id, this.displayName, this.isBot});

  factory NapaxiChannelActor.fromJson(Map<String, dynamic> json) {
    return NapaxiChannelActor(
      id: json['id'] as String? ?? '',
      displayName: json['display_name'] as String?,
      isBot: json['is_bot'] as bool?,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    if (displayName != null) 'display_name': displayName,
    if (isBot != null) 'is_bot': isBot,
  };
}

class NapaxiChannelMedia {
  final String kind;
  final String? uri;
  final String? mimeType;
  final String? name;
  final int? sizeBytes;
  final Map<String, dynamic>? raw;

  const NapaxiChannelMedia({
    required this.kind,
    this.uri,
    this.mimeType,
    this.name,
    this.sizeBytes,
    this.raw,
  });

  factory NapaxiChannelMedia.fromJson(Map<String, dynamic> json) {
    return NapaxiChannelMedia(
      kind: json['kind'] as String? ?? NapaxiChannelModality.file,
      uri: json['uri'] as String?,
      mimeType: json['mime_type'] as String?,
      name: json['name'] as String?,
      sizeBytes: json['size_bytes'] as int?,
      raw: json['raw'] is Map
          ? Map<String, dynamic>.from(json['raw'] as Map)
          : null,
    );
  }

  Map<String, dynamic> toJson() => {
    'kind': kind,
    if (uri != null) 'uri': uri,
    if (mimeType != null) 'mime_type': mimeType,
    if (name != null) 'name': name,
    if (sizeBytes != null) 'size_bytes': sizeBytes,
    if (raw != null) 'raw': raw,
  };
}

class NapaxiChannelInboundMessage {
  final String id;
  final String channelName;
  final String accountId;
  final NapaxiChannelPeer peer;
  final NapaxiChannelActor sender;
  final String? platformMessageId;
  final String? threadId;
  final String? text;
  final List<NapaxiChannelMedia> media;
  final Map<String, dynamic>? raw;
  final String? error;
  final String status;
  final String receivedAt;
  final String updatedAt;

  const NapaxiChannelInboundMessage({
    this.id = '',
    required this.channelName,
    this.accountId = 'default',
    required this.peer,
    required this.sender,
    this.platformMessageId,
    this.threadId,
    this.text,
    this.media = const [],
    this.raw,
    this.error,
    this.status = '',
    this.receivedAt = '',
    this.updatedAt = '',
  });

  factory NapaxiChannelInboundMessage.fromJson(Map<String, dynamic> json) {
    return NapaxiChannelInboundMessage(
      id: json['id'] as String? ?? '',
      channelName:
          json['channel_name'] as String? ?? json['channel'] as String? ?? '',
      accountId: json['account_id'] as String? ?? 'default',
      peer: NapaxiChannelPeer.fromJson(
        Map<String, dynamic>.from(json['peer'] as Map? ?? const {}),
      ),
      sender: NapaxiChannelActor.fromJson(
        Map<String, dynamic>.from(json['sender'] as Map? ?? const {}),
      ),
      platformMessageId: json['platform_message_id'] as String?,
      threadId: json['thread_id'] as String?,
      text: json['text'] as String?,
      media: _decodeChannelMedia(json['media']),
      raw: json['raw'] is Map
          ? Map<String, dynamic>.from(json['raw'] as Map)
          : null,
      error: json['error'] as String?,
      status: json['status'] as String? ?? '',
      receivedAt: json['received_at'] as String? ?? '',
      updatedAt: json['updated_at'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
    if (id.isNotEmpty) 'id': id,
    'channel_name': channelName,
    'account_id': accountId,
    'peer': peer.toJson(),
    'sender': sender.toJson(),
    if (platformMessageId != null) 'platform_message_id': platformMessageId,
    if (threadId != null) 'thread_id': threadId,
    if (text != null) 'text': text,
    if (media.isNotEmpty) 'media': media.map((item) => item.toJson()).toList(),
    if (raw != null) 'raw': raw,
  };

  String toJsonString() => jsonEncode(toJson());
}

class NapaxiChannelAgentRoute {
  final String id;
  final String channelName;
  final String? channelAccountId;
  final String? peerKind;
  final String? peerId;
  final String? threadId;
  final String sessionAccountId;
  final String agentId;
  final bool enabled;
  final String sessionPolicy;
  final String createdAt;
  final String updatedAt;

  const NapaxiChannelAgentRoute({
    this.id = '',
    required this.channelName,
    this.channelAccountId,
    this.peerKind,
    this.peerId,
    this.threadId,
    this.sessionAccountId = 'default',
    this.agentId = 'napaxi',
    this.enabled = true,
    this.sessionPolicy = 'stable_by_peer_or_thread',
    this.createdAt = '',
    this.updatedAt = '',
  });

  factory NapaxiChannelAgentRoute.channelDefault({
    required String channelName,
    String? channelAccountId,
    required String sessionAccountId,
    required String agentId,
    bool enabled = true,
  }) {
    return NapaxiChannelAgentRoute(
      channelName: channelName,
      channelAccountId: channelAccountId,
      sessionAccountId: sessionAccountId,
      agentId: agentId,
      enabled: enabled,
    );
  }

  factory NapaxiChannelAgentRoute.fromJson(Map<String, dynamic> json) {
    return NapaxiChannelAgentRoute(
      id: json['id'] as String? ?? '',
      channelName: json['channel_name'] as String? ?? '',
      channelAccountId: json['channel_account_id'] as String?,
      peerKind: json['peer_kind'] as String?,
      peerId: json['peer_id'] as String?,
      threadId: json['thread_id'] as String?,
      sessionAccountId: json['session_account_id'] as String? ?? 'default',
      agentId: json['agent_id'] as String? ?? 'napaxi',
      enabled: json['enabled'] as bool? ?? true,
      sessionPolicy:
          json['session_policy'] as String? ?? 'stable_by_peer_or_thread',
      createdAt: json['created_at'] as String? ?? '',
      updatedAt: json['updated_at'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
    if (id.isNotEmpty) 'id': id,
    'channel_name': channelName,
    if (channelAccountId != null) 'channel_account_id': channelAccountId,
    if (peerKind != null) 'peer_kind': peerKind,
    if (peerId != null) 'peer_id': peerId,
    if (threadId != null) 'thread_id': threadId,
    'session_account_id': sessionAccountId,
    'agent_id': agentId,
    'enabled': enabled,
    'session_policy': sessionPolicy,
  };

  String toJsonString() => jsonEncode(toJson());
}

class NapaxiChannelAgentStatus {
  final List<NapaxiChannelAgentRoute> routes;
  final List<Map<String, dynamic>> pendingHuman;

  const NapaxiChannelAgentStatus({
    this.routes = const [],
    this.pendingHuman = const [],
  });

  factory NapaxiChannelAgentStatus.fromJson(Map<String, dynamic> json) {
    return NapaxiChannelAgentStatus(
      routes: (json['routes'] as List? ?? const [])
          .whereType<Map>()
          .map(
            (item) => NapaxiChannelAgentRoute.fromJson(
              Map<String, dynamic>.from(item),
            ),
          )
          .toList(growable: false),
      pendingHuman: (json['pending_human'] as List? ?? const [])
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList(growable: false),
    );
  }
}

class NapaxiChannelOutboundMessage {
  final String id;
  final String channelName;
  final String accountId;
  final NapaxiChannelPeer peer;
  final String? replyToMessageId;
  final String? threadId;
  final String? text;
  final String? format;
  final List<NapaxiChannelMedia> media;
  final Map<String, dynamic>? raw;
  final String? leaseId;
  final Map<String, dynamic>? platformReceipt;
  final String? error;
  final String status;
  final String createdAt;
  final String updatedAt;

  const NapaxiChannelOutboundMessage({
    this.id = '',
    required this.channelName,
    this.accountId = 'default',
    required this.peer,
    this.replyToMessageId,
    this.threadId,
    this.text,
    this.format,
    this.media = const [],
    this.raw,
    this.leaseId,
    this.platformReceipt,
    this.error,
    this.status = '',
    this.createdAt = '',
    this.updatedAt = '',
  });

  factory NapaxiChannelOutboundMessage.fromJson(Map<String, dynamic> json) {
    return NapaxiChannelOutboundMessage(
      id: json['id'] as String? ?? '',
      channelName:
          json['channel_name'] as String? ?? json['channel'] as String? ?? '',
      accountId: json['account_id'] as String? ?? 'default',
      peer: NapaxiChannelPeer.fromJson(
        Map<String, dynamic>.from(json['peer'] as Map? ?? const {}),
      ),
      replyToMessageId: json['reply_to_message_id'] as String?,
      threadId: json['thread_id'] as String?,
      text: json['text'] as String?,
      format:
          json['format'] as String? ??
          json['content_format'] as String? ??
          json['contentFormat'] as String?,
      media: _decodeChannelMedia(json['media']),
      raw: json['raw'] is Map
          ? Map<String, dynamic>.from(json['raw'] as Map)
          : null,
      leaseId: json['lease_id'] as String?,
      platformReceipt: json['platform_receipt'] is Map
          ? Map<String, dynamic>.from(json['platform_receipt'] as Map)
          : null,
      error: json['error'] as String?,
      status: json['status'] as String? ?? '',
      createdAt: json['created_at'] as String? ?? '',
      updatedAt: json['updated_at'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
    if (id.isNotEmpty) 'id': id,
    'channel_name': channelName,
    'account_id': accountId,
    'peer': peer.toJson(),
    if (replyToMessageId != null) 'reply_to_message_id': replyToMessageId,
    if (threadId != null) 'thread_id': threadId,
    if (text != null) 'text': text,
    if (format != null && format!.trim().isNotEmpty) 'format': format,
    if (media.isNotEmpty) 'media': media.map((item) => item.toJson()).toList(),
    if (raw != null) 'raw': raw,
  };

  String toJsonString() => jsonEncode(toJson());
}

class NapaxiChannelAcceptedReceipt {
  final bool accepted;
  final String id;
  final bool duplicate;
  final String? error;

  const NapaxiChannelAcceptedReceipt({
    required this.accepted,
    required this.id,
    this.duplicate = false,
    this.error,
  });

  factory NapaxiChannelAcceptedReceipt.fromJson(Map<String, dynamic> json) {
    return NapaxiChannelAcceptedReceipt(
      accepted: json['accepted'] as bool? ?? false,
      id: json['id'] as String? ?? '',
      duplicate: json['duplicate'] as bool? ?? false,
      error: json['error'] as String?,
    );
  }
}

List<NapaxiChannelRecord> decodeChannelRecords(String jsonStr) {
  final decoded = jsonDecode(jsonStr);
  if (decoded is! List) return const [];
  return decoded
      .whereType<Map>()
      .map(
        (item) => NapaxiChannelRecord.fromJson(Map<String, dynamic>.from(item)),
      )
      .toList(growable: false);
}

NapaxiChannelAcceptedReceipt decodeChannelAcceptedReceipt(String jsonStr) {
  final decoded = jsonDecode(jsonStr);
  if (decoded is! Map) {
    return const NapaxiChannelAcceptedReceipt(accepted: false, id: '');
  }
  return NapaxiChannelAcceptedReceipt.fromJson(
    Map<String, dynamic>.from(decoded),
  );
}

List<NapaxiChannelInboundMessage> decodeChannelInboundMessages(String jsonStr) {
  final decoded = jsonDecode(jsonStr);
  if (decoded is! List) return const [];
  return decoded
      .whereType<Map>()
      .map(
        (item) => NapaxiChannelInboundMessage.fromJson(
          Map<String, dynamic>.from(item),
        ),
      )
      .toList(growable: false);
}

List<NapaxiChannelOutboundMessage> decodeChannelOutboundMessages(
  String jsonStr,
) {
  final decoded = jsonDecode(jsonStr);
  if (decoded is! List) return const [];
  return decoded
      .whereType<Map>()
      .map(
        (item) => NapaxiChannelOutboundMessage.fromJson(
          Map<String, dynamic>.from(item),
        ),
      )
      .toList(growable: false);
}

NapaxiChannelAgentRoute decodeChannelAgentRoute(String jsonStr) {
  final decoded = jsonDecode(jsonStr);
  if (decoded is! Map) {
    return const NapaxiChannelAgentRoute(channelName: '');
  }
  return NapaxiChannelAgentRoute.fromJson(Map<String, dynamic>.from(decoded));
}

List<NapaxiChannelAgentRoute> decodeChannelAgentRoutes(String jsonStr) {
  final decoded = jsonDecode(jsonStr);
  if (decoded is! List) return const [];
  return decoded
      .whereType<Map>()
      .map(
        (item) =>
            NapaxiChannelAgentRoute.fromJson(Map<String, dynamic>.from(item)),
      )
      .toList(growable: false);
}

NapaxiChannelAgentStatus decodeChannelAgentStatus(String jsonStr) {
  final decoded = jsonDecode(jsonStr);
  if (decoded is! Map) return const NapaxiChannelAgentStatus();
  return NapaxiChannelAgentStatus.fromJson(Map<String, dynamic>.from(decoded));
}

List<NapaxiChannelMedia> _decodeChannelMedia(Object? value) {
  if (value is! List) return const [];
  return value
      .whereType<Map>()
      .map(
        (item) => NapaxiChannelMedia.fromJson(Map<String, dynamic>.from(item)),
      )
      .toList(growable: false);
}
