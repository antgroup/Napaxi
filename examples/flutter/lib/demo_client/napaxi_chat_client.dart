part of '../main.dart';

typedef NapaxiChatClientFactory = Future<NapaxiChatClient> Function();

const int _localA2ADiscoveryTimeoutMs = 5000;
const int _a2aMaxArtifactsPerTurn = 12;
const int _a2aMaxInlineArtifactBase64Chars = 12 * 1024 * 1024;
const int _a2aBlobChunkBytes = 64 * 1024;
const int _a2aBlobMaxChunkBase64Chars =
    ((_a2aBlobChunkBytes + 2) ~/ 3) * 4 + 16;
const int _a2aBlobMaxArtifactsPerManifest = 20;
const int _a2aBlobMaxArtifactBytes = 64 * 1024 * 1024;
const int _a2aBlobMaxManifestBytes = 256 * 1024 * 1024;
const int _a2aBlobWaitTimeoutMs = 15000;
const String _a2aBlobProtocolVersion = 'local-blob-v1';
const String _a2aBlobSignatureAlgorithm = 'hmac-sha256-v1';
const int _a2aPendingArtifactTtlMs = 10 * 60 * 1000;
const String _ccHistoryLogTag = 'napaxiCCHistory';
const String _codexHistoryLogTag = 'napaxiCodexHistory';

Future<String?> _resolvedCliWorkspaceHostPath() {
  return _resolveCliWorkspaceHostDir()
      .then((value) {
        final trimmed = value.trim();
        return trimmed.isEmpty || trimmed == '/workspace' ? null : trimmed;
      })
      .catchError((Object error) {
        debugPrint('Failed to resolve CLI workspace host path: $error');
        return null;
      });
}

class _A2AArtifactTransportResult {
  const _A2AArtifactTransportResult({
    required this.artifacts,
    required this.issues,
  });

  final List<sdk.A2AArtifact> artifacts;
  final List<Map<String, dynamic>> issues;

  bool get ok => issues.every((issue) => issue['severity'] != 'error');
}

class _A2ABlobTransferPlan {
  const _A2ABlobTransferPlan({
    required this.manifestId,
    required this.artifacts,
    required this.files,
  });

  final String manifestId;
  final List<sdk.A2AArtifact> artifacts;
  final List<_A2ABlobTransferFile> files;
}

class _A2ABlobBuildResult {
  const _A2ABlobBuildResult({
    required this.artifacts,
    required this.issues,
    required this.blobPlan,
  });

  final List<sdk.A2AArtifact> artifacts;
  final List<Map<String, dynamic>> issues;
  final _A2ABlobTransferPlan? blobPlan;
}

class _A2ABlobTransferFile {
  const _A2ABlobTransferFile({
    required this.artifact,
    required this.file,
    required this.sizeBytes,
    required this.sha256Hex,
    required this.chunkCount,
  });

  final sdk.A2AArtifact artifact;
  final File file;
  final int sizeBytes;
  final String sha256Hex;
  final int chunkCount;
}

class _A2ASocketTarget {
  const _A2ASocketTarget({required this.host, required this.port});

  final String host;
  final int port;
}

class _A2ABlobReceiveManifest {
  _A2ABlobReceiveManifest({
    required this.manifestId,
    required this.fromPeerId,
    required this.createdAtMs,
    required this.artifacts,
  });

  final String manifestId;
  final String fromPeerId;
  final int createdAtMs;
  final Map<String, _A2ABlobReceiveArtifact> artifacts;
  bool completeReceived = false;
}

class _A2ABlobReceiveArtifact {
  _A2ABlobReceiveArtifact({
    required this.artifactId,
    required this.name,
    required this.mimeType,
    required this.sizeBytes,
    required this.sha256Hex,
    required this.chunkSizeBytes,
    required this.chunkCount,
  });

  final String artifactId;
  final String name;
  final String mimeType;
  final int sizeBytes;
  final String sha256Hex;
  final int chunkSizeBytes;
  final int chunkCount;
  final Set<int> receivedChunks = {};
  sdk.A2AArtifact? resolvedArtifact;

  bool get hasAllChunks =>
      chunkCount > 0 && receivedChunks.length >= chunkCount;
}

class _SingleValueSink<T> implements Sink<T> {
  T? value;
  var _closed = false;

  @override
  void add(T data) {
    if (_closed) {
      throw StateError('sink is closed');
    }
    value = data;
  }

  @override
  void close() {
    _closed = true;
  }
}

class _A2APendingArtifact {
  const _A2APendingArtifact({
    required this.artifact,
    required this.sourceTool,
    required this.createdAtMs,
  });

  final sdk.A2AArtifact artifact;
  final String sourceTool;
  final int createdAtMs;
}

const _a2aLocalWorkspaceFilesDirMetadata = '_local_workspace_files_dir';
const _a2aLocalAccountIdMetadata = '_local_account_id';
const _a2aLocalAgentIdMetadata = '_local_agent_id';
const _a2aLocalSourceToolMetadata = '_local_source_tool';

const _a2aLocalTransportMetadataKeys = {
  _a2aLocalWorkspaceFilesDirMetadata,
  _a2aLocalAccountIdMetadata,
  _a2aLocalAgentIdMetadata,
  _a2aLocalSourceToolMetadata,
};

List<sdk.A2AArtifact> _a2aArtifactsFromParam(Object? value) {
  if (value is! List) return const [];
  return value
      .whereType<Map>()
      .take(_a2aMaxArtifactsPerTurn)
      .map((item) => _a2aArtifactFromMap(Map<String, dynamic>.from(item)))
      .whereType<sdk.A2AArtifact>()
      .toList(growable: false);
}

sdk.A2AArtifact? _a2aArtifactFromMap(Map<String, dynamic> map) {
  final artifactId = _a2aStringField(map, ['artifactId', 'artifact_id', 'id']);
  final mimeType = _a2aStringField(map, ['mimeType', 'mime_type']);
  final name = _a2aStringField(map, ['name', 'filename']);
  final uri = _a2aStringField(map, [
    'uri',
    'sandboxPath',
    'sandbox_path',
    'filePath',
    'file_path',
    'path',
  ]);
  final text = _a2aStringField(map, [
    'text',
    'extractedText',
    'extracted_text',
  ]);
  final metadata = map['metadata'] is Map
      ? Map<String, dynamic>.from(map['metadata'] as Map)
      : <String, dynamic>{};
  final dataBase64 = _a2aStringField(map, ['dataBase64', 'data_base64']);
  if (dataBase64.isNotEmpty &&
      dataBase64.length <= _a2aMaxInlineArtifactBase64Chars) {
    metadata['data_base64'] = dataBase64;
  }
  final sizeBytes = _a2aIntFromAny(map['sizeBytes'] ?? map['size_bytes']);
  if (sizeBytes != null) metadata['size_bytes'] = sizeBytes;
  if (artifactId.isEmpty &&
      mimeType.isEmpty &&
      name.isEmpty &&
      uri.isEmpty &&
      text.isEmpty) {
    return null;
  }
  return sdk.A2AArtifact(
    artifactId: artifactId.isEmpty
        ? 'artifact-${DateTime.now().microsecondsSinceEpoch}'
        : artifactId,
    mimeType: mimeType,
    name: name,
    uri: uri.isEmpty ? null : uri,
    text: text.isEmpty ? null : text,
    metadata: metadata,
  );
}

List<Map<String, dynamic>> _a2aArtifactJsonList(
  List<sdk.A2AArtifact> artifacts,
) => artifacts.map((item) => item.toJson()).toList(growable: false);

List<Map<String, dynamic>> _a2aArtifactSummaryList(
  List<sdk.A2AArtifact> artifacts,
) => artifacts
    .map(
      (item) => {
        'artifactId': item.artifactId,
        if (item.mimeType.isNotEmpty) 'mimeType': item.mimeType,
        if (item.name.isNotEmpty) 'name': item.name,
        if (item.uri?.trim().isNotEmpty == true) 'hasUri': true,
        if (item.text?.trim().isNotEmpty == true) 'hasText': true,
        if (item.metadata['data_base64'] is String) 'hasInlineData': true,
        if (item.metadata['size_bytes'] != null)
          'sizeBytes': item.metadata['size_bytes'],
      },
    )
    .toList(growable: false);

List<sdk.NapaxiChannelMedia> _a2aChannelMediaFromArtifacts(
  List<sdk.A2AArtifact> artifacts,
) => artifacts
    .map((artifact) {
      final raw = _a2aTransferableArtifactMetadata(artifact.metadata);
      raw['artifact_id'] = artifact.artifactId;
      if (artifact.text?.trim().isNotEmpty == true) {
        raw['extracted_text'] = artifact.text!.trim();
      }
      return sdk.NapaxiChannelMedia(
        kind: _a2aChannelKindForArtifact(artifact),
        uri: artifact.uri,
        mimeType: artifact.mimeType.isEmpty ? null : artifact.mimeType,
        name: artifact.name.isEmpty ? null : artifact.name,
        sizeBytes: _a2aIntFromAny(raw['size_bytes']),
        raw: raw.isEmpty ? null : raw,
      );
    })
    .toList(growable: false);

List<sdk.A2AArtifact> _a2aArtifactsFromChannelMedia(
  List<sdk.NapaxiChannelMedia> media,
) => media
    .take(_a2aMaxArtifactsPerTurn)
    .map((item) {
      final raw = item.raw == null
          ? <String, dynamic>{}
          : Map<String, dynamic>.from(item.raw!);
      final text = _a2aStringField(raw, [
        'extractedText',
        'extracted_text',
        'text',
      ]);
      final artifactId = _a2aStringField(raw, [
        'artifactId',
        'artifact_id',
        'id',
      ]);
      return sdk.A2AArtifact(
        artifactId: artifactId.isEmpty
            ? 'media-${DateTime.now().microsecondsSinceEpoch}'
            : artifactId,
        mimeType: item.mimeType ?? '',
        name: item.name ?? '',
        uri: item.uri,
        text: text.isEmpty ? null : text,
        metadata: raw,
      );
    })
    .toList(growable: false);

String _a2aChannelKindForArtifact(sdk.A2AArtifact artifact) {
  final kind = artifact.metadata['kind']?.toString().trim().toLowerCase() ?? '';
  if (kind == sdk.NapaxiChannelModality.image ||
      kind == sdk.NapaxiChannelModality.audio) {
    return kind;
  }
  final mime = artifact.mimeType.trim().toLowerCase();
  if (mime.startsWith('image/')) return sdk.NapaxiChannelModality.image;
  if (mime.startsWith('audio/')) return sdk.NapaxiChannelModality.audio;
  return sdk.NapaxiChannelModality.file;
}

sdk.A2AArtifact _a2aArtifactWithMetadata(
  sdk.A2AArtifact artifact,
  Map<String, dynamic> metadata,
) {
  return sdk.A2AArtifact(
    artifactId: artifact.artifactId,
    mimeType: artifact.mimeType,
    name: artifact.name,
    uri: artifact.uri,
    text: artifact.text,
    metadata: metadata,
  );
}

Map<String, dynamic> _a2aTransferableArtifactMetadata(
  Map<String, dynamic> metadata,
) {
  final raw = Map<String, dynamic>.from(metadata);
  for (final key in _a2aLocalTransportMetadataKeys) {
    raw.remove(key);
  }
  return raw;
}

bool _a2aUriIsLocalOnly(String uri) {
  final value = uri.trim();
  return value.startsWith('/workspace/') ||
      value.startsWith('file://') ||
      value.startsWith('napaxi-sandbox://');
}

List<Map<String, dynamic>> _a2aUnportableArtifactIssues(
  List<sdk.A2AArtifact> artifacts,
) {
  final issues = <Map<String, dynamic>>[];
  for (final artifact in artifacts) {
    final uri = artifact.uri?.trim() ?? '';
    if (uri.isEmpty) continue;
    final metadata = artifact.metadata;
    final transport = metadata['transport']?.toString().trim() ?? '';
    final hasInlineData = _a2aStringField(metadata, [
      'dataBase64',
      'data_base64',
    ]).isNotEmpty;
    final isBlob =
        transport == 'local_blob' ||
        uri.startsWith('a2a-blob://') ||
        _a2aStringField(metadata, ['manifest_id', 'manifestId']).isNotEmpty;
    if (isBlob || hasInlineData) continue;
    final parsed = Uri.tryParse(uri);
    final isRemoteUri =
        parsed != null && (parsed.scheme == 'http' || parsed.scheme == 'https');
    if (isRemoteUri) continue;
    if (_a2aUriIsLocalOnly(uri)) {
      issues.add({
        'severity': 'error',
        'code': 'local_artifact_not_portable',
        'artifactId': artifact.artifactId,
        'name': artifact.name,
        'uri': uri,
        'message':
            'Local file artifacts must be transferred as A2A blobs before sending to another device.',
      });
    }
  }
  return issues;
}

String _a2aArtifactLocalPathCandidate(
  sdk.A2AArtifact artifact,
  Map<String, dynamic> metadata,
) {
  final metadataPath = _a2aStringField(metadata, [
    'sandboxPath',
    'sandbox_path',
    'path',
    'localPath',
    'local_path',
  ]);
  if (metadataPath.isNotEmpty) return metadataPath;
  final uri = artifact.uri?.trim() ?? '';
  if (uri.startsWith('napaxi-sandbox://')) {
    return uri.substring('napaxi-sandbox://'.length);
  }
  if (_a2aUriIsLocalOnly(uri)) return uri;
  return '';
}

Future<File?> _a2aResolveTransportFile(
  String path,
  sdk.NapaxiEngine engine, {
  Map<String, dynamic> metadata = const {},
}) async {
  final normalized = path.trim();
  if (normalized.isEmpty) return null;

  final candidates = <File>[];
  final candidatePaths = <String>{};
  void addCandidate(String? path) {
    final value = path?.trim() ?? '';
    if (value.isEmpty || candidatePaths.contains(value)) return;
    candidatePaths.add(value);
    candidates.add(File(value));
  }

  final allowedRoots = <String>[
    engine.filesDir,
    if (sdk.NapaxiFileBridge.isInitialized)
      sdk.NapaxiFileBridge.instance.workspaceDir.path,
  ];
  void addAllowedRoot(String? root) {
    final value = root?.trim() ?? '';
    if (value.isEmpty || allowedRoots.contains(value)) return;
    allowedRoots.add(value);
  }

  if (normalized.startsWith('/workspace/')) {
    final relativeWorkspacePath = normalized.substring('/workspace/'.length);
    if (sdk.NapaxiFileBridge.isInitialized) {
      final bridge = sdk.NapaxiFileBridge.instance;
      final workspaceFilesDir = _a2aStringField(metadata, [
        _a2aLocalWorkspaceFilesDirMetadata,
        'workspace_files_dir',
        'workspaceFilesDir',
      ]);
      if (workspaceFilesDir.isNotEmpty) {
        final scopedWorkspace = _a2aJoinPath(
          _a2aJoinPath(workspaceFilesDir, 'linux-env'),
          'workspace',
        );
        addAllowedRoot(scopedWorkspace);
        addCandidate(_a2aJoinPath(scopedWorkspace, relativeWorkspacePath));
      }

      final accountId = _a2aStringField(metadata, [
        _a2aLocalAccountIdMetadata,
        'account_id',
        'accountId',
      ]);
      final agentId = _a2aStringField(metadata, [
        _a2aLocalAgentIdMetadata,
        'agent_id',
        'agentId',
      ]);
      if (accountId.isNotEmpty && agentId.isNotEmpty) {
        addAllowedRoot(
          bridge
              .workspaceDirScoped(accountId: accountId, agentId: agentId)
              .path,
        );
        addCandidate(
          bridge.sandboxToRealScoped(
            normalized,
            accountId: accountId,
            agentId: agentId,
          ),
        );
      }

      addCandidate(bridge.sandboxToReal(normalized));
    }
  } else if (normalized.startsWith('file://')) {
    addCandidate(Uri.parse(normalized).toFilePath());
  } else if (normalized.startsWith('/')) {
    addCandidate(normalized);
  }

  for (final candidate in candidates) {
    if (!await candidate.exists()) continue;
    if (await FileSystemEntity.isDirectory(candidate.path)) continue;
    if (await _a2aPathIsUnderAnyRoot(candidate, allowedRoots)) {
      return candidate;
    }
  }
  return null;
}

String _a2aJoinPath(String root, String child) {
  final normalizedRoot = root.trim();
  final normalizedChild = child.trim();
  if (normalizedRoot.endsWith('/')) return '$normalizedRoot$normalizedChild';
  return '$normalizedRoot/$normalizedChild';
}

Future<bool> _a2aPathIsUnderAnyRoot(File file, List<String> roots) async {
  final filePath = await _a2aCanonicalPath(file.path);
  if (filePath == null) return false;
  for (final root in roots) {
    final normalizedRoot = root.trim();
    if (normalizedRoot.isEmpty) continue;
    final rootPath = await _a2aCanonicalPath(normalizedRoot);
    if (rootPath == null) continue;
    if (filePath == rootPath || filePath.startsWith('$rootPath/')) {
      return true;
    }
  }
  return false;
}

Future<String?> _a2aCanonicalPath(String path) async {
  try {
    final type = await FileSystemEntity.type(path);
    if (type == FileSystemEntityType.directory) {
      return await Directory(path).resolveSymbolicLinks();
    }
    return await File(path).resolveSymbolicLinks();
  } catch (_) {
    return null;
  }
}

Future<String> _a2aFileSha256Hex(File file) async {
  final sink = _SingleValueSink<crypto.Digest>();
  final input = crypto.sha256.startChunkedConversion(sink);
  await for (final chunk in file.openRead()) {
    input.add(chunk);
  }
  input.close();
  return sink.value?.toString() ?? '';
}

String _a2aBytesSha256Hex(List<int> bytes) =>
    crypto.sha256.convert(bytes).toString();

Map<String, dynamic> _a2aSignBlobFrame(
  Map<String, dynamic> frame,
  String sharedSecret,
) {
  final unsigned = Map<String, dynamic>.from(frame)
    ..remove('signature')
    ..remove('signatureAlgorithm');
  final signature = crypto.Hmac(
    crypto.sha256,
    utf8.encode(sharedSecret),
  ).convert(utf8.encode(_a2aCanonicalJson(unsigned)));
  return {
    ...unsigned,
    'signatureAlgorithm': _a2aBlobSignatureAlgorithm,
    'signature': base64UrlEncode(signature.bytes).replaceAll('=', ''),
  };
}

bool _a2aVerifyBlobFrame(Map<String, dynamic> frame, String sharedSecret) {
  final signature = frame['signature']?.toString().trim() ?? '';
  final algorithm = frame['signatureAlgorithm']?.toString().trim() ?? '';
  if (signature.isEmpty || algorithm != _a2aBlobSignatureAlgorithm) {
    return false;
  }
  final expected = _a2aSignBlobFrame(frame, sharedSecret)['signature'];
  return signature == expected;
}

String _a2aCanonicalJson(Object? value) {
  Object? normalize(Object? input) {
    if (input is Map) {
      final keys = input.keys.map((key) => key.toString()).toList()..sort();
      return {
        for (final key in keys)
          key: normalize(
            input.entries
                .firstWhere((entry) => entry.key.toString() == key)
                .value,
          ),
      };
    }
    if (input is List) return input.map(normalize).toList(growable: false);
    return input;
  }

  return jsonEncode(normalize(value));
}

String _a2aSafeFilename(String value, String fallback) {
  final normalized = value
      .trim()
      .replaceAll(RegExp(r'[/\\]+'), '_')
      .replaceAll(RegExp(r'[^A-Za-z0-9._ -]+'), '_')
      .replaceAll(RegExp(r'\s+'), ' ');
  final safe = normalized.replaceAll(RegExp(r'^\.+'), '').trim();
  return safe.isEmpty ? fallback : safe;
}

String _a2aFileExtensionForMime(String mimeType) {
  final mime = mimeType.trim().toLowerCase();
  if (mime == 'image/jpeg' || mime == 'image/jpg') return '.jpg';
  if (mime == 'image/png') return '.png';
  if (mime == 'image/heic') return '.heic';
  if (mime == 'image/webp') return '.webp';
  if (mime == 'video/mp4') return '.mp4';
  if (mime == 'audio/mpeg') return '.mp3';
  if (mime == 'audio/mp4') return '.m4a';
  return '';
}

Future<File> _a2aUniqueFile(Directory dir, String filename) async {
  final dot = filename.lastIndexOf('.');
  final stem = dot > 0 ? filename.substring(0, dot) : filename;
  final ext = dot > 0 ? filename.substring(dot) : '';
  for (var i = 0; i < 1000; i++) {
    final candidateName = i == 0 ? filename : '$stem-$i$ext';
    final file = File('${dir.path}/$candidateName');
    if (!await file.exists()) return file;
  }
  return File('${dir.path}/${DateTime.now().microsecondsSinceEpoch}-$filename');
}

String _a2aStringField(Map<String, dynamic> map, List<String> keys) {
  for (final key in keys) {
    final value = map[key];
    if (value is String && value.trim().isNotEmpty) return value.trim();
  }
  return '';
}

int? _a2aIntFromAny(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value.trim());
  return null;
}

String _a2aPeerDisplayLabel(Object peer) {
  final (rawName, rawPeerId) = switch (peer) {
    sdk.A2APeer(:final displayName, :final peerId) => (displayName, peerId),
    sdk.A2ALocalPeerAdvertisement(:final displayName, :final peerId) => (
      displayName,
      peerId,
    ),
    _ => ('', ''),
  };
  final label = rawName.trim();
  if (_isGenericA2APeerLabel(label)) {
    return _a2aDefaultPeerDisplayLabel(rawPeerId);
  }
  return label;
}

String _a2aDefaultPeerDisplayLabel(String peerId) {
  final normalized = peerId.trim().toLowerCase();
  if (normalized.startsWith('ios-')) return 'iOS Agent';
  if (normalized.startsWith('android-')) return 'Android Agent';
  return '附近 Agent';
}

String _a2aExtractCollaborationMessage(String value) {
  final text = value.trim();
  if (text.isEmpty) return '';
  const marker = 'Message from the other Agent:';
  /*
'

Treat this as one turn'
  */
  final markerIndex = text.indexOf(marker);
  if (markerIndex < 0) return text;
  final tail = text.substring(markerIndex + marker.length).trimLeft();
  final endMarkers = [
    '\n\nTreat this as one turn',
    '\n\nIf you need clarification,',
    '\n\nYour reply may be',
    '\n\nThis message does not require a reply.',
    '\n\nWhen writing the final answer,',
    '\n\nWrite naturally,',
  ];
  var endIndex = tail.length;
  for (final endMarker in endMarkers) {
    final index = tail.indexOf(endMarker);
    if (index >= 0 && index < endIndex) endIndex = index;
  }
  return tail.substring(0, endIndex).trim();
}

/// Demo-only seam between the Flutter sample UI and the public napaxi SDK.
///
/// This is intentionally not an SDK API. It keeps the sample testable while
/// ensuring the demo only exercises `package:napaxi_flutter/napaxi_flutter.dart`.
abstract class NapaxiChatClient {
  sdk.NapaxiBrowserController? get browserController;

  Future<void> configureForManagement({
    sdk.NapaxiCapabilitySelection? capabilitySelection,
  });

  Future<void> configure(
    LlmModelProfile profile, {
    String responseLanguage = 'en',
    sdk.NapaxiCapabilitySelection? capabilitySelection,
  });

  Future<void> applyCapabilitySelection(
    sdk.NapaxiCapabilitySelection capabilitySelection,
  );

  Future<List<DemoAgent>> listAgents();

  Future<DemoAgent> createAgent({
    required String name,
    String systemPrompt = '',
    String? modelProfileId,
  });

  Future<DemoAgent> updateAgent({
    required String agentId,
    required String name,
    String systemPrompt = '',
    String? modelProfileId,
  });

  Future<bool> deleteAgent(String agentId);

  Future<List<sdk.AgentProviderDescriptor>> discoverAgentProviders();

  Future<DemoAgent> installAgentProvider(sdk.AgentProviderDescriptor provider);

  Future<DemoAgent?> installPendingAgentProvider();

  Future<sdk.AcceptedAgentTrigger?> consumePendingAgentTrigger();

  Future<List<sdk.NapaxiChannelProviderManifest>> listChannelProviders();

  Future<List<DemoChannelStatus>> listChannelStatuses();

  Future<List<DemoChannelInputSource>> listChannelInputSources({
    required String agentId,
  });

  Future<DemoChannelCredentials?> loadChannelCredentials(
    String channelName, {
    String? accountId,
  });

  Future<void> saveChannelCredentials(DemoChannelCredentials credentials);

  Future<void> clearChannelCredentials(String channelName, {String? accountId});

  Future<DemoChannelStatus> channelStatus(
    String channelName, {
    String? accountId,
  });

  Future<DemoChannelStatus> connectChannel(
    String channelName, {
    String? accountId,
  });

  Future<DemoHeadsetTranscriptResult> submitHeadsetTranscript({
    required String text,
  });

  Future<DemoHeadsetTranscriptResult> captureHeadsetTranscript({
    String? accountId,
    String? agentId,
  });

  Future<List<DemoChannelStatus>> ensureConfiguredChannelsConnected();

  Future<DemoLocalA2AChannelReceipt> submitLocalA2AChannelTask({
    required sdk.A2ATaskRecord task,
    required sdk.A2ALocalPeerAdvertisement peer,
  });

  Future<DemoLocalA2AChannelRun> runLocalA2AChannelTask({
    required String taskId,
    required String agentId,
  });

  bool claimLocalA2AAutoRunTask(String taskId);

  void releaseLocalA2AAutoRunTask(String taskId, {bool handled = true});

  Future<sdk.SessionKey> createSession({
    required String threadId,
    required String agentId,
  });

  Stream<sdk.ChatEvent> sendToSession(
    sdk.SessionKey session,
    String message, {
    required String agentId,
    List<sdk.McAttachment>? attachments,
    int maxIterations = 0,
    void Function(String nativeThreadId)? onNativeThreadId,
  });

  Future<bool> cancelSession(sdk.SessionKey session, {required String agentId});

  /// Reset CLI engine bridge state for a new conversation.
  void resetCliBridge(String engineId);

  /// Drop a CLI engine's persisted native-id mapping so its next turn starts a
  /// fresh native session (codex thread / Claude session).
  Future<void> clearCliNativeId(String engineId);

  Future<bool> deleteSession(sdk.SessionKey session, {required String agentId});

  Future<bool> injectMessage(
    sdk.SessionKey session,
    String message, {
    required String agentId,
    List<sdk.McAttachment>? attachments,
  });

  Future<bool> retractInjectedMessage(sdk.SessionKey session, String message);

  Future<bool> answerHumanRequest(String requestId, String response);

  Future<List<Map<String, dynamic>>> listPendingEvolution();

  Future<Map<String, dynamic>> applyPendingEvolution(String pendingId);

  Future<Map<String, dynamic>> rejectPendingEvolution(String pendingId);

  Future<List<sdk.EvolutionRun>> listEvolutionRuns({List<String>? runIds});

  bool get supportsBackgroundExecution;

  Future<bool> requestBackgroundPermission();

  Stream<sdk.BackgroundActionEvent> get onBackgroundAction;

  Stream<DemoChannelBridgeEvent> get onChannelBridgeEvent;

  Future<void> stopBackgroundService();

  Future<List<sdk.SessionInfo>> listSessions({required String agentId});

  Future<List<sdk.ChatMessage>> getHistory(
    String threadId, {
    required String agentId,
  });

  Future<sdk.HistoryPage> getHistoryPage(
    String threadId, {
    required String agentId,
    String? before,
    int limit = 80,
  });

  Future<sdk.ContextStatus> contextStatus(
    String threadId, {
    required String agentId,
  });

  Future<sdk.ContextStatus> compactContext(
    sdk.SessionKey session, {
    required String agentId,
    String? focus,
  });

  Future<List<sdk.WorkspaceEntry>> listMemoryFiles(
    String directory, {
    required String agentId,
  });

  Future<sdk.WorkspaceFile?> readMemoryFile(
    String path, {
    required String agentId,
  });

  Future<List<sdk.JournalDay>> listJournalDays({required String agentId});

  Future<List<sdk.JournalTurnRecord>> readJournalDay(
    String date, {
    required String agentId,
  });

  Future<List<sdk.MemoryRecallSession>> recallSessions(
    String query, {
    required String agentId,
  });

  Future<sdk.RecallIndexStats> rebuildRecallIndex({required String agentId});

  Future<sdk.RecallIndexStats> recallIndexStats({required String agentId});

  Future<bool> deleteMemoryFile(String path, {required String agentId});

  Future<List<sdk.WorkspaceFileInfo>> listSandboxWorkspaceFiles({
    required String agentId,
    String? subdir,
    bool recursive = true,
  });

  Future<void> deleteSandboxWorkspaceFile(
    String sandboxPath, {
    required String agentId,
  });

  Future<List<DemoRepositoryInfo>> listGitRepositories();

  Future<DemoGitRepositoryStatus> gitRepositoryStatus(String directory);

  /// Source-control change set for a repository: branch plus staged /
  /// unstaged / untracked entries with `+X/-Y` numstat. Powers the dev
  /// workbench's source-control view.
  Future<DemoGitChangeSet> gitChanges(String directory);

  Future<DemoGitOperationResult> stageGitPaths(
    String directory,
    List<String> paths,
  );

  Future<DemoGitOperationResult> unstageGitPaths(
    String directory,
    List<String> paths,
  );

  Future<DemoGitOperationResult> discardGitPaths(
    String directory,
    List<String> paths,
  );

  Future<DemoGitOperationResult> commitGit(String directory, String message);

  /// Unified diff for a single path, parsed into displayable hunks. Pass
  /// `cached: true` for the staged diff. Powers the inline diff the dev
  /// workbench shows when a changed file row is expanded.
  Future<DemoGitFileDiff> gitFileDiff(
    String directory,
    String path, {
    bool cached = false,
  });

  Future<List<DemoGitBranchInfo>> listGitBranches(String directory);

  Future<DemoGitOperationResult> switchGitBranch(
    String directory,
    String branch, {
    bool remote = false,
    bool allowDirty = false,
  });

  Future<List<DemoGitCommitInfo>> listGitCommitHistory(String directory);

  Future<DemoGitCommitDiff> gitCommitDiff(String directory, String hash);

  Future<List<DemoGitRemoteInfo>> listGitRemotes(String directory);

  Future<DemoGitOperationResult> setGitRemote(
    String directory, {
    required String name,
    required String url,
  });

  Future<DemoGitOperationResult> removeGitRemote(
    String directory, {
    required String name,
  });

  Future<DemoGitOperationResult> fetchGitRemote(
    String directory, {
    String? remote,
  });

  Future<DemoGitOperationResult> pushGitRemote(
    String directory, {
    String? remote,
  });

  Future<DemoGitOperationResult> pullGitRemote(
    String directory, {
    String? remote,
  });

  Future<List<DemoRepositoryFileItem>> listGitRepositoryChildren(
    String directory, {
    String subdir = '',
    String query = '',
    int limit = 200,
  });

  List<sdk.ResolvedFile> detectProducedFiles(
    String text, {
    required String agentId,
  });

  Future<List<sdk.NapaxiScenarioPack>> listScenarioPacks();

  Future<List<sdk.NapaxiScenarioStatus>> listScenarioStatuses();

  Future<sdk.NapaxiScenarioResolution?> resolveScenario(String scenarioId);

  Future<sdk.NapaxiScenarioPackInstallResult?> installScenarioPack(
    sdk.NapaxiScenarioPack pack,
  );

  Future<sdk.NapaxiScenarioPackRemovalResult?> removeScenarioPack(
    String scenarioId,
  );

  Future<List<sdk.SkillInfo>> listSkills({required String agentId});

  Future<sdk.SkillInfo?> getSkill(String skillName, {required String agentId});

  Future<sdk.SkillStatusReport> listSkillStatus({required String agentId});

  Future<sdk.SkillSourceReport> listSkillSources({required String agentId});

  Future<sdk.SkillSnapshotList> listSkillSnapshots({required String agentId});

  Future<sdk.SkillSecretRequirementReport> listSkillSecretRequirements({
    required String agentId,
    String? skillName,
  });

  Future<sdk.SkillRemediationRunList> listSkillRemediationRuns({
    required String agentId,
    String? skillName,
  });

  Future<sdk.SkillStatusReport> checkSkills({required String agentId});

  Future<sdk.SkillCommandReport> listSkillCommands({required String agentId});

  Future<sdk.SkillCommandResolution> resolveSkillCommand(
    String text, {
    required String agentId,
  });

  Future<sdk.SkillCommandRun> runSkillCommand(
    String commandName, {
    required String agentId,
    String? args,
    sdk.SessionKey? sessionKey,
  });

  Future<String> setSkillEnabled(
    String skillName, {
    required String agentId,
    required bool enabled,
  });

  Future<String> updateSkillConfig(
    String skillKey,
    Map<String, dynamic> patch, {
    required String agentId,
  });

  Future<String> recordSkillRequirementResolution(
    String skillName,
    String actionId,
    Map<String, dynamic> result, {
    required String agentId,
  });

  Future<sdk.SkillRemediationRun> requestSkillRemediation(
    String skillName,
    String actionId, {
    required String agentId,
  });

  Future<List<sdk.SkillUsageRecord>> listSkillUsage({required String agentId});

  Future<List<String>> reloadSkills({required String agentId});

  Future<bool> removeSkill(String skillName, {required String agentId});

  Future<String> pinSkill(
    String skillName, {
    required String agentId,
    required bool pinned,
  });

  Future<String> archiveSkill(String skillName, {required String agentId});

  Future<String> restoreSkill(String skillName, {required String agentId});

  Future<sdk.CuratorRunSummary> runSkillCurator({
    required String agentId,
    bool dryRun = true,
  });

  Future<sdk.SkillConsolidationReviewResult> runSkillConsolidationReview({
    required String agentId,
    bool dryRun = true,
  });

  Future<sdk.SkillSupportFileReadResult> readSkillSupportFile(
    String skillName,
    String filePath, {
    required String agentId,
  });

  Future<sdk.CatalogSearchResult> listCatalogPackages({
    int limit = 50,
    String? cursor,
  });

  Future<sdk.CatalogSearchResult> searchCatalog(String query);

  Future<sdk.SkillInstallResult> installFromCatalog(
    String slug, {
    required String agentId,
  });

  Stream<sdk.A2ALocalTransportEvent> get localA2AEvents;

  Future<bool> handleLocalA2ABlobFrame(sdk.A2ALocalTransportEvent event);

  Future<sdk.A2ALocalTransportStatus> localA2AStatus();

  Future<bool> checkLocalA2APermission();

  Future<bool> requestLocalA2APermission();

  String generateLocalA2APairingSecret();

  String normalizeLocalA2APairingSecret(String value);

  String formatLocalA2APairingSecret(String value);

  String localA2APairingKey(sdk.A2ALocalPeerAdvertisement peer);

  String localA2APairingCode(String peerId, String publicKey);

  String deriveLocalA2ASharedSecret({
    required String localPeerId,
    required String localPublicKey,
    required String localPairingSecret,
    required sdk.A2ALocalPeerAdvertisement peer,
    required String remotePairingSecret,
  });

  Future<sdk.A2ALocalTransportStatus> startLocalA2A({
    required String agentId,
    required String displayName,
    String publicKey = '',
  });

  Future<sdk.A2ALocalTransportStatus> stopLocalA2A();

  Future<List<sdk.A2ALocalPeerAdvertisement>> discoverLocalA2APeers({
    int timeoutMs = 5000,
  });

  Future<sdk.A2APeerSession> openLocalA2ASession(
    sdk.A2ALocalPeerAdvertisement peer, {
    String sharedSecret = '',
  });

  Future<List<sdk.A2APeer>> listLocalA2APeers({String agentId = ''});

  Future<bool> deleteLocalA2APeer(String peerId);

  Future<sdk.A2APeerMessage> createLocalA2ATaskMessage(
    String sessionId,
    String message, {
    Map<String, dynamic> options = const {},
  });

  Future<sdk.A2APeerMessage> createLocalA2AProgressMessage(
    String sessionId,
    String taskId,
    String message, {
    String? status,
  });

  Future<sdk.A2APeerMessage> createLocalA2AResultMessage(
    String sessionId,
    String taskId,
    String message, {
    String? status,
  });

  Future<sdk.A2APeerMessage> createLocalA2ADiagnosticMessage({
    required String localPeerId,
  });

  Future<bool> sendLocalA2AMessage(
    sdk.A2APeerMessage message, {
    required String endpoint,
  });

  Future<bool> sendLocalA2ADiagnosticMessage(
    sdk.A2APeerMessage message, {
    required String endpoint,
  });

  Future<sdk.A2ADeliveryRecord> recordLocalA2AMessage(
    sdk.A2APeerMessage message, {
    String source = 'local_transport_require_trusted',
  });

  Future<List<sdk.A2ADeliveryRecord>> listLocalA2ADeliveryRecords(
    String sessionId, {
    int limit = 100,
    int offset = 0,
  });

  Future<List<sdk.A2APeerMessage>> listLocalA2APeerMessages(
    String sessionId, {
    int limit = 100,
    int offset = 0,
  });

  Future<sdk.A2ATaskRecord> runLocalA2ATask(String taskId);

  Future<sdk.A2ATaskRecord?> getLocalA2ATask(String taskId);

  Future<List<sdk.A2ATaskRecord>> listLocalA2ATasks({int limit = 50});

  Future<List<sdk.A2AArtifact>> resolveLocalA2AArtifacts(
    List<sdk.A2AArtifact> artifacts,
  );

  void dispose();
}

class NapaxiSdkChatClient implements NapaxiChatClient {
  NapaxiSdkChatClient();

  static final sdk.A2AApi _a2aStatelessHelper = sdk.A2AApi(() => 0);

  sdk.NapaxiEngine? _engine;
  sdk.NapaxiCapabilitySelection _activeCapabilitySelection =
      _withDemoBaselineCapabilities(const sdk.NapaxiCapabilitySelection());
  Future<sdk.NapaxiCapabilityProfile>? _demoCapabilityProfileFuture;
  final _automationToolExecutor = _DemoAutomationToolExecutor();
  @override
  late final sdk.NapaxiBrowserController browserController =
      _createBrowserController();

  sdk.NapaxiBrowserController _createBrowserController() {
    final backend = _DemoWebViewBrowserBackend();
    final controller = sdk.NapaxiBrowserController(backend: backend);
    // Bind the state listener after the controller exists, rather than
    // capturing `browserController` inside the backend's constructor. The old
    // form referenced the `late final` field from within its own initializer,
    // which threw LateInitializationError and recursed into a StackOverflow on
    // first access (hanging every real-client widget test).
    backend.onStateChanged = controller.notifyBackendStateChanged;
    return controller;
  }

  final Set<String> _memorySeededAgents = {};
  bool _mockAgentAppRegistered = false;
  final Map<String, sdk.QqBotChannelProvider> _demoQqChannelProviders = {};
  final Map<String, sdk.NapaxiChannelAgentBridge> _demoQqChannelBridges = {};
  final Map<String, StreamSubscription<DemoChannelBridgeEvent>>
  _demoQqChannelBridgeSubscriptions = {};
  final Map<String, sdk.BluetoothHeadsetChannelProvider>
  _demoHeadsetChannelProviders = {};
  final Map<String, sdk.NapaxiChannelAgentBridge> _demoHeadsetChannelBridges =
      {};
  final Map<String, StreamSubscription<DemoChannelBridgeEvent>>
  _demoHeadsetChannelBridgeSubscriptions = {};
  _DemoLocalA2AChannelProvider? _localA2AChannelProvider;
  sdk.NapaxiChannelAgentBridge? _localA2AChannelBridge;
  StreamSubscription<DemoChannelBridgeEvent>?
  _localA2AChannelBridgeSubscription;
  StreamSubscription<sdk.A2ALocalTransportEvent>? _localA2AAutoResponder;
  final Set<String> _localA2AAutoResponderMessageIds = {};
  final Set<String> _localA2AAutoResponderTaskIds = {};
  final Set<String> _localA2AAutoResponderHandledTaskIds = {};
  final Map<String, _A2ABlobReceiveManifest> _localA2ABlobManifests = {};
  final Map<String, sdk.A2AArtifact> _localA2AResolvedBlobArtifacts = {};
  final Map<String, Completer<void>> _localA2ABlobWaiters = {};
  bool _localA2AToolsEnabled = false;
  final Set<String> _demoQqChannelAutoConnecting = {};
  final Map<String, String> _demoQqChannelAutoConnectErrors = {};
  final Set<String> _demoHeadsetChannelAutoConnecting = {};
  final Map<String, String> _demoHeadsetChannelAutoConnectErrors = {};
  final StreamController<DemoChannelBridgeEvent> _channelBridgeEvents =
      StreamController<DemoChannelBridgeEvent>.broadcast();
  final FlutterSecureStorage _channelCredentialStore =
      const FlutterSecureStorage();
  _CliEngineBridge? _ccBridge;
  _CliEngineBridge? _codexBridge;
  Future<String?>? _cliWorkspaceHostPathFuture;

  DemoScenarioRuntimeProfile get _activeRuntimeProfile {
    final config = _activeCapabilitySelection.config;
    return _scenarioRuntimeProfileFor(
      config['scenario_id'] as String?,
      developerEngineId: config['developer_engine_id'] as String?,
    );
  }

  String get _activeAccountId => _activeRuntimeProfile.accountId;

  static const sdk.BackgroundConfig _androidBackgroundConfig =
      sdk.BackgroundConfig(
        notificationConfig: sdk.NotificationConfig(
          channelName: 'napaxi Agent',
          channelDescription: 'napaxi Agent is running',
          ongoingTitle: 'napaxi Agent',
          ongoingMessage: 'Agent and channels are running...',
          hitlTitle: 'Agent needs confirmation',
          completionMessage: 'Task completed. Tap to view.',
          errorPrefix: 'Task failed. Tap to view.',
          stopActionLabel: 'Stop',
          openActionLabel: 'Open',
        ),
        wakeLockTimeout: Duration(minutes: 30),
      );

  static const String _demoRuntimeGuidanceMarker =
      '[Napaxi demo runtime guidance]';
  static const String _localA2AToolCapabilityId = 'napaxi.tool.a2a';

  static const String _demoA2ARuntimeGuidance =
      '$_demoRuntimeGuidanceMarker\n'
      '- When the user asks to talk to, greet, ask, notify, discuss with, or delegate to a nearby/paired/trusted device, phone, iPhone, Android, or Agent, treat it as a local A2A request.\n'
      '- For local A2A requests, first call a2a_list_agents. If a target Agent is available, create a collaboration with a2a_start_collaboration, send the message with a2a_send_message, and wait with a2a_wait_messages when a reply is expected.\n'
      '- Do not narrate A2A transport steps to the user. Treat send/delivery/progress as runtime evidence, not as chat content.\n'
      '- A2A is a multi-turn conversation, not a single request/response. After a2a_wait_messages returns a remote reply, decide whether the goal is actually resolved. If not, send a follow-up, critique, answer, or synthesis request with a2a_send_message and wait again.\n'
      '- The user does not choose a number of turns. You decide whether to continue or stop from the observed conversation state and the user goal.\n'
      '- When a local A2A task needs photos or videos from this device, use the media_library platform tool to status/search/import authorized media into artifacts, then pass those artifacts to a2a_send_message. Use media_library action=pick only when direct library search/import is unavailable or the user should choose manually.\n'
      '- If a2a_wait_messages returns timedOut=true or noRemoteReply=true, say only that no reply has been received yet. Do not infer the other Agent is busy, absent, offline, choosing silence, or agreeing/disagreeing.\n'
      '- Do not close or summarize an A2A discussion as completed unless a2a_wait_messages returned at least one remote message and you have either reached a useful conclusion or the internal budget is exhausted, or the user explicitly asked not to wait.\n'
      '- Do not claim that you sent, asked, notified, or received a reply from another device unless the A2A tool result shows a successful delivery or observed remote message.\n'
      '- Successful A2A tool results are evidence for your next decision; they are not text to echo in the parent chat. The dedicated nearby-Agent conversation already shows turn-by-turn messages.\n'
      '- displayText is only user-facing for no-channel, no-reply, or explicit error states. Do not expose peerId, sessionId, taskId, messageId, endpoint, or other transport identifiers unless the user explicitly asks for diagnostics.\n'
      '- If no A2A peer is available, say only that no verified A2A channel is currently reachable. This does not prove the remote app is offline.';

  @override
  Future<void> configureForManagement({
    sdk.NapaxiCapabilitySelection? capabilitySelection,
  }) async {
    if (capabilitySelection != null) {
      _activeCapabilitySelection = _withDemoBaselineCapabilities(
        capabilitySelection,
      );
      _automationToolExecutor.updateRuntimeProfile(_activeRuntimeProfile);
    } else {
      await _restorePersistedDemoRuntimeSelection();
    }
    await _ensureEngine(
      sdk.LlmConfig(
        provider: '',
        apiKey: '',
        model: '',
        systemPrompt: 'You are napaxi, a helpful AI assistant.',
        userTimezone: await _systemUserTimezone(),
      ),
    );
  }

  Future<void> _restorePersistedDemoRuntimeSelection() async {
    final preferences = await SharedPreferences.getInstance();
    final scenarioId = _normalizeDemoScenarioId(
      preferences.getString(_ChatScreenState._activeScenarioKey),
    );
    final developerEngineId =
        preferences.getString(_activeDeveloperEngineKey) ??
        _defaultDeveloperEngineId;
    final gitSettings = await _loadDemoGitSettings();
    _activeCapabilitySelection = _withDemoBaselineCapabilities(
      _scenarioCapabilitySelection(
        scenarioId,
        gitSettings: gitSettings,
        developerEngineId: developerEngineId,
      ),
    );
    _automationToolExecutor.updateRuntimeProfile(_activeRuntimeProfile);
  }

  @override
  Future<void> configure(
    LlmModelProfile profile, {
    String responseLanguage = 'en',
    sdk.NapaxiCapabilitySelection? capabilitySelection,
  }) async {
    if (capabilitySelection != null) {
      _activeCapabilitySelection = _withDemoBaselineCapabilities(
        capabilitySelection,
      );
      _automationToolExecutor.updateRuntimeProfile(_activeRuntimeProfile);
    }
    await _ensureEngine(
      profile.toSdkConfig(
        responseLanguage: responseLanguage,
        userTimezone: await _systemUserTimezone(),
      ),
    );
  }

  @override
  Future<void> applyCapabilitySelection(
    sdk.NapaxiCapabilitySelection capabilitySelection,
  ) async {
    _activeCapabilitySelection = _withDemoBaselineCapabilities(
      capabilitySelection,
    );
    _automationToolExecutor.updateRuntimeProfile(_activeRuntimeProfile);
    final engine = _engine;
    if (engine == null) return;
    await _ensureEngine(engine.config);
  }

  Future<String?> _systemUserTimezone() async {
    try {
      final context = await sdk.NapaxiPlatformContextResolver.resolve();
      return context.userTimezone;
    } catch (_) {
      return null;
    }
  }

  Future<sdk.NapaxiCapabilityProfile> _demoCapabilityProfile() {
    return _demoCapabilityProfileFuture ??= _buildDemoCapabilityProfile();
  }

  Future<sdk.NapaxiCapabilityProfile> _buildDemoCapabilityProfile() async {
    String? platform;
    try {
      final context = await sdk.NapaxiPlatformContextResolver.resolve();
      final decoded = jsonDecode(context.platformContextJson);
      if (decoded is Map) {
        platform = decoded['platform'] as String?;
      }
    } catch (_) {
      if (Platform.isAndroid) {
        platform = 'android';
      } else if (Platform.isIOS) {
        platform = 'ios';
      }
    }
    return sdk.NapaxiCapabilityProfile(
      platform: platform,
      supportedCapabilities: [
        sdk.NapaxiChannelCapability.im,
        sdk.NapaxiChannelCapability.device,
        'napaxi.tool.custom_host',
        _localA2AToolCapabilityId,
        _DemoAutomationToolExecutor.gitCapabilityId,
        'napaxi.tool.agent_app_action',
        'napaxi.platform_tool.*',
        'napaxi.tool.browser',
        if (Platform.isAndroid) 'napaxi.service.automation',
      ],
    );
  }

  Future<sdk.NapaxiEngine> _ensureManagementEngine() async {
    if (_engine == null) {
      await configureForManagement();
    }
    return _requireEngine();
  }

  Future<void> _ensureEngine(
    sdk.LlmConfig config, {
    bool autoConnectChannels = true,
  }) async {
    final effectiveConfig = config.copyWith(
      systemPrompt: _effectiveDemoSystemPrompt(config.systemPrompt),
      capabilitySelection: _effectiveCapabilitySelection(),
      // Default the demo to native (paseo-style) git: the agent's shell `git`
      // runs directly against the `git` baked into the sandbox rootfs instead
      // of being redirected to structured tools. Harmless for non-git scenarios
      // (the redirect only engages under the mobile-development scenario). A
      // caller can still override by setting `config.git` explicitly.
      git: config.git ?? const sdk.GitConfig.native(),
    );
    final engine = _engine;
    if (engine != null) {
      final updated = engine.updateConfig(effectiveConfig);
      if (!updated) {
        throw StateError('Failed to update Napaxi engine runtime config');
      }
      if (Platform.isAndroid) {
        engine.updateBackgroundConfig(_androidBackgroundConfig);
      }
      _automationToolExecutor.attach(
        engine,
        defaultTimezone: effectiveConfig.userTimezone,
        owner: this,
      );
      await _ensureRuntimeAgent(engine);
      _registerMockAgentApp(engine);
      _syncScenarioTools(engine);
      if (autoConnectChannels) {
        unawaited(_autoConnectConfiguredDemoQqChannel(engine));
        unawaited(_autoConnectConfiguredDemoHeadsetChannel(engine));
      }
      return;
    }

    final capabilityProfile = await _demoCapabilityProfile();
    final createdEngine = await sdk.NapaxiEngine.create(
      config: effectiveConfig,
      toolExecutor: _automationToolExecutor,
      toolResultObserver: _automationToolExecutor.observeToolResult,
      agentAppActionExecutor: _DemoAgentAppActionExecutor(
        androidExecutor: Platform.isAndroid
            ? sdk.AndroidAgentProviderActionExecutor()
            : null,
        iosExecutor: Platform.isIOS
            ? sdk.IosAgentProviderActionExecutor()
            : null,
      ),
      browserController: browserController,
      browserMutationPolicy: sdk.BrowserMutationPolicy.allowAll,
      enablePlatformTools: true,
      backgroundConfig: Platform.isAndroid ? _androidBackgroundConfig : null,
      capabilityProfile: capabilityProfile,
      capabilitySelection: _effectiveCapabilitySelection(),
    );
    _automationToolExecutor.attach(
      createdEngine,
      defaultTimezone: effectiveConfig.userTimezone,
      owner: this,
    );
    await _ensureRuntimeAgent(createdEngine);
    _registerMockAgentApp(createdEngine);
    createdEngine.startToolRequestListener();
    _syncScenarioTools(createdEngine);
    _engine = createdEngine;
    if (autoConnectChannels) {
      unawaited(_autoConnectConfiguredDemoQqChannel(createdEngine));
      unawaited(_autoConnectConfiguredDemoHeadsetChannel(createdEngine));
    }
  }

  String _effectiveDemoSystemPrompt(String systemPrompt) {
    final prompt = _withoutDemoRuntimeGuidance(systemPrompt);
    if (!_localA2AToolsEnabled) return prompt;
    if (prompt.isEmpty) return _demoA2ARuntimeGuidance;
    return '$prompt\n\n$_demoA2ARuntimeGuidance';
  }

  static String _withoutDemoRuntimeGuidance(String systemPrompt) {
    final prompt = systemPrompt.trim();
    final markerIndex = prompt.indexOf(_demoRuntimeGuidanceMarker);
    if (markerIndex < 0) return prompt;
    return prompt.substring(0, markerIndex).trimRight();
  }

  static sdk.NapaxiCapabilitySelection _withDemoBaselineCapabilities(
    sdk.NapaxiCapabilitySelection selection,
  ) {
    final enabled = <String>{
      sdk.NapaxiChannelCapability.im,
      sdk.NapaxiChannelCapability.device,
      'napaxi.tool.agent_app_action',
      ...selection.enabledCapabilities,
    }.toList(growable: false);
    final disabled = selection.disabledCapabilities
        .where(
          (capabilityId) =>
              capabilityId != sdk.NapaxiChannelCapability.im &&
              capabilityId != sdk.NapaxiChannelCapability.device,
        )
        .toList(growable: false);
    return sdk.NapaxiCapabilitySelection(
      enabledCapabilities: enabled,
      disabledCapabilities: disabled,
      config: selection.config,
    );
  }

  sdk.NapaxiCapabilitySelection _effectiveCapabilitySelection([
    sdk.NapaxiCapabilitySelection? selection,
  ]) {
    final baseline = _withDemoBaselineCapabilities(
      selection ?? _activeCapabilitySelection,
    );
    final enabled = {...baseline.enabledCapabilities};
    final disabled = baseline.disabledCapabilities
        .where((capabilityId) => capabilityId != _localA2AToolCapabilityId)
        .toSet();
    if (_localA2AToolsEnabled) {
      enabled.add(_localA2AToolCapabilityId);
    } else {
      enabled.remove(_localA2AToolCapabilityId);
    }
    return sdk.NapaxiCapabilitySelection(
      enabledCapabilities: enabled.toList(growable: false)..sort(),
      disabledCapabilities: disabled.toList(growable: false)..sort(),
      config: baseline.config,
    );
  }

  void _syncScenarioTools(sdk.NapaxiEngine engine) {
    _automationToolExecutor.updateRuntimeProfile(_activeRuntimeProfile);
    engine.updateCustomTools(
      _automationToolExecutor.toolDefinitionsForSelection(
        _activeCapabilitySelection,
        includeA2A: _localA2AToolsEnabled,
      ),
    );
  }

  void _setLocalA2AToolsEnabled(bool enabled) {
    if (_localA2AToolsEnabled == enabled) return;
    _localA2AToolsEnabled = enabled;
    debugPrint('[napaxiToolTrace] local A2A tools enabled=$enabled');
    final engine = _engine;
    if (engine == null) return;
    _syncScenarioTools(engine);
    final updated = engine.updateConfig(
      engine.config.copyWith(
        systemPrompt: _effectiveDemoSystemPrompt(engine.config.systemPrompt),
        capabilitySelection: _effectiveCapabilitySelection(),
      ),
    );
    if (!updated) {
      debugPrint(
        '[napaxiToolTrace] failed to update A2A runtime guidance enabled=$enabled',
      );
    }
  }

  void _registerMockAgentApp(sdk.NapaxiEngine engine) {
    if (_mockAgentAppRegistered) return;
    engine.agentApp.registerPackage(
      const sdk.AgentAppPackage(
        providerId: 'demo_provider',
        agentId: 'demo.agent_app',
        displayName: 'Demo Agent App',
        description: 'Mock provider-backed Agent for validating action flow.',
        systemPrompt:
            'You are a demo provider-backed Agent. Use app_action_demo_order_create when the user asks to create or confirm an order.',
        actions: [
          sdk.AgentAppActionManifest(
            actionId: 'demo.order.create',
            toolName: 'app_action_demo_order_create',
            description: 'Create a mock order proposal in the demo provider.',
            parameters: {
              'type': 'object',
              'properties': {
                'item': {'type': 'string'},
                'amount': {'type': 'number'},
              },
              'required': ['item'],
            },
            resultSchema: {'type': 'object'},
            risk: 'high',
            confirmationPolicy: 'provider_required',
            executionModes: ['app_handoff'],
            timeoutSeconds: 600,
          ),
        ],
        handoff: {'mode': 'app_handoff', 'demo': true},
        result: {'mode': 'immediate_mock'},
      ),
    );
    _mockAgentAppRegistered = true;
  }

  @override
  Future<List<sdk.AgentProviderDescriptor>> discoverAgentProviders() {
    if (!Platform.isAndroid) return Future.value(const []);
    return _agentProviderInstallApi().discoverProviders();
  }

  @override
  Future<DemoAgent?> installPendingAgentProvider() async {
    final package = await _agentProviderInstallApi().installFromLaunchIntent();
    if (package == null) return null;
    await _reloadProviderAgent(package.agentId);
    final engine = await _ensureManagementEngine();
    final definition = await engine.getAgentDefinition(package.agentId);
    if (definition != null) return DemoAgent.fromDefinition(definition);
    return DemoAgent(
      id: package.agentId,
      name: package.displayName.trim().isEmpty
          ? package.agentId
          : package.displayName,
      icon: Icons.sensors_rounded,
      systemPrompt: package.systemPrompt,
    );
  }

  @override
  Future<sdk.AcceptedAgentTrigger?> consumePendingAgentTrigger() async {
    if (_engine == null) {
      await configureForManagement();
    }
    final engine = _requireEngine();
    final api = sdk.AgentProviderTriggerApi(
      getPackage: engine.agentApp.getPackage,
    );
    final request = await api.consumePendingTrigger();
    if (request == null) return null;
    return api.acceptTrigger(request);
  }

  @override
  Future<List<sdk.NapaxiChannelProviderManifest>> listChannelProviders() async {
    final qqCredentials = await _loadDemoQqCredentialList();
    final headsetCredentials = await _loadDemoHeadsetCredentialList();
    return [
      if (qqCredentials.isEmpty)
        sdk.QqBotChannelProvider.manifestFor(null)
      else
        for (final credentials in qqCredentials)
          sdk.QqBotChannelProvider.manifestFor(credentials),
      if (headsetCredentials.isEmpty)
        sdk.BluetoothHeadsetChannelProvider.manifestFor(null)
      else
        for (final credentials in headsetCredentials)
          sdk.BluetoothHeadsetChannelProvider.manifestFor(credentials),
    ];
  }

  @override
  Future<List<DemoChannelStatus>> listChannelStatuses() async {
    final statuses = <DemoChannelStatus>[];
    final qqCredentials = await _loadDemoQqCredentialList();
    if (qqCredentials.isEmpty) {
      statuses.add(await channelStatus(sdk.QqBotChannelProvider.channelName));
    } else {
      for (final credentials in qqCredentials) {
        statuses.add(
          await channelStatus(
            sdk.QqBotChannelProvider.channelName,
            accountId: credentials.appId,
          ),
        );
      }
    }
    final headsetCredentials = await _loadDemoHeadsetCredentialList();
    if (headsetCredentials.isEmpty) {
      statuses.add(
        await channelStatus(sdk.BluetoothHeadsetChannelProvider.channelName),
      );
    } else {
      for (final credentials in headsetCredentials) {
        statuses.add(
          await channelStatus(
            sdk.BluetoothHeadsetChannelProvider.channelName,
            accountId: credentials.accountId,
          ),
        );
      }
    }
    return statuses;
  }

  @override
  Future<List<DemoChannelInputSource>> listChannelInputSources({
    required String agentId,
  }) async {
    final normalizedAgentId = _normalizeDemoChannelAgentId(agentId);
    final statuses = await listChannelStatuses();
    final sources = <DemoChannelInputSource>[];
    for (final status in statuses) {
      if (status.manifest.channelName !=
          sdk.BluetoothHeadsetChannelProvider.channelName) {
        continue;
      }
      if (!status.configured || !status.connected) continue;
      if (!_demoStatusBelongsToAgent(status, normalizedAgentId)) continue;
      sources.add(DemoChannelInputSource.fromBluetoothHeadset(status));
    }
    sources.sort((a, b) => a.label.compareTo(b.label));
    return List.unmodifiable(sources);
  }

  @override
  Future<DemoChannelCredentials?> loadChannelCredentials(
    String channelName, {
    String? accountId,
  }) async {
    final normalized = _normalizeDemoChannelName(channelName);
    final credentials = await _loadChannelCredentialList(normalized);
    if (accountId != null) {
      final target = accountId.trim();
      for (final item in credentials) {
        if (_channelCredentialAccountId(item) == target) return item;
      }
      return null;
    }
    return credentials.isEmpty ? null : credentials.first;
  }

  @override
  Future<void> saveChannelCredentials(
    DemoChannelCredentials credentials,
  ) async {
    final normalized = _normalizeDemoChannelName(credentials.channelName);
    if (normalized == sdk.BluetoothHeadsetChannelProvider.channelName) {
      await _saveDemoHeadsetChannelCredentials(credentials);
      return;
    }
    if (normalized != sdk.QqBotChannelProvider.channelName) {
      throw UnsupportedError('Unsupported channel provider: $normalized');
    }
    final parsedQqCredentials = DemoQqChannelCredentials.fromChannelCredentials(
      DemoChannelCredentials(
        channelName: normalized,
        secrets: credentials.secrets,
        config: credentials.config,
      ),
    );
    final configuredSessionAccountId =
        credentials.config[DemoQqChannelCredentials.sessionAccountIdKey]
            ?.toString()
            .trim() ??
        '';
    final qqCredentials = await _demoQqCredentialsWithAvailableAgent(
      _demoQqCredentialsWithSessionAccountId(
        parsedQqCredentials,
        configuredSessionAccountId.isNotEmpty
            ? configuredSessionAccountId
            : _activeAccountId,
      ),
    );
    if (!qqCredentials.isConfigured) {
      throw ArgumentError('QQBot AppID and AppSecret are required.');
    }
    await _saveStoredChannelCredentials(qqCredentials.toChannelCredentials());
    final engine = _engine;
    if (engine != null) {
      _registerDemoQqChannelRoute(engine, qqCredentials);
    }
  }

  Future<void> _saveDemoHeadsetChannelCredentials(
    DemoChannelCredentials credentials,
  ) async {
    final parsed =
        DemoBluetoothHeadsetChannelCredentials.fromChannelCredentials(
          DemoChannelCredentials(
            channelName: sdk.BluetoothHeadsetChannelProvider.channelName,
            secrets: credentials.secrets,
            config: credentials.config,
          ),
        );
    final configuredSessionAccountId =
        credentials
            .config[DemoBluetoothHeadsetChannelCredentials.sessionAccountIdKey]
            ?.toString()
            .trim() ??
        '';
    final headsetCredentials = await _demoHeadsetCredentialsWithAvailableAgent(
      _demoHeadsetCredentialsWithSessionAccountId(
        parsed,
        configuredSessionAccountId.isNotEmpty
            ? configuredSessionAccountId
            : _activeAccountId,
      ),
    );
    if (!headsetCredentials.isConfigured) {
      throw ArgumentError('Bluetooth device id is required.');
    }
    await _saveStoredChannelCredentials(
      headsetCredentials.toChannelCredentials(),
    );
    final engine = _engine;
    if (engine != null) {
      _registerDemoHeadsetChannelRoute(engine, headsetCredentials);
    }
  }

  @override
  Future<void> clearChannelCredentials(
    String channelName, {
    String? accountId,
  }) async {
    final normalized = _normalizeDemoChannelName(channelName);
    final accounts = await _channelCredentialAccountsForClear(
      normalized,
      accountId: accountId,
    );
    for (final account in accounts) {
      await _channelCredentialStore.delete(
        key: _channelCredentialsKey(normalized, account),
      );
      await _removeChannelCredentialIndexEntry(normalized, account);
    }
    if (accountId == null) {
      await _channelCredentialStore.delete(
        key: _legacyChannelCredentialsKey(normalized),
      );
    }
    final engine = _engine;
    if (normalized == sdk.QqBotChannelProvider.channelName) {
      for (final account in accounts) {
        if (engine?.channelProviders.hasProvider(
              normalized,
              accountId: account,
            ) ==
            true) {
          await engine!.channelProviders.unregisterProvider(
            normalized,
            accountId: account,
          );
        }
        _demoQqChannelProviders.remove(account);
        _demoQqChannelAutoConnectErrors.remove(account);
        _demoQqChannelAutoConnecting.remove(account);
        _stopDemoQqChannelBridge(account);
      }
    } else if (normalized == sdk.BluetoothHeadsetChannelProvider.channelName) {
      for (final account in accounts) {
        if (engine?.channelProviders.hasProvider(
              normalized,
              accountId: account,
            ) ==
            true) {
          await engine!.channelProviders.unregisterProvider(
            normalized,
            accountId: account,
          );
        }
        _demoHeadsetChannelProviders.remove(account);
        _demoHeadsetChannelAutoConnectErrors.remove(account);
        _demoHeadsetChannelAutoConnecting.remove(account);
        _stopDemoHeadsetChannelBridge(account);
      }
    }
  }

  @override
  Future<DemoChannelStatus> channelStatus(
    String channelName, {
    String? accountId,
  }) async {
    final normalized = _normalizeDemoChannelName(channelName);
    if (normalized == sdk.BluetoothHeadsetChannelProvider.channelName) {
      return _headsetChannelStatus(accountId: accountId);
    }
    if (normalized != sdk.QqBotChannelProvider.channelName) {
      throw UnsupportedError('Unsupported channel provider: $normalized');
    }
    final engine = _engine;
    final channels =
        engine?.channels.list() ?? const <sdk.NapaxiChannelRecord>[];
    final credentials = await loadChannelCredentials(
      normalized,
      accountId: accountId,
    );
    final qqCredentials = credentials == null
        ? null
        : DemoQqChannelCredentials.fromChannelCredentials(credentials);
    final provider = accountId == null
        ? null
        : _demoQqChannelProviders[accountId.trim()];
    if (provider != null) {
      if (qqCredentials != null &&
          !_sameDemoQqProviderConfig(provider.credentials, qqCredentials)) {
        final providerAccountId = accountId!.trim();
        _stopDemoQqChannelBridge(providerAccountId, stopBackground: false);
        _demoQqChannelProviders.remove(providerAccountId);
        await engine?.channelProviders.unregisterProvider(
          sdk.QqBotChannelProvider.channelName,
          accountId: providerAccountId,
          unregisterChannel: false,
        );
      } else {
        if (engine != null) {
          _registerDemoQqChannelRoute(engine, provider.credentials);
        }
        return _withDemoQqChannelBridgeStatus(
          provider.status(channels: channels),
        );
      }
    }
    if (qqCredentials != null) {
      if (engine != null) {
        _registerDemoQqChannelRoute(engine, qqCredentials);
      }
      return _withDemoQqChannelBridgeStatus(
        sdk.QqBotChannelProvider(qqCredentials).status(channels: channels),
      );
    }
    return DemoChannelStatus(
      connected: false,
      configured: false,
      manifest: sdk.QqBotChannelProvider.manifestFor(null),
      channels: channels,
      mode: 'qqbot_gateway_openapi',
      gatewayPhase: 'unconfigured',
      bridgePhase: accountId == null
          ? null
          : _demoQqChannelBridges[accountId.trim()]?.status.phase,
      bridgeLastError: accountId == null
          ? null
          : _demoQqChannelBridges[accountId.trim()]?.status.lastError,
      bridgeProcessedCount: accountId == null
          ? 0
          : _demoQqChannelBridges[accountId.trim()]?.status.processedCount ?? 0,
      bridgeReplyCount: accountId == null
          ? 0
          : _demoQqChannelBridges[accountId.trim()]?.status.replyCount ?? 0,
    );
  }

  Future<DemoChannelStatus> _headsetChannelStatus({String? accountId}) async {
    final engine = _engine;
    final channels =
        engine?.channels.list() ?? const <sdk.NapaxiChannelRecord>[];
    final normalizedAccount = accountId?.trim();
    final credentials = await loadChannelCredentials(
      sdk.BluetoothHeadsetChannelProvider.channelName,
      accountId: accountId,
    );
    final headsetCredentials = credentials == null
        ? null
        : DemoBluetoothHeadsetChannelCredentials.fromChannelCredentials(
            credentials,
          );
    final provider = normalizedAccount?.isNotEmpty == true
        ? _demoHeadsetChannelProviders[normalizedAccount]
        : null;
    if (provider != null) {
      if (headsetCredentials != null &&
          !_sameDemoHeadsetProviderConfig(
            provider.credentials,
            headsetCredentials,
          )) {
        final providerAccountId = normalizedAccount!;
        _stopDemoHeadsetChannelBridge(providerAccountId, stopBackground: false);
        _demoHeadsetChannelProviders.remove(providerAccountId);
        await engine?.channelProviders.unregisterProvider(
          sdk.BluetoothHeadsetChannelProvider.channelName,
          accountId: providerAccountId,
          unregisterChannel: false,
        );
      } else {
        await provider.refreshDeviceState();
        if (engine != null) {
          _registerDemoHeadsetChannelRoute(engine, provider.credentials);
        }
        return _withDemoHeadsetChannelBridgeStatus(
          provider.status(channels: channels),
        );
      }
    }
    if (headsetCredentials != null) {
      if (engine != null) {
        _registerDemoHeadsetChannelRoute(engine, headsetCredentials);
      }
      return _withDemoHeadsetChannelBridgeStatus(
        _createDemoHeadsetChannelProvider(
          headsetCredentials,
        ).status(channels: channels),
      );
    }
    return DemoChannelStatus(
      connected: false,
      configured: false,
      manifest: sdk.BluetoothHeadsetChannelProvider.manifestFor(null),
      channels: channels,
      mode: 'bluetooth_headset_host_audio',
      deviceId: sdk.BluetoothHeadsetChannelCredentials.defaultDeviceId,
      deviceName: sdk.BluetoothHeadsetChannelCredentials.defaultDeviceName,
      bridgePhase: normalizedAccount?.isNotEmpty == true
          ? _demoHeadsetChannelBridges[normalizedAccount]?.status.phase
          : null,
      bridgeLastError: normalizedAccount?.isNotEmpty == true
          ? _demoHeadsetChannelBridges[normalizedAccount]?.status.lastError
          : null,
      bridgeProcessedCount: normalizedAccount?.isNotEmpty == true
          ? _demoHeadsetChannelBridges[normalizedAccount]
                    ?.status
                    .processedCount ??
                0
          : 0,
      bridgeReplyCount: normalizedAccount?.isNotEmpty == true
          ? _demoHeadsetChannelBridges[normalizedAccount]?.status.replyCount ??
                0
          : 0,
    );
  }

  @override
  Future<DemoChannelStatus> connectChannel(
    String channelName, {
    String? accountId,
  }) async {
    final normalized = _normalizeDemoChannelName(channelName);
    if (normalized == sdk.BluetoothHeadsetChannelProvider.channelName) {
      return _connectDemoHeadsetChannel(accountId: accountId);
    }
    if (normalized != sdk.QqBotChannelProvider.channelName) {
      throw UnsupportedError('Unsupported channel provider: $normalized');
    }
    final engine = await _ensureManagementEngine();
    final qqCredentials = await _loadDemoQqCredentials(accountId: accountId);
    if (qqCredentials == null || !qqCredentials.isConfigured) {
      return DemoChannelStatus(
        connected: false,
        configured: false,
        manifest: sdk.QqBotChannelProvider.manifestFor(null),
        channels: engine.channels.list(),
        mode: 'qqbot_gateway_openapi',
        gatewayPhase: 'unconfigured',
        lastError: 'Use /channel setup qqbot before connecting.',
      );
    }
    final qqAccountId = _demoQqChannelAccountId(qqCredentials);
    final existingProvider = _demoQqChannelProviders[qqAccountId];
    if (engine.channelProviders.hasProvider(
          normalized,
          accountId: qqAccountId,
        ) &&
        existingProvider != null &&
        _sameDemoQqProviderConfig(
          existingProvider.credentials,
          qqCredentials,
        )) {
      final existingStatus = existingProvider.status(
        channels: engine.channels.list(),
      );
      if (existingStatus.connected) {
        _demoQqChannelAutoConnectErrors.remove(qqAccountId);
        _registerDemoQqChannelRoute(engine, existingProvider.credentials);
        final ready = await _ensureDemoQqChannelRuntimeConfig(
          engine: engine,
          credentials: existingProvider.credentials,
        );
        if (ready &&
            _demoQqChannelBridges[qqAccountId]?.status.running != true) {
          _startDemoQqChannelBridge(
            engine: engine,
            credentials: existingProvider.credentials,
          );
        }
        return _withDemoQqChannelBridgeStatus(
          existingProvider.status(channels: engine.channels.list()),
        );
      }
    }
    if (_demoQqChannelAutoConnecting.contains(qqAccountId)) {
      return channelStatus(normalized, accountId: qqAccountId);
    }
    if (engine.channelProviders.hasProvider(
      normalized,
      accountId: qqAccountId,
    )) {
      _stopDemoQqChannelBridge(qqAccountId, stopBackground: false);
      _demoQqChannelProviders.remove(qqAccountId);
      await engine.channelProviders.unregisterProvider(
        normalized,
        accountId: qqAccountId,
        unregisterChannel: false,
      );
    }
    final provider = sdk.QqBotChannelProvider(qqCredentials);
    await engine.channelProviders.registerProvider(
      provider,
      autoPump: true,
      pollInterval: const Duration(seconds: 2),
    );
    _demoQqChannelProviders[qqAccountId] = provider;
    _registerDemoQqChannelRoute(engine, provider.credentials);
    final ready = await _ensureDemoQqChannelRuntimeConfig(
      engine: engine,
      credentials: provider.credentials,
    );
    if (!ready) {
      return _withDemoQqChannelBridgeStatus(
        provider.status(channels: engine.channels.list()),
      );
    }
    _startDemoQqChannelBridge(
      engine: engine,
      credentials: provider.credentials,
    );
    return _withDemoQqChannelBridgeStatus(
      provider.status(channels: engine.channels.list()),
    );
  }

  Future<DemoChannelStatus> _connectDemoHeadsetChannel({
    String? accountId,
  }) async {
    final engine = await _ensureManagementEngine();
    final credentials = await _loadDemoHeadsetCredentials(accountId: accountId);
    if (credentials == null || !credentials.isConfigured) {
      return DemoChannelStatus(
        connected: false,
        configured: false,
        manifest: sdk.BluetoothHeadsetChannelProvider.manifestFor(null),
        channels: engine.channels.list(),
        mode: 'bluetooth_headset_host_audio',
        lastError: 'Use /channel headset setup before connecting.',
      );
    }
    final headsetAccountId = _demoHeadsetChannelAccountId(credentials);
    final existingProvider = _demoHeadsetChannelProviders[headsetAccountId];
    if (engine.channelProviders.hasProvider(
          sdk.BluetoothHeadsetChannelProvider.channelName,
          accountId: headsetAccountId,
        ) &&
        existingProvider != null &&
        _sameDemoHeadsetProviderConfig(
          existingProvider.credentials,
          credentials,
        )) {
      await existingProvider.refreshDeviceState();
      final existingStatus = existingProvider.status(
        channels: engine.channels.list(),
      );
      if (existingStatus.connected) {
        _demoHeadsetChannelAutoConnectErrors.remove(headsetAccountId);
        _registerDemoHeadsetChannelRoute(engine, existingProvider.credentials);
        final ready = await _ensureDemoHeadsetChannelRuntimeConfig(
          engine: engine,
          credentials: existingProvider.credentials,
        );
        if (ready &&
            _demoHeadsetChannelBridges[headsetAccountId]?.status.running !=
                true) {
          _startDemoHeadsetChannelBridge(
            engine: engine,
            credentials: existingProvider.credentials,
          );
        }
        return _withDemoHeadsetChannelBridgeStatus(
          existingProvider.status(channels: engine.channels.list()),
        );
      }
    }
    if (_demoHeadsetChannelAutoConnecting.contains(headsetAccountId)) {
      return channelStatus(
        sdk.BluetoothHeadsetChannelProvider.channelName,
        accountId: headsetAccountId,
      );
    }
    if (engine.channelProviders.hasProvider(
      sdk.BluetoothHeadsetChannelProvider.channelName,
      accountId: headsetAccountId,
    )) {
      _stopDemoHeadsetChannelBridge(headsetAccountId, stopBackground: false);
      _demoHeadsetChannelProviders.remove(headsetAccountId);
      await engine.channelProviders.unregisterProvider(
        sdk.BluetoothHeadsetChannelProvider.channelName,
        accountId: headsetAccountId,
        unregisterChannel: false,
      );
    }
    final provider = _createDemoHeadsetChannelProvider(credentials);
    await engine.channelProviders.registerProvider(
      provider,
      autoPump: true,
      pollInterval: const Duration(seconds: 2),
    );
    _demoHeadsetChannelProviders[headsetAccountId] = provider;
    _registerDemoHeadsetChannelRoute(engine, provider.credentials);
    final ready = await _ensureDemoHeadsetChannelRuntimeConfig(
      engine: engine,
      credentials: provider.credentials,
    );
    if (!ready) {
      return _withDemoHeadsetChannelBridgeStatus(
        provider.status(channels: engine.channels.list()),
      );
    }
    _startDemoHeadsetChannelBridge(
      engine: engine,
      credentials: provider.credentials,
    );
    return _withDemoHeadsetChannelBridgeStatus(
      provider.status(channels: engine.channels.list()),
    );
  }

  sdk.BluetoothHeadsetChannelProvider _createDemoHeadsetChannelProvider(
    sdk.BluetoothHeadsetChannelCredentials credentials,
  ) {
    return sdk.BluetoothHeadsetChannelProvider.withPlatformAudio(credentials);
  }

  Future<DemoBluetoothHeadsetChannelCredentials?>
  _selectDemoHeadsetCredentialsForInput({
    String? accountId,
    String? agentId,
  }) async {
    final normalizedAccount = accountId?.trim();
    if (normalizedAccount?.isNotEmpty == true) {
      final credentials = await _loadDemoHeadsetCredentials(
        accountId: normalizedAccount,
      );
      if (!_demoHeadsetCredentialsBelongsToAgent(credentials, agentId)) {
        return null;
      }
      return credentials;
    }
    final credentials = await _loadDemoHeadsetCredentialList();
    for (final item in credentials) {
      if (_demoHeadsetCredentialsBelongsToAgent(item, agentId)) return item;
    }
    return null;
  }

  bool _demoHeadsetCredentialsBelongsToAgent(
    sdk.BluetoothHeadsetChannelCredentials? credentials,
    String? agentId,
  ) {
    if (credentials == null) return false;
    if (agentId == null || agentId.trim().isEmpty) return true;
    return _normalizeDemoChannelAgentId(credentials.agentId) ==
        _normalizeDemoChannelAgentId(agentId);
  }

  @override
  Future<DemoHeadsetTranscriptResult> captureHeadsetTranscript({
    String? accountId,
    String? agentId,
  }) async {
    final engine = await _ensureManagementEngine();
    final normalizedAccount = accountId?.trim();
    final normalizedAgentId = agentId == null
        ? null
        : _normalizeDemoChannelAgentId(agentId);
    sdk.BluetoothHeadsetChannelProvider? provider;
    String? providerAccountId;

    if (normalizedAccount?.isNotEmpty == true) {
      providerAccountId = normalizedAccount;
      provider = _demoHeadsetChannelProviders[providerAccountId];
      if (provider != null &&
          !_demoHeadsetCredentialsBelongsToAgent(
            provider.credentials,
            normalizedAgentId,
          )) {
        final status = await _headsetChannelStatus(
          accountId: providerAccountId,
        );
        return DemoHeadsetTranscriptResult(
          accepted: false,
          status: status,
          error: 'Bluetooth device channel is bound to another agent.',
        );
      }
    } else {
      for (final entry in _demoHeadsetChannelProviders.entries) {
        if (engine.channelProviders.hasProvider(
              sdk.BluetoothHeadsetChannelProvider.channelName,
              accountId: entry.key,
            ) &&
            entry.value.status().connected &&
            _demoHeadsetCredentialsBelongsToAgent(
              entry.value.credentials,
              normalizedAgentId,
            )) {
          providerAccountId = entry.key;
          provider = entry.value;
          break;
        }
      }
    }

    if (provider == null) {
      final credentials = await _selectDemoHeadsetCredentialsForInput(
        accountId: providerAccountId,
        agentId: normalizedAgentId,
      );
      providerAccountId = credentials == null
          ? providerAccountId
          : _demoHeadsetChannelAccountId(credentials);
      if (credentials == null) {
        final status = await _headsetChannelStatus(
          accountId: providerAccountId,
        );
        return DemoHeadsetTranscriptResult(
          accepted: false,
          status: status,
          error: normalizedAgentId == null
              ? 'Bluetooth device channel is not configured.'
              : 'No Bluetooth device channel is bound to this agent.',
        );
      }
      final status = await _connectDemoHeadsetChannel(
        accountId: providerAccountId,
      );
      if (!status.connected) {
        return DemoHeadsetTranscriptResult(
          accepted: false,
          status: status,
          error:
              status.lastError ?? 'Bluetooth device channel is not connected.',
        );
      }
      provider = providerAccountId == null
          ? null
          : _demoHeadsetChannelProviders[providerAccountId];
    }

    if (provider == null || providerAccountId == null) {
      final status = await _headsetChannelStatus(accountId: providerAccountId);
      return DemoHeadsetTranscriptResult(
        accepted: false,
        status: status,
        error: 'Bluetooth device provider is unavailable.',
      );
    }

    _registerDemoHeadsetChannelRoute(engine, provider.credentials);
    final runtimeReady = await _ensureDemoHeadsetChannelRuntimeConfig(
      engine: engine,
      credentials: provider.credentials,
    );
    if (!runtimeReady) {
      return DemoHeadsetTranscriptResult(
        accepted: false,
        status: _withDemoHeadsetChannelBridgeStatus(
          provider.status(channels: engine.channels.list()),
        ),
        error: 'Bluetooth device channel runtime is not configured.',
      );
    }
    if (_demoHeadsetChannelBridges[providerAccountId]?.status.running != true) {
      _startDemoHeadsetChannelBridge(
        engine: engine,
        credentials: provider.credentials,
      );
    }

    final capture = await provider.captureAndSubmit();
    if (!capture.submitted) {
      return DemoHeadsetTranscriptResult(
        accepted: false,
        status: _withDemoHeadsetChannelBridgeStatus(
          provider.status(channels: engine.channels.list()),
        ),
        transcript: capture.transcript?.text,
        error: capture.error,
      );
    }

    final bridge = _demoHeadsetChannelBridges[providerAccountId];
    bridge?.start();
    await bridge?.pump();
    await engine.channelProviders.pump(
      sdk.BluetoothHeadsetChannelProvider.channelName,
      accountId: providerAccountId,
    );
    return DemoHeadsetTranscriptResult(
      accepted: true,
      inboundId: capture.receipt?.id,
      transcript: capture.transcript?.text,
      error: capture.receipt?.error,
      status: _withDemoHeadsetChannelBridgeStatus(
        provider.status(channels: engine.channels.list()),
      ),
    );
  }

  @override
  Future<DemoHeadsetTranscriptResult> submitHeadsetTranscript({
    required String text,
  }) async {
    final engine = await _ensureManagementEngine();
    sdk.BluetoothHeadsetChannelProvider? provider;
    String? accountId;
    for (final entry in _demoHeadsetChannelProviders.entries) {
      if (engine.channelProviders.hasProvider(
            sdk.BluetoothHeadsetChannelProvider.channelName,
            accountId: entry.key,
          ) &&
          entry.value.status().connected) {
        accountId = entry.key;
        provider = entry.value;
        break;
      }
    }
    if (provider == null) {
      final credentials = await _loadDemoHeadsetCredentials();
      accountId = credentials == null
          ? null
          : _demoHeadsetChannelAccountId(credentials);
      final status = await _connectDemoHeadsetChannel(accountId: accountId);
      if (!status.connected) {
        return DemoHeadsetTranscriptResult(
          accepted: false,
          status: status,
          error:
              status.lastError ?? 'Bluetooth device channel is not connected.',
        );
      }
      provider = accountId == null
          ? null
          : _demoHeadsetChannelProviders[accountId];
    }
    if (provider == null) {
      final status = await _headsetChannelStatus(accountId: accountId);
      return DemoHeadsetTranscriptResult(
        accepted: false,
        status: status,
        error: 'Bluetooth device provider is unavailable.',
      );
    }
    final receipt = provider.submitVoiceTranscript(
      sdk.BluetoothHeadsetTranscript(text: text),
    );
    if (accountId != null) {
      _demoHeadsetChannelBridges[accountId]?.start();
      unawaited(_demoHeadsetChannelBridges[accountId]?.pump());
    }
    unawaited(
      engine.channelProviders.pump(
        sdk.BluetoothHeadsetChannelProvider.channelName,
        accountId: accountId,
      ),
    );
    return DemoHeadsetTranscriptResult(
      accepted: receipt.accepted,
      inboundId: receipt.id,
      transcript: text,
      error: receipt.error,
      status: _withDemoHeadsetChannelBridgeStatus(
        provider.status(channels: engine.channels.list()),
      ),
    );
  }

  @override
  Future<List<DemoChannelStatus>> ensureConfiguredChannelsConnected() async {
    final engine = await _ensureManagementEngine();
    await _autoConnectConfiguredDemoQqChannel(
      engine,
      reconnectDisconnected: true,
    );
    await _autoConnectConfiguredDemoHeadsetChannel(engine);
    final statuses = await listChannelStatuses();
    return [
      for (final status in statuses)
        if (status.configured) status,
    ];
  }

  Future<_DemoLocalA2AChannelProvider> _ensureLocalA2AChannelProvider() async {
    final engine = await _ensureManagementEngine();
    final existing = _localA2AChannelProvider;
    if (existing != null &&
        engine.channelProviders.hasProvider(
          _DemoLocalA2AChannelProvider.name,
        )) {
      return existing;
    }
    if (engine.channelProviders.hasProvider(
      _DemoLocalA2AChannelProvider.name,
    )) {
      await engine.channelProviders.unregisterProvider(
        _DemoLocalA2AChannelProvider.name,
      );
    }
    final provider = _DemoLocalA2AChannelProvider(engine, this);
    await engine.channelProviders.registerProvider(provider);
    _localA2AChannelProvider = provider;
    return provider;
  }

  Future<sdk.NapaxiChannelAgentBridge> _ensureLocalA2AChannelBridge(
    String agentId,
  ) async {
    final engine = await _ensureManagementEngine();
    final provider = await _ensureLocalA2AChannelProvider();
    final normalizedAgentId = agentId.trim().isEmpty
        ? sdk.NapaxiEngine.defaultAgentId
        : agentId.trim();
    final existing = _localA2AChannelBridge;
    if (existing != null && existing.agentId == normalizedAgentId) {
      return existing;
    }
    await _localA2AChannelBridgeSubscription?.cancel();
    await existing?.dispose(stopBackground: false);
    final bridge = sdk.NapaxiChannelAgentBridge(
      engine: engine,
      channelName: _DemoLocalA2AChannelProvider.name,
      accountId: _activeAccountId,
      channelAccountId: _DemoLocalA2AChannelProvider.accountId,
      agentId: normalizedAgentId,
      inboundBatchSize: 1,
      keepAliveInBackground: false,
      isProviderConnected: () => true,
      ensureAgent: _ensureAgent,
      bridgeId: 'local_a2a.channel_agent_bridge',
    );
    _localA2AChannelBridgeSubscription = bridge.events.listen((event) {
      _automationToolExecutor.setCurrentSession(
        event.session,
        agentId: event.agentId,
      );
      _channelBridgeEvents.add(provider.withUiContext(event));
      final error = event.error?.trim() ?? '';
      if (error.isNotEmpty) {
        debugPrint('[napaxiToolTrace] local A2A bridge event error=$error');
      }
    });
    _localA2AChannelBridge = bridge;
    return bridge;
  }

  @override
  Future<DemoLocalA2AChannelReceipt> submitLocalA2AChannelTask({
    required sdk.A2ATaskRecord task,
    required sdk.A2ALocalPeerAdvertisement peer,
  }) async {
    final provider = await _ensureLocalA2AChannelProvider();
    final collaboration = _a2aCollaborationFromTask(task);
    final taskMessage = _a2aUserFacingTaskMessage(task).trim();
    final sessionId = task.sessionId?.trim() ?? '';
    final conversationThreadId =
        collaboration['sessionId']?.toString().trim() ?? '';
    final visibleConversationSessionId = conversationThreadId.isEmpty
        ? 'nearby-agent:$sessionId'
        : _a2aVisibleConversationSessionIdForCollaboration(
            conversationThreadId,
          );
    final peerMessageId = task.peerMessageId?.trim().isNotEmpty == true
        ? task.peerMessageId!.trim()
        : task.envelopeId.trim();
    if (task.taskId.trim().isEmpty ||
        sessionId.isEmpty ||
        peer.peerId.trim().isEmpty ||
        peer.endpoint.trim().isEmpty ||
        taskMessage.isEmpty) {
      throw StateError('A2A task is missing task/session/peer/message data.');
    }
    final resolvedArtifacts = await _resolveLocalA2ABlobArtifacts(
      task.request.artifacts,
    );
    final artifactIssues = await _validateResolvedLocalA2AArtifacts(
      resolvedArtifacts,
      _requireEngine(),
    );
    if (artifactIssues.isNotEmpty) {
      throw StateError(
        'A2A attachment bytes are not available on this device: '
        '${jsonEncode(artifactIssues)}',
      );
    }
    provider.rememberTask(
      _DemoLocalA2AChannelTaskContext(
        taskId: task.taskId,
        sessionId: sessionId,
        peerMessageId: peerMessageId,
        peer: peer,
        visibleConversationSessionId: visibleConversationSessionId,
      ),
    );
    final receipt = _requireEngine().channels.submitInbound(
      sdk.NapaxiChannelInboundMessage(
        channelName: _DemoLocalA2AChannelProvider.name,
        accountId: _DemoLocalA2AChannelProvider.accountId,
        peer: sdk.NapaxiChannelPeer(
          kind: sdk.NapaxiChannelEndpointKind.device,
          id: peer.peerId,
          displayName: _a2aPeerDisplayLabel(peer),
        ),
        sender: sdk.NapaxiChannelActor(
          id: peer.peerId,
          displayName: _a2aPeerDisplayLabel(peer),
          isBot: true,
        ),
        platformMessageId: peerMessageId,
        threadId: conversationThreadId.isEmpty
            ? sessionId
            : conversationThreadId,
        text: taskMessage,
        media: _a2aChannelMediaFromArtifacts(resolvedArtifacts),
        raw: {
          'source': 'local_a2a',
          'task_id': task.taskId,
          'a2a_session_id': sessionId,
          if (conversationThreadId.isNotEmpty)
            'a2a_conversation_id': conversationThreadId,
          'peer_message_id': peerMessageId,
          'from_peer_id': peer.peerId,
          'a2a_collaboration': collaboration,
          'a2a_original_message': task.request.message,
          if (resolvedArtifacts.isNotEmpty)
            'a2a_artifacts': _a2aArtifactSummaryList(resolvedArtifacts),
          'endpoint': peer.endpoint,
          'transport': peer.transport,
        },
      ),
    );
    if (!receipt.accepted) {
      throw StateError(receipt.error ?? 'local_a2a channel rejected task');
    }
    provider.rememberInbound(task.taskId, receipt.id);
    return DemoLocalA2AChannelReceipt(
      taskId: task.taskId,
      inboundId: receipt.id,
      duplicate: receipt.duplicate,
    );
  }

  Map<String, dynamic> _a2aCollaborationFromTask(sdk.A2ATaskRecord task) {
    final collaboration = task.request.context['a2aCollaboration'];
    if (collaboration is Map) {
      return Map<String, dynamic>.from(collaboration);
    }
    return const <String, dynamic>{};
  }

  String _a2aUserFacingTaskMessage(sdk.A2ATaskRecord task) {
    final collaboration = _a2aCollaborationFromTask(task);
    final message = collaboration['message']?.toString().trim() ?? '';
    if (message.isNotEmpty) return message;
    return _a2aExtractCollaborationMessage(task.request.message);
  }

  @override
  Future<DemoLocalA2AChannelRun> runLocalA2AChannelTask({
    required String taskId,
    required String agentId,
  }) async {
    final provider = await _ensureLocalA2AChannelProvider();
    final bridge = await _ensureLocalA2AChannelBridge(agentId);
    provider.markActiveTask(taskId);
    final result = provider.waitForTaskResult(taskId);
    try {
      bridge.start();
      await bridge.pump();
      final delivered = await result;
      final summary = provider.takeTaskResultSummary(taskId);
      return DemoLocalA2AChannelRun(
        taskId: taskId,
        delivered: delivered,
        phase: bridge.status.phase,
        summary: summary,
        error: bridge.status.lastError,
      );
    } finally {
      bridge.stop(stopBackground: false);
      provider.clearActiveTask(taskId);
    }
  }

  Future<void> _autoConnectConfiguredDemoQqChannel(
    sdk.NapaxiEngine engine, {
    bool reconnectDisconnected = false,
  }) async {
    final credentialsList = await _loadDemoQqCredentialList();
    for (final credentials in credentialsList) {
      final accountId = _demoQqChannelAccountId(credentials);
      if (_demoQqChannelAutoConnecting.contains(accountId)) continue;
      try {
        _demoQqChannelAutoConnectErrors.remove(accountId);
        _registerDemoQqChannelRoute(engine, credentials);
        final runtimeReady = await _ensureDemoQqChannelRuntimeConfig(
          engine: engine,
          credentials: credentials,
        );
        if (!runtimeReady) continue;
        if (_demoQqChannelBridges[accountId]?.status.running != true) {
          _startDemoQqChannelBridge(engine: engine, credentials: credentials);
        }
        final provider = _demoQqChannelProviders[accountId];
        if (engine.channelProviders.hasProvider(
              sdk.QqBotChannelProvider.channelName,
              accountId: accountId,
            ) &&
            provider != null) {
          final connected = provider
              .status(channels: engine.channels.list())
              .connected;
          if (connected || !reconnectDisconnected) {
            if (_demoQqChannelBridges[accountId]?.status.running != true) {
              _startDemoQqChannelBridge(
                engine: engine,
                credentials: provider.credentials,
              );
            }
            continue;
          }
        }

        await _reconnectDemoQqProvider(engine, accountId: accountId);
        final reconnectedProvider = _demoQqChannelProviders[accountId];
        if (reconnectedProvider == null) continue;
        final reconnectedRuntimeReady = await _ensureDemoQqChannelRuntimeConfig(
          engine: engine,
          credentials: reconnectedProvider.credentials,
        );
        if (!reconnectedRuntimeReady) continue;
        if (_demoQqChannelBridges[accountId]?.status.running != true) {
          _startDemoQqChannelBridge(
            engine: engine,
            credentials: reconnectedProvider.credentials,
          );
        }
      } catch (error) {
        _demoQqChannelAutoConnectErrors[accountId] =
            'QQBot auto-connect failed: $error';
      }
    }
  }

  Future<void> _autoConnectConfiguredDemoHeadsetChannel(
    sdk.NapaxiEngine engine,
  ) async {
    final credentialsList = await _loadDemoHeadsetCredentialList();
    for (final credentials in credentialsList) {
      final accountId = _demoHeadsetChannelAccountId(credentials);
      if (_demoHeadsetChannelAutoConnecting.contains(accountId)) continue;
      try {
        _demoHeadsetChannelAutoConnectErrors.remove(accountId);
        _registerDemoHeadsetChannelRoute(engine, credentials);
        final runtimeReady = await _ensureDemoHeadsetChannelRuntimeConfig(
          engine: engine,
          credentials: credentials,
        );
        if (!runtimeReady) continue;
        if (_demoHeadsetChannelBridges[accountId]?.status.running != true) {
          _startDemoHeadsetChannelBridge(
            engine: engine,
            credentials: credentials,
          );
        }
        final provider = _demoHeadsetChannelProviders[accountId];
        if (engine.channelProviders.hasProvider(
              sdk.BluetoothHeadsetChannelProvider.channelName,
              accountId: accountId,
            ) &&
            provider != null &&
            provider.status(channels: engine.channels.list()).connected) {
          continue;
        }
        await _reconnectDemoHeadsetProvider(engine, accountId: accountId);
        final reconnectedProvider = _demoHeadsetChannelProviders[accountId];
        if (reconnectedProvider == null) continue;
        if (_demoHeadsetChannelBridges[accountId]?.status.running != true) {
          _startDemoHeadsetChannelBridge(
            engine: engine,
            credentials: reconnectedProvider.credentials,
          );
        }
      } catch (error) {
        _demoHeadsetChannelAutoConnectErrors[accountId] =
            'Bluetooth device auto-connect failed: $error';
      }
    }
  }

  Future<DemoQqChannelCredentials?> _loadDemoQqCredentials({
    String? accountId,
  }) async {
    final credentials = await loadChannelCredentials(
      sdk.QqBotChannelProvider.channelName,
      accountId: accountId,
    );
    if (credentials == null || !credentials.isConfigured) return null;
    var qqCredentials = DemoQqChannelCredentials.fromChannelCredentials(
      credentials,
    );
    if (!qqCredentials.isConfigured) return null;
    var changed = false;
    if (qqCredentials.sessionAccountId.trim().isEmpty) {
      qqCredentials = _demoQqCredentialsWithSessionAccountId(
        qqCredentials,
        _activeAccountId,
      );
      changed = true;
    }
    final resolvedCredentials = await _demoQqCredentialsWithAvailableAgent(
      qqCredentials,
    );
    if (changed ||
        resolvedCredentials.sessionAccountId !=
            qqCredentials.sessionAccountId ||
        resolvedCredentials.agentId != qqCredentials.agentId) {
      await _saveStoredChannelCredentials(
        resolvedCredentials.toChannelCredentials(),
      );
    }
    return resolvedCredentials;
  }

  Future<DemoBluetoothHeadsetChannelCredentials?> _loadDemoHeadsetCredentials({
    String? accountId,
  }) async {
    final credentials = await loadChannelCredentials(
      sdk.BluetoothHeadsetChannelProvider.channelName,
      accountId: accountId,
    );
    if (credentials == null || !credentials.isConfigured) return null;
    var headsetCredentials =
        DemoBluetoothHeadsetChannelCredentials.fromChannelCredentials(
          credentials,
        );
    if (!headsetCredentials.isConfigured) return null;
    var changed = false;
    if (headsetCredentials.sessionAccountId.trim().isEmpty) {
      headsetCredentials = _demoHeadsetCredentialsWithSessionAccountId(
        headsetCredentials,
        _activeAccountId,
      );
      changed = true;
    }
    final resolvedCredentials = await _demoHeadsetCredentialsWithAvailableAgent(
      headsetCredentials,
    );
    if (changed ||
        resolvedCredentials.sessionAccountId !=
            headsetCredentials.sessionAccountId ||
        resolvedCredentials.agentId != headsetCredentials.agentId) {
      await _saveStoredChannelCredentials(
        resolvedCredentials.toChannelCredentials(),
      );
    }
    return resolvedCredentials;
  }

  Future<List<DemoBluetoothHeadsetChannelCredentials>>
  _loadDemoHeadsetCredentialList() async {
    final credentials = await _loadChannelCredentialList(
      sdk.BluetoothHeadsetChannelProvider.channelName,
    );
    final items = <DemoBluetoothHeadsetChannelCredentials>[];
    for (final item in credentials) {
      if (!item.isConfigured) continue;
      final headsetCredentials =
          DemoBluetoothHeadsetChannelCredentials.fromChannelCredentials(item);
      if (!headsetCredentials.isConfigured) continue;
      var resolved = headsetCredentials;
      if (headsetCredentials.sessionAccountId.trim().isEmpty) {
        resolved = _demoHeadsetCredentialsWithSessionAccountId(
          headsetCredentials,
          _activeAccountId,
        );
      }
      resolved = await _demoHeadsetCredentialsWithAvailableAgent(resolved);
      if (resolved.sessionAccountId != headsetCredentials.sessionAccountId ||
          resolved.agentId != headsetCredentials.agentId) {
        await _saveStoredChannelCredentials(resolved.toChannelCredentials());
      }
      items.add(resolved);
    }
    return items;
  }

  DemoQqChannelCredentials _demoQqCredentialsWithSessionAccountId(
    DemoQqChannelCredentials credentials,
    String sessionAccountId,
  ) {
    return DemoQqChannelCredentials(
      appId: credentials.appId,
      appSecret: credentials.appSecret,
      sandbox: credentials.sandbox,
      intents: credentials.intents,
      agentId: credentials.agentId,
      sessionAccountId: sessionAccountId.trim(),
    );
  }

  DemoBluetoothHeadsetChannelCredentials
  _demoHeadsetCredentialsWithSessionAccountId(
    DemoBluetoothHeadsetChannelCredentials credentials,
    String sessionAccountId,
  ) {
    return DemoBluetoothHeadsetChannelCredentials(
      deviceId: credentials.deviceId,
      deviceName: credentials.deviceName,
      accountId: credentials.accountId,
      agentId: credentials.agentId,
      ttsEnabled: credentials.ttsEnabled,
      sessionAccountId: sessionAccountId.trim(),
    );
  }

  Future<DemoQqChannelCredentials> _demoQqCredentialsWithAvailableAgent(
    DemoQqChannelCredentials credentials,
  ) async {
    final agentId = await _resolveAvailableChannelAgentId(credentials.agentId);
    if (agentId == credentials.agentId.trim()) return credentials;
    return DemoQqChannelCredentials(
      appId: credentials.appId,
      appSecret: credentials.appSecret,
      sandbox: credentials.sandbox,
      intents: credentials.intents,
      agentId: agentId,
      sessionAccountId: credentials.sessionAccountId,
    );
  }

  Future<DemoBluetoothHeadsetChannelCredentials>
  _demoHeadsetCredentialsWithAvailableAgent(
    DemoBluetoothHeadsetChannelCredentials credentials,
  ) async {
    final agentId = await _resolveAvailableChannelAgentId(credentials.agentId);
    if (agentId == credentials.agentId.trim()) return credentials;
    return DemoBluetoothHeadsetChannelCredentials(
      deviceId: credentials.deviceId,
      deviceName: credentials.deviceName,
      accountId: credentials.accountId,
      agentId: agentId,
      ttsEnabled: credentials.ttsEnabled,
      sessionAccountId: credentials.sessionAccountId,
    );
  }

  Future<String> _resolveAvailableChannelAgentId(String agentId) async {
    final desired = agentId.trim();
    final agents = await listAgents();
    if (desired.isNotEmpty && agents.any((agent) => agent.id == desired)) {
      return desired;
    }
    if (agents.any((agent) => agent.id == sdk.NapaxiEngine.defaultAgentId)) {
      return sdk.NapaxiEngine.defaultAgentId;
    }
    return agents.isEmpty ? sdk.NapaxiEngine.defaultAgentId : agents.first.id;
  }

  Future<bool> _ensureDemoQqChannelRuntimeConfig({
    required sdk.NapaxiEngine engine,
    required sdk.QqBotChannelCredentials credentials,
  }) async {
    final accountId = _demoQqChannelAccountId(credentials);
    if (_isChannelRuntimeConfigReady(engine.config)) return true;
    final restoredConfig = await _loadStoredChannelRuntimeConfig(
      engine: engine,
      agentId: credentials.agentId,
    );
    if (restoredConfig != null &&
        _isChannelRuntimeConfigReady(restoredConfig)) {
      try {
        await _ensureEngine(restoredConfig, autoConnectChannels: false);
      } catch (error) {
        _stopDemoQqChannelBridge(accountId, stopBackground: false);
        _demoQqChannelAutoConnectErrors[accountId] =
            'QQBot is connected, but napaxi failed to apply the agent runtime '
            'model config: $error';
        return false;
      }
      if (!_isChannelRuntimeConfigReady(engine.config)) {
        _stopDemoQqChannelBridge(accountId, stopBackground: false);
        _demoQqChannelAutoConnectErrors[accountId] =
            'QQBot is connected, but the active agent runtime model config is '
            'not ready after restore.';
        return false;
      }
      _demoQqChannelAutoConnectErrors.remove(accountId);
      return true;
    }
    _stopDemoQqChannelBridge(accountId, stopBackground: false);
    _demoQqChannelAutoConnectErrors[accountId] =
        'QQBot is connected, but agent ${credentials.agentId} has no ready '
        'LLM model profile. Configure a model before sending QQ messages.';
    return false;
  }

  Future<bool> _ensureDemoHeadsetChannelRuntimeConfig({
    required sdk.NapaxiEngine engine,
    required sdk.BluetoothHeadsetChannelCredentials credentials,
  }) async {
    final accountId = _demoHeadsetChannelAccountId(credentials);
    if (_isChannelRuntimeConfigReady(engine.config)) return true;
    final restoredConfig = await _loadStoredChannelRuntimeConfig(
      engine: engine,
      agentId: credentials.agentId,
    );
    if (restoredConfig != null &&
        _isChannelRuntimeConfigReady(restoredConfig)) {
      try {
        await _ensureEngine(restoredConfig, autoConnectChannels: false);
      } catch (error) {
        _stopDemoHeadsetChannelBridge(accountId, stopBackground: false);
        _demoHeadsetChannelAutoConnectErrors[accountId] =
            'Bluetooth device is connected, but napaxi failed to apply the '
            'agent runtime model config: $error';
        return false;
      }
      if (!_isChannelRuntimeConfigReady(engine.config)) {
        _stopDemoHeadsetChannelBridge(accountId, stopBackground: false);
        _demoHeadsetChannelAutoConnectErrors[accountId] =
            'Bluetooth device is connected, but the active agent runtime '
            'model config is not ready after restore.';
        return false;
      }
      _demoHeadsetChannelAutoConnectErrors.remove(accountId);
      return true;
    }
    _stopDemoHeadsetChannelBridge(accountId, stopBackground: false);
    _demoHeadsetChannelAutoConnectErrors[accountId] =
        'Bluetooth device is connected, but agent ${credentials.agentId} has '
        'no ready LLM model profile. Configure a model before speaking.';
    return false;
  }

  Future<sdk.LlmConfig?> _loadStoredChannelRuntimeConfig({
    required sdk.NapaxiEngine engine,
    required String agentId,
  }) async {
    final store = sdk.NapaxiConfigStore.instance;
    final profiles = await store.loadProfiles();
    if (profiles.isEmpty) return null;
    final selection = await store.loadSelection();
    final restoredProfiles = <LlmModelProfile>[];
    for (final profile in profiles) {
      final apiKey = await store.readApiKey(profile.id);
      restoredProfiles.add(_profileFromStoredProfile(profile, apiKey));
    }
    final configState = LlmConfigState(
      profiles: List.unmodifiable(restoredProfiles),
      selectedProfileId: selection.selectedProfileId,
      selectedProfileIdByCapability: _capabilitySelectionFromStored(selection),
      systemPrompt: selection.systemPrompt.trim().isNotEmpty
          ? selection.systemPrompt.trim()
          : restoredProfiles
                .map((profile) => profile.systemPrompt.trim())
                .firstWhere((prompt) => prompt.isNotEmpty, orElse: () => ''),
      maxToolIterations: selection.maxToolIterations,
    );
    final modelProfileId = await _modelProfileIdForChannelAgent(
      engine,
      agentId,
    );
    final runtimeProfile = configState.runtimeProfileFor(
      chatProfileId: modelProfileId,
    );
    if (runtimeProfile == null ||
        !runtimeProfile.hasModel ||
        runtimeProfile.apiKey.trim().isEmpty) {
      return null;
    }
    return runtimeProfile
        .toSdkConfig(
          responseLanguage: _channelResponseLanguageCode,
          userTimezone: await _systemUserTimezone(),
        )
        .copyWith(maxToolIterations: configState.maxToolIterations);
  }

  Future<String?> _modelProfileIdForChannelAgent(
    sdk.NapaxiEngine engine,
    String agentId,
  ) async {
    final normalized = agentId.trim();
    if (normalized.isEmpty || normalized == sdk.NapaxiEngine.defaultAgentId) {
      return null;
    }
    try {
      final definition = await engine.getAgentDefinition(normalized);
      final modelProfileId = definition?.modelProfileId?.trim();
      return modelProfileId == null || modelProfileId.isEmpty
          ? null
          : modelProfileId;
    } catch (_) {
      return null;
    }
  }

  bool _isChannelRuntimeConfigReady(sdk.LlmConfig config) {
    return config.provider.trim().isNotEmpty &&
        config.model.trim().isNotEmpty &&
        config.apiKey.trim().isNotEmpty;
  }

  String get _channelResponseLanguageCode {
    final languageCode = ui.PlatformDispatcher.instance.locale.languageCode
        .toLowerCase();
    return languageCode == 'zh' ? 'zh' : 'en';
  }

  void _startDemoQqChannelBridge({
    required sdk.NapaxiEngine engine,
    required sdk.QqBotChannelCredentials credentials,
  }) {
    final accountId = _demoQqChannelAccountId(credentials);
    _stopDemoQqChannelBridge(accountId, stopBackground: false);
    final bridge = sdk.NapaxiChannelAgentBridge(
      engine: engine,
      channelName: sdk.QqBotChannelProvider.channelName,
      accountId: _activeAccountId,
      channelAccountId: credentials.appId,
      agentId: credentials.agentId,
      keepAliveInBackground: Platform.isAndroid,
      backgroundConfig: Platform.isAndroid ? _androidBackgroundConfig : null,
      isProviderConnected: () {
        return _demoQqChannelProviders[accountId]?.status().connected ?? false;
      },
      reconnectProvider: () =>
          _reconnectDemoQqProvider(engine, accountId: accountId),
      ensureAgent: _ensureAgent,
    );
    _demoQqChannelBridges[accountId] = bridge;
    _demoQqChannelBridgeSubscriptions[accountId] = bridge.events.listen((
      event,
    ) {
      _automationToolExecutor.setCurrentSession(
        event.session,
        agentId: event.agentId,
      );
      _channelBridgeEvents.add(event);
    });
    bridge.start();
  }

  void _startDemoHeadsetChannelBridge({
    required sdk.NapaxiEngine engine,
    required sdk.BluetoothHeadsetChannelCredentials credentials,
  }) {
    final accountId = _demoHeadsetChannelAccountId(credentials);
    _stopDemoHeadsetChannelBridge(accountId, stopBackground: false);
    final bridge = sdk.NapaxiChannelAgentBridge(
      engine: engine,
      channelName: sdk.BluetoothHeadsetChannelProvider.channelName,
      accountId: _activeAccountId,
      channelAccountId: credentials.accountId,
      agentId: credentials.agentId,
      keepAliveInBackground: Platform.isAndroid,
      backgroundConfig: Platform.isAndroid ? _androidBackgroundConfig : null,
      isProviderConnected: () {
        return _demoHeadsetChannelProviders[accountId]?.status().connected ??
            false;
      },
      reconnectProvider: () =>
          _reconnectDemoHeadsetProvider(engine, accountId: accountId),
      ensureAgent: _ensureAgent,
    );
    _demoHeadsetChannelBridges[accountId] = bridge;
    _demoHeadsetChannelBridgeSubscriptions[accountId] = bridge.events.listen((
      event,
    ) {
      _automationToolExecutor.setCurrentSession(
        event.session,
        agentId: event.agentId,
      );
      _channelBridgeEvents.add(event);
    });
    bridge.start();
  }

  void _registerDemoQqChannelRoute(
    sdk.NapaxiEngine engine,
    sdk.QqBotChannelCredentials credentials,
  ) {
    _removeStaleDemoQqChannelRoutes(engine, credentials);
    final sessionAccountId = _demoQqSessionAccountId(credentials);
    engine.channelAgents.registerRoute(
      sdk.NapaxiChannelAgentRoute.channelDefault(
        channelName: sdk.QqBotChannelProvider.channelName,
        channelAccountId: credentials.appId,
        sessionAccountId: sessionAccountId,
        agentId: credentials.agentId,
      ),
    );
  }

  void _registerDemoHeadsetChannelRoute(
    sdk.NapaxiEngine engine,
    sdk.BluetoothHeadsetChannelCredentials credentials,
  ) {
    _removeStaleDemoHeadsetChannelRoutes(engine, credentials);
    final sessionAccountId = _demoHeadsetSessionAccountId(credentials);
    engine.channelAgents.registerRoute(
      sdk.NapaxiChannelAgentRoute.channelDefault(
        channelName: sdk.BluetoothHeadsetChannelProvider.channelName,
        channelAccountId: credentials.accountId,
        sessionAccountId: sessionAccountId,
        agentId: credentials.agentId,
      ),
    );
  }

  void _removeStaleDemoQqChannelRoutes(
    sdk.NapaxiEngine engine,
    sdk.QqBotChannelCredentials credentials,
  ) {
    final currentSessionAccountId = _demoQqSessionAccountId(credentials);
    final currentAgentId = credentials.agentId.trim().isEmpty
        ? sdk.NapaxiEngine.defaultAgentId
        : credentials.agentId.trim();
    final currentChannelAccountId = credentials.appId.trim();
    for (final route in engine.channelAgents.listRoutes(
      channelName: sdk.QqBotChannelProvider.channelName,
    )) {
      final routeChannelAccountId = route.channelAccountId?.trim() ?? '';
      final routeAgentId = route.agentId.trim().isEmpty
          ? sdk.NapaxiEngine.defaultAgentId
          : route.agentId.trim();
      final routeIsChannelDefault =
          (route.peerKind?.trim().isEmpty ?? true) &&
          (route.peerId?.trim().isEmpty ?? true) &&
          (route.threadId?.trim().isEmpty ?? true);
      if (!routeIsChannelDefault ||
          route.id.trim().isEmpty ||
          routeChannelAccountId != currentChannelAccountId) {
        continue;
      }
      if (routeAgentId == currentAgentId &&
          route.sessionAccountId == currentSessionAccountId) {
        continue;
      }
      engine.channelAgents.removeRoute(route.id);
    }
  }

  void _removeStaleDemoHeadsetChannelRoutes(
    sdk.NapaxiEngine engine,
    sdk.BluetoothHeadsetChannelCredentials credentials,
  ) {
    final currentSessionAccountId = _demoHeadsetSessionAccountId(credentials);
    final currentAgentId = credentials.agentId.trim().isEmpty
        ? sdk.NapaxiEngine.defaultAgentId
        : credentials.agentId.trim();
    final currentChannelAccountId = credentials.accountId.trim();
    for (final route in engine.channelAgents.listRoutes(
      channelName: sdk.BluetoothHeadsetChannelProvider.channelName,
    )) {
      final routeChannelAccountId = route.channelAccountId?.trim() ?? '';
      final routeAgentId = route.agentId.trim().isEmpty
          ? sdk.NapaxiEngine.defaultAgentId
          : route.agentId.trim();
      final routeIsChannelDefault =
          (route.peerKind?.trim().isEmpty ?? true) &&
          (route.peerId?.trim().isEmpty ?? true) &&
          (route.threadId?.trim().isEmpty ?? true);
      if (!routeIsChannelDefault ||
          route.id.trim().isEmpty ||
          routeChannelAccountId != currentChannelAccountId) {
        continue;
      }
      if (routeAgentId == currentAgentId &&
          route.sessionAccountId == currentSessionAccountId) {
        continue;
      }
      engine.channelAgents.removeRoute(route.id);
    }
  }

  String _demoQqSessionAccountId(sdk.QqBotChannelCredentials credentials) {
    if (credentials is DemoQqChannelCredentials) {
      final configured = credentials.sessionAccountId.trim();
      if (configured.isNotEmpty) return configured;
    }
    return _activeAccountId;
  }

  String _demoHeadsetSessionAccountId(
    sdk.BluetoothHeadsetChannelCredentials credentials,
  ) {
    if (credentials is DemoBluetoothHeadsetChannelCredentials) {
      final configured = credentials.sessionAccountId.trim();
      if (configured.isNotEmpty) return configured;
    }
    return _activeAccountId;
  }

  void _stopDemoQqChannelBridge(
    String accountId, {
    bool stopBackground = true,
  }) {
    final subscription = _demoQqChannelBridgeSubscriptions.remove(accountId);
    unawaited(subscription?.cancel() ?? Future<void>.value());
    final bridge = _demoQqChannelBridges.remove(accountId);
    if (bridge != null) {
      unawaited(bridge.dispose(stopBackground: stopBackground));
    }
  }

  void _stopAllDemoQqChannelBridges({bool stopBackground = true}) {
    for (final accountId in _demoQqChannelBridges.keys.toList()) {
      _stopDemoQqChannelBridge(accountId, stopBackground: stopBackground);
    }
  }

  void _stopDemoHeadsetChannelBridge(
    String accountId, {
    bool stopBackground = true,
  }) {
    final subscription = _demoHeadsetChannelBridgeSubscriptions.remove(
      accountId,
    );
    unawaited(subscription?.cancel() ?? Future<void>.value());
    final bridge = _demoHeadsetChannelBridges.remove(accountId);
    if (bridge != null) {
      unawaited(bridge.dispose(stopBackground: stopBackground));
    }
  }

  void _stopAllDemoHeadsetChannelBridges({bool stopBackground = true}) {
    for (final accountId in _demoHeadsetChannelBridges.keys.toList()) {
      _stopDemoHeadsetChannelBridge(accountId, stopBackground: stopBackground);
    }
  }

  Future<void> _reconnectDemoQqProvider(
    sdk.NapaxiEngine engine, {
    required String accountId,
  }) async {
    if (_demoQqChannelAutoConnecting.contains(accountId)) return;
    _demoQqChannelAutoConnecting.add(accountId);
    try {
      if (engine.channelProviders.hasProvider(
        sdk.QqBotChannelProvider.channelName,
        accountId: accountId,
      )) {
        _demoQqChannelProviders.remove(accountId);
        await engine.channelProviders.unregisterProvider(
          sdk.QqBotChannelProvider.channelName,
          accountId: accountId,
          unregisterChannel: false,
        );
      }
      final credentials = await loadChannelCredentials(
        sdk.QqBotChannelProvider.channelName,
        accountId: accountId,
      );
      if (credentials == null || !credentials.isConfigured) return;
      final qqCredentials = DemoQqChannelCredentials.fromChannelCredentials(
        credentials,
      );
      if (!qqCredentials.isConfigured) return;
      final provider = sdk.QqBotChannelProvider(qqCredentials);
      await engine.channelProviders.registerProvider(
        provider,
        autoPump: true,
        pollInterval: const Duration(seconds: 2),
      );
      _demoQqChannelProviders[accountId] = provider;
      _demoQqChannelAutoConnectErrors.remove(accountId);
    } catch (error) {
      _demoQqChannelAutoConnectErrors[accountId] =
          'QQBot provider reconnect failed: $error';
      rethrow;
    } finally {
      _demoQqChannelAutoConnecting.remove(accountId);
    }
  }

  Future<void> _reconnectDemoHeadsetProvider(
    sdk.NapaxiEngine engine, {
    required String accountId,
  }) async {
    if (_demoHeadsetChannelAutoConnecting.contains(accountId)) return;
    _demoHeadsetChannelAutoConnecting.add(accountId);
    try {
      if (engine.channelProviders.hasProvider(
        sdk.BluetoothHeadsetChannelProvider.channelName,
        accountId: accountId,
      )) {
        _demoHeadsetChannelProviders.remove(accountId);
        await engine.channelProviders.unregisterProvider(
          sdk.BluetoothHeadsetChannelProvider.channelName,
          accountId: accountId,
          unregisterChannel: false,
        );
      }
      final credentials = await loadChannelCredentials(
        sdk.BluetoothHeadsetChannelProvider.channelName,
        accountId: accountId,
      );
      if (credentials == null || !credentials.isConfigured) return;
      final headsetCredentials =
          DemoBluetoothHeadsetChannelCredentials.fromChannelCredentials(
            credentials,
          );
      if (!headsetCredentials.isConfigured) return;
      final provider = _createDemoHeadsetChannelProvider(headsetCredentials);
      await engine.channelProviders.registerProvider(
        provider,
        autoPump: true,
        pollInterval: const Duration(seconds: 2),
      );
      _demoHeadsetChannelProviders[accountId] = provider;
      _demoHeadsetChannelAutoConnectErrors.remove(accountId);
    } catch (error) {
      _demoHeadsetChannelAutoConnectErrors[accountId] =
          'Bluetooth device provider reconnect failed: $error';
      rethrow;
    } finally {
      _demoHeadsetChannelAutoConnecting.remove(accountId);
    }
  }

  DemoChannelStatus _withDemoQqChannelBridgeStatus(
    sdk.QqBotChannelStatus status,
  ) {
    final accountId = status.manifest.accountId.trim();
    final bridgeStatus = accountId.isEmpty
        ? null
        : _demoQqChannelBridges[accountId]?.status;
    final autoConnectError = accountId.isEmpty
        ? null
        : _demoQqChannelAutoConnectErrors[accountId];
    final channelStatus = DemoChannelStatus.fromQqBot(
      status,
      bridgeStatus: bridgeStatus,
    );
    return channelStatus.copyWith(
      lastError: channelStatus.lastError ?? autoConnectError,
      bridgeLastError: channelStatus.bridgeLastError ?? autoConnectError,
    );
  }

  DemoChannelStatus _withDemoHeadsetChannelBridgeStatus(
    sdk.BluetoothHeadsetChannelStatus status,
  ) {
    final accountId = status.manifest.accountId.trim();
    final bridgeStatus = accountId.isEmpty
        ? null
        : _demoHeadsetChannelBridges[accountId]?.status;
    final autoConnectError = accountId.isEmpty
        ? null
        : _demoHeadsetChannelAutoConnectErrors[accountId];
    final channelStatus = DemoChannelStatus.fromBluetoothHeadset(
      status,
      bridgeStatus: bridgeStatus,
    );
    return channelStatus.copyWith(
      lastError: channelStatus.lastError ?? autoConnectError,
      bridgeLastError: channelStatus.bridgeLastError ?? autoConnectError,
    );
  }

  String _normalizeDemoChannelName(String channelName) {
    final normalized = channelName.trim().toLowerCase();
    if (normalized == 'qq' || normalized == 'qqbot') {
      return sdk.QqBotChannelProvider.channelName;
    }
    if (normalized == 'headset' ||
        normalized == 'bluetooth' ||
        normalized == 'bluetooth_headset' ||
        normalized == 'bt_headset') {
      return sdk.BluetoothHeadsetChannelProvider.channelName;
    }
    return normalized;
  }

  Future<List<DemoQqChannelCredentials>> _loadDemoQqCredentialList() async {
    final credentials = await _loadChannelCredentialList(
      sdk.QqBotChannelProvider.channelName,
    );
    final items = <DemoQqChannelCredentials>[];
    for (final item in credentials) {
      if (!item.isConfigured) continue;
      final qqCredentials = DemoQqChannelCredentials.fromChannelCredentials(
        item,
      );
      if (!qqCredentials.isConfigured) continue;
      var resolved = qqCredentials;
      if (qqCredentials.sessionAccountId.trim().isEmpty) {
        resolved = _demoQqCredentialsWithSessionAccountId(
          qqCredentials,
          _activeAccountId,
        );
      }
      resolved = await _demoQqCredentialsWithAvailableAgent(resolved);
      if (resolved.sessionAccountId != qqCredentials.sessionAccountId ||
          resolved.agentId != qqCredentials.agentId) {
        await _saveStoredChannelCredentials(resolved.toChannelCredentials());
      }
      items.add(resolved);
    }
    return items;
  }

  Future<List<DemoChannelCredentials>> _loadChannelCredentialList(
    String channelName,
  ) async {
    final normalized = _normalizeDemoChannelName(channelName);
    final accounts = await _readChannelCredentialIndex(normalized);
    final items = <DemoChannelCredentials>[];
    final seen = <String>{};
    for (final account in accounts) {
      final credentials = await _readStoredChannelCredentials(
        normalized,
        accountId: account,
      );
      if (credentials == null) continue;
      final resolvedAccount = _channelCredentialAccountId(credentials);
      if (seen.add(resolvedAccount)) items.add(credentials);
    }
    final legacy = await _readStoredChannelCredentials(normalized);
    if (legacy != null && legacy.isConfigured) {
      final account = _channelCredentialAccountId(legacy);
      if (seen.add(account)) {
        await _saveStoredChannelCredentials(legacy);
        items.add(legacy);
      }
    }
    return items;
  }

  Future<DemoChannelCredentials?> _readStoredChannelCredentials(
    String channelName, {
    String? accountId,
  }) async {
    final normalized = _normalizeDemoChannelName(channelName);
    final encoded = await _channelCredentialStore.read(
      key: accountId == null
          ? _legacyChannelCredentialsKey(normalized)
          : _channelCredentialsKey(normalized, accountId),
    );
    if (encoded == null || encoded.trim().isEmpty) return null;
    try {
      final decoded = jsonDecode(encoded);
      if (decoded is! Map) return null;
      return DemoChannelCredentials(
        channelName: normalized,
        secrets: Map<String, String>.from(
          decoded['secrets'] as Map? ?? const {},
        ),
        config: Map<String, dynamic>.from(
          decoded['config'] as Map? ?? const {},
        ),
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> _saveStoredChannelCredentials(
    DemoChannelCredentials credentials,
  ) async {
    final normalized = _normalizeDemoChannelName(credentials.channelName);
    final accountId = _channelCredentialAccountId(credentials);
    await _channelCredentialStore.write(
      key: _channelCredentialsKey(normalized, accountId),
      value: jsonEncode({
        'channel_name': normalized,
        'secrets': credentials.secrets,
        'config': credentials.config,
      }),
    );
    await _addChannelCredentialIndexEntry(normalized, accountId);
  }

  Future<List<String>> _channelCredentialAccountsForClear(
    String channelName, {
    String? accountId,
  }) async {
    final normalized = _normalizeDemoChannelName(channelName);
    if (accountId?.trim().isNotEmpty == true) return [accountId!.trim()];
    final accounts = await _readChannelCredentialIndex(normalized);
    final result = <String>{...accounts};
    final legacy = await _readStoredChannelCredentials(normalized);
    if (legacy != null && legacy.isConfigured) {
      result.add(_channelCredentialAccountId(legacy));
    }
    return result.toList(growable: false);
  }

  Future<List<String>> _readChannelCredentialIndex(String channelName) async {
    final encoded = await _channelCredentialStore.read(
      key: _channelCredentialIndexKey(channelName),
    );
    if (encoded == null || encoded.trim().isEmpty) return const [];
    try {
      final decoded = jsonDecode(encoded);
      if (decoded is! List) return const [];
      return decoded
          .map((item) => item.toString().trim())
          .where((item) => item.isNotEmpty)
          .toList(growable: false);
    } catch (_) {
      return const [];
    }
  }

  Future<void> _writeChannelCredentialIndex(
    String channelName,
    List<String> accounts,
  ) async {
    final unique = <String>[];
    for (final account in accounts) {
      final normalized = account.trim();
      if (normalized.isEmpty || unique.contains(normalized)) continue;
      unique.add(normalized);
    }
    if (unique.isEmpty) {
      await _channelCredentialStore.delete(
        key: _channelCredentialIndexKey(channelName),
      );
      return;
    }
    await _channelCredentialStore.write(
      key: _channelCredentialIndexKey(channelName),
      value: jsonEncode(unique),
    );
  }

  Future<void> _addChannelCredentialIndexEntry(
    String channelName,
    String accountId,
  ) async {
    final accounts = await _readChannelCredentialIndex(channelName);
    if (accounts.contains(accountId)) return;
    await _writeChannelCredentialIndex(channelName, [...accounts, accountId]);
  }

  Future<void> _removeChannelCredentialIndexEntry(
    String channelName,
    String accountId,
  ) async {
    final accounts = await _readChannelCredentialIndex(channelName);
    await _writeChannelCredentialIndex(
      channelName,
      accounts.where((account) => account != accountId).toList(),
    );
  }

  String _channelCredentialAccountId(DemoChannelCredentials credentials) {
    final normalized = _normalizeDemoChannelName(credentials.channelName);
    if (normalized == sdk.QqBotChannelProvider.channelName) {
      final appId = DemoQqChannelCredentials.fromChannelCredentials(
        credentials,
      ).appId.trim();
      return appId.isEmpty ? 'unconfigured' : appId;
    }
    if (normalized == sdk.BluetoothHeadsetChannelProvider.channelName) {
      final accountId =
          DemoBluetoothHeadsetChannelCredentials.fromChannelCredentials(
            credentials,
          ).accountId.trim();
      return accountId.isEmpty
          ? sdk.BluetoothHeadsetChannelCredentials.defaultAccountId
          : accountId;
    }
    return 'default';
  }

  String _demoQqChannelAccountId(sdk.QqBotChannelCredentials credentials) {
    final accountId = credentials.appId.trim();
    return accountId.isEmpty ? 'unconfigured' : accountId;
  }

  String _demoHeadsetChannelAccountId(
    sdk.BluetoothHeadsetChannelCredentials credentials,
  ) {
    final accountId = credentials.accountId.trim();
    if (accountId.isNotEmpty) return accountId;
    final deviceId = credentials.deviceId.trim();
    return deviceId.isEmpty
        ? sdk.BluetoothHeadsetChannelCredentials.defaultAccountId
        : deviceId;
  }

  bool _sameDemoQqProviderConfig(
    sdk.QqBotChannelCredentials left,
    sdk.QqBotChannelCredentials right,
  ) {
    return left.appId == right.appId &&
        left.appSecret == right.appSecret &&
        left.sandbox == right.sandbox &&
        left.intents == right.intents &&
        left.agentId == right.agentId;
  }

  bool _sameDemoHeadsetProviderConfig(
    sdk.BluetoothHeadsetChannelCredentials left,
    sdk.BluetoothHeadsetChannelCredentials right,
  ) {
    return left.deviceId == right.deviceId &&
        left.deviceName == right.deviceName &&
        left.accountId == right.accountId &&
        left.agentId == right.agentId &&
        left.ttsEnabled == right.ttsEnabled;
  }

  String _legacyChannelCredentialsKey(String channelName) {
    return 'napaxi_demo.channel_credentials.$channelName.v1';
  }

  String _channelCredentialIndexKey(String channelName) {
    return 'napaxi_demo.channel_credentials.$channelName.index.v1';
  }

  String _channelCredentialsKey(String channelName, String accountId) {
    return 'napaxi_demo.channel_credentials.$channelName.'
        '${_channelCredentialStoreKeyComponent(accountId)}.v1';
  }

  String _channelCredentialStoreKeyComponent(String value) {
    final buffer = StringBuffer();
    for (final codeUnit in value.trim().toLowerCase().codeUnits) {
      final isDigit = codeUnit >= 48 && codeUnit <= 57;
      final isLowerAscii = codeUnit >= 97 && codeUnit <= 122;
      buffer.write(
        isDigit || isLowerAscii ? String.fromCharCode(codeUnit) : '-',
      );
    }
    final normalized = buffer.toString().replaceAll(RegExp('-+'), '-');
    return normalized.isEmpty ? 'default' : normalized;
  }

  @override
  Future<DemoAgent> installAgentProvider(
    sdk.AgentProviderDescriptor provider,
  ) async {
    if (!Platform.isAndroid && provider.platform != 'ios') {
      throw UnsupportedError('Provider Agent install is not supported');
    }
    final package = await _agentProviderInstallApi().requestInstall(provider);
    await _reloadProviderAgent(package.agentId);
    final definition = await _requireEngine().getAgentDefinition(
      package.agentId,
    );
    if (definition != null) return DemoAgent.fromDefinition(definition);
    return DemoAgent(
      id: package.agentId,
      name: package.displayName.trim().isEmpty
          ? package.agentId
          : package.displayName,
      icon: Icons.sensors_rounded,
      systemPrompt: package.systemPrompt,
    );
  }

  sdk.AgentProviderInstallApi _agentProviderInstallApi() {
    final engine = _requireEngine();
    return sdk.AgentProviderInstallApi(
      registerPackage: engine.agentApp.registerPackage,
    );
  }

  @override
  Future<List<DemoAgent>> listAgents() async {
    final engine = _engine;
    final runtimeProfile = _activeRuntimeProfile;
    if (!runtimeProfile.supportsAgents) {
      if (engine != null) await _ensureRuntimeAgent(engine);
      return [runtimeProfile.primaryAgent];
    }
    if (engine == null) return const [_defaultDemoAgent];

    final definitions = await engine.listAgentDefinitions();
    final agents = <DemoAgent>[_defaultDemoAgent];
    final seen = <String>{sdk.NapaxiEngine.defaultAgentId};
    for (final definition in definitions) {
      if (definition.id == sdk.NapaxiEngine.defaultAgentId ||
          definition.id.trim().isEmpty ||
          !seen.add(definition.id)) {
        continue;
      }
      agents.add(DemoAgent.fromDefinition(definition));
    }
    return _visibleAgentsForRuntimeProfile(runtimeProfile, agents);
  }

  @override
  Future<DemoAgent> createAgent({
    required String name,
    String systemPrompt = '',
    String? modelProfileId,
  }) async {
    final trimmedName = name.trim();
    if (trimmedName.isEmpty) {
      throw ArgumentError.value(name, 'name', 'Agent name is required');
    }
    final engine = _requireEngine();
    final definition = await engine.createAgentDefinition(
      sdk.AgentDefinition(
        id: _agentIdFromName(trimmedName),
        name: trimmedName,
        systemPrompt: systemPrompt.trim(),
        modelProfileId: modelProfileId?.trim(),
      ),
    );
    await engine.createAgentFromDefinition(definition.id);
    return DemoAgent.fromDefinition(definition);
  }

  @override
  Future<DemoAgent> updateAgent({
    required String agentId,
    required String name,
    String systemPrompt = '',
    String? modelProfileId,
  }) async {
    if (agentId == sdk.NapaxiEngine.defaultAgentId) {
      return _defaultDemoAgent;
    }
    final engine = _requireEngine();
    final existing = await engine.getAgentDefinition(agentId);
    if (existing == null) {
      throw StateError('Agent not found: $agentId');
    }
    final definition = sdk.AgentDefinition(
      id: existing.id,
      name: name.trim().isEmpty ? existing.name : name.trim(),
      description: existing.description,
      systemPrompt: systemPrompt.trim(),
      provider: existing.provider,
      model: existing.model,
      modelProfileId: modelProfileId?.trim(),
      toolFilter: existing.toolFilter,
      toolList: existing.toolList,
      icon: existing.icon,
    );
    final updated = await engine.updateAgentDefinition(definition);
    if (!updated) throw StateError('Agent was not updated: $agentId');
    engine.deleteAgent(agentId);
    return DemoAgent.fromDefinition(definition);
  }

  @override
  Future<bool> deleteAgent(String agentId) async {
    if (agentId == sdk.NapaxiEngine.defaultAgentId) return false;
    final engine = _requireEngine();
    final deletedDefinition = await engine.deleteAgentDefinition(agentId);
    final deletedRuntime = engine.deleteAgent(agentId);
    return deletedDefinition || deletedRuntime;
  }

  @override
  Future<sdk.SessionKey> createSession({
    required String threadId,
    required String agentId,
  }) async {
    await _ensureAgent(agentId);
    return _requireEngine().createSession(
      channelType: 'app',
      accountId: _activeAccountId,
      threadId: threadId,
      agentId: agentId,
    );
  }

  @override
  Stream<sdk.ChatEvent> sendToSession(
    sdk.SessionKey session,
    String message, {
    required String agentId,
    List<sdk.McAttachment>? attachments,
    int maxIterations = 0,
    void Function(String nativeThreadId)? onNativeThreadId,
  }) {
    if (agentId == 'engine.cc') {
      return _sendToCliBridge('cc', session.threadId, message);
    }
    if (agentId == 'engine.codex') {
      return _sendToCliBridge(
        'codex',
        session.threadId,
        message,
        onNativeThreadId: onNativeThreadId,
      );
    }
    _automationToolExecutor.setCurrentSession(session, agentId: agentId);
    return _requireEngine().sendToSession(
      session,
      message,
      agentId: agentId,
      attachments: attachments,
      maxIterations: maxIterations,
    );
  }

  Stream<sdk.ChatEvent> _sendToCliBridge(
    String engineId,
    String threadId,
    String message, {
    void Function(String nativeThreadId)? onNativeThreadId,
  }) {
    final controller = StreamController<sdk.ChatEvent>();
    () async {
      try {
        final bridge = _getOrCreateBridge(engineId);
        await for (final event in bridge.send(
          threadId,
          message,
          onNativeThreadId: onNativeThreadId,
        )) {
          if (controller.isClosed) break;
          controller.add(event);
        }
        if (!controller.isClosed) await controller.close();
      } catch (e) {
        if (!controller.isClosed) {
          controller.add(sdk.ErrorEvent(message: e.toString()));
          await controller.close();
        }
      }
    }();
    return controller.stream;
  }

  _CliEngineBridge _getOrCreateBridge(String engineId) {
    switch (engineId) {
      case 'cc':
        return _ccBridge ??= _CliEngineBridge(spec: _CliEngineSpec.cc);
      case 'codex':
        return _codexBridge ??= _CliEngineBridge(spec: _CliEngineSpec.codex);
      default:
        throw ArgumentError('Unknown CLI engine: $engineId');
    }
  }

  @override
  void resetCliBridge(String engineId) {
    switch (engineId) {
      case 'cc':
        _ccBridge?.resetForNewConversation();
      case 'codex':
        _codexBridge?.resetForNewConversation();
    }
  }

  @override
  Future<void> clearCliNativeId(String engineId) async {
    try {
      await _getOrCreateBridge(engineId).clearNativeIds();
    } catch (_) {}
  }

  /// Backfill codex/CC history from each engine's native session store
  /// (codex thread items / Claude session jsonl), mapped to the core
  /// history-item schema.
  Future<List<sdk.ChatMessage>> _getCliEngineHistory(
    String threadId,
    String agentId,
  ) async {
    final engineId = agentId == 'engine.cc' ? 'cc' : 'codex';
    try {
      final bridge = _getOrCreateBridge(engineId);
      final items = await bridge.readHistory(threadId);
      final messages = items
          .map((m) => sdk.ChatMessage.fromMap(Map<String, dynamic>.from(m)))
          .toList(growable: false);
      debugPrint(
        '[${agentId == 'engine.cc' ? _ccHistoryLogTag : _codexHistoryLogTag}] sdkHistory thread=$threadId agent=$agentId raw=${items.length} decoded=${messages.length} roles=${_historyMessageRoleSummary(messages)}',
      );
      return messages;
    } catch (_) {
      return const [];
    }
  }

  String _historyMessageRoleSummary(List<sdk.ChatMessage> messages) {
    final counts = <String, int>{};
    for (final message in messages) {
      counts[message.role] = (counts[message.role] ?? 0) + 1;
    }
    if (counts.isEmpty) return 'none';
    return counts.entries
        .map((entry) => '${entry.key}:${entry.value}')
        .join(',');
  }

  @override
  Future<bool> cancelSession(
    sdk.SessionKey session, {
    required String agentId,
  }) {
    if (agentId == 'engine.cc') {
      _ccBridge?.sendInterrupt();
      return Future.value(true);
    }
    if (agentId == 'engine.codex') {
      _codexBridge?.sendInterrupt();
      return Future.value(true);
    }
    return _requireEngine().cancelSession(session, agentId: agentId);
  }

  @override
  Future<bool> deleteSession(
    sdk.SessionKey session, {
    required String agentId,
  }) {
    return _requireEngine().deleteSession(session, agentId: agentId);
  }

  @override
  Future<bool> injectMessage(
    sdk.SessionKey session,
    String message, {
    required String agentId,
    List<sdk.McAttachment>? attachments,
  }) {
    return _requireEngine().injectMessage(
      session,
      message,
      agentId: agentId,
      attachments: attachments,
    );
  }

  @override
  Future<bool> retractInjectedMessage(sdk.SessionKey session, String message) {
    return _requireEngine().retractInjectedMessage(session, message);
  }

  @override
  Future<bool> answerHumanRequest(String requestId, String response) {
    final ccBridge = _ccBridge;
    if (ccBridge != null) {
      return ccBridge.answerHumanRequest(requestId, response);
    }
    final codexBridge = _codexBridge;
    if (codexBridge != null) {
      return codexBridge.answerHumanRequest(requestId, response);
    }
    return _requireEngine().answerHumanRequest(requestId, response);
  }

  @override
  Future<List<Map<String, dynamic>>> listPendingEvolution() async {
    return _requireEngine().listPendingEvolution();
  }

  @override
  Future<Map<String, dynamic>> applyPendingEvolution(String pendingId) {
    return _requireEngine().applyPendingEvolution(pendingId);
  }

  @override
  Future<Map<String, dynamic>> rejectPendingEvolution(String pendingId) {
    return _requireEngine().rejectPendingEvolution(pendingId);
  }

  @override
  Future<List<sdk.EvolutionRun>> listEvolutionRuns({
    List<String>? runIds,
  }) async {
    return _requireEngine().listEvolutionRuns(runIds: runIds);
  }

  @override
  bool get supportsBackgroundExecution => Platform.isAndroid;

  @override
  Future<bool> requestBackgroundPermission() {
    return sdk.NapaxiBackgroundPermissions.requestNotificationPermission();
  }

  @override
  Stream<sdk.BackgroundActionEvent> get onBackgroundAction {
    final engine = _engine;
    return engine?.onBackgroundAction ?? const Stream.empty();
  }

  @override
  Stream<DemoChannelBridgeEvent> get onChannelBridgeEvent {
    return _channelBridgeEvents.stream;
  }

  @override
  Future<void> stopBackgroundService() async {
    for (final entry in _demoQqChannelProviders.entries) {
      if ((entry.value.status().connected) &&
          _demoQqChannelBridges[entry.key]?.status.running == true) {
        return;
      }
    }
    for (final entry in _demoHeadsetChannelProviders.entries) {
      if ((entry.value.status().connected) &&
          _demoHeadsetChannelBridges[entry.key]?.status.running == true) {
        return;
      }
    }
    await _engine?.stopBackgroundService();
  }

  @override
  Future<List<sdk.SessionInfo>> listSessions({required String agentId}) async {
    if (agentId == 'engine.codex') {
      // Codex: pull threads directly via thread/list RPC. The codex thread id
      // doubles as the UI session id — no mapping layer.
      final bridge = _getOrCreateBridge('codex');
      final threads = await bridge.listThreads();
      debugPrint(
        '[$_codexHistoryLogTag] listSessions codex threads=${threads.length}',
      );
      final sessions = threads
          .map((thread) {
            final id = thread['id'] as String;
            final createdMs = thread['createdAt'] as int;
            final updatedMs = thread['updatedAt'] as int;
            final title = (thread['name'] as String).trim().isNotEmpty
                ? thread['name'] as String
                : (thread['preview'] as String);
            return sdk.SessionInfo(
              key: sdk.SessionKey(
                channelType: 'cli',
                accountId: agentId,
                threadId: id,
              ),
              title: title,
              preview: thread['preview'] as String,
              createdAt: DateTime.fromMillisecondsSinceEpoch(
                createdMs,
              ).toIso8601String(),
              updatedAt: DateTime.fromMillisecondsSinceEpoch(
                updatedMs,
              ).toIso8601String(),
            );
          })
          .toList(growable: false);
      debugPrint(
        '[$_codexHistoryLogTag] listSessions codex mapped=${sessions.length} first=${sessions.isEmpty ? 'none' : sessions.first.key.threadId}',
      );
      return sessions;
    }
    if (agentId == 'engine.cc') {
      final sessions = await _getOrCreateBridge(
        'cc',
      ).listCcSessions(agentId: agentId);
      debugPrint(
        '[$_ccHistoryLogTag] listSessions cc mapped=${sessions.length} first=${sessions.isEmpty ? 'none' : sessions.first.key.threadId}',
      );
      return sessions;
    }
    await _ensureAgent(agentId);
    return (await _ensureManagementEngine()).listSessions(
      accountId: _activeAccountId,
      agentId: agentId,
    );
  }

  @override
  Future<List<sdk.ChatMessage>> getHistory(
    String threadId, {
    required String agentId,
  }) async {
    if (agentId == 'engine.cc' || agentId == 'engine.codex') {
      return _getCliEngineHistory(threadId, agentId);
    }
    return (await _ensureManagementEngine()).getHistory(
      threadId,
      agentId: agentId,
    );
  }

  @override
  Future<sdk.HistoryPage> getHistoryPage(
    String threadId, {
    required String agentId,
    String? before,
    int limit = 80,
  }) async {
    if (agentId == 'engine.cc' || agentId == 'engine.codex') {
      final messages = await _getCliEngineHistory(threadId, agentId);
      return sdk.HistoryPage(messages: messages, hasMore: false);
    }
    return (await _ensureManagementEngine()).getHistoryPage(
      threadId,
      agentId: agentId,
      before: before,
      limit: limit,
    );
  }

  @override
  Future<sdk.ContextStatus> contextStatus(
    String threadId, {
    required String agentId,
  }) async {
    return (await _ensureManagementEngine()).contextStatus(
      threadId,
      agentId: agentId,
    );
  }

  @override
  Future<sdk.ContextStatus> compactContext(
    sdk.SessionKey session, {
    required String agentId,
    String? focus,
  }) async {
    return (await _ensureManagementEngine()).compactContext(
      session,
      agentId: agentId,
      focus: focus,
    );
  }

  @override
  Future<List<sdk.WorkspaceEntry>> listMemoryFiles(
    String directory, {
    required String agentId,
  }) async {
    final engine = _requireEngine();
    await _ensureAgent(agentId);
    final accountId = _activeAccountId;
    final seedKey = '$accountId::$agentId';
    if (!_memorySeededAgents.contains(seedKey) && directory.trim().isEmpty) {
      _memorySeededAgents.add(seedKey);
      await engine.reseedWorkspace(accountId: accountId, agentId: agentId);
    }
    return engine.listWorkspaceFiles(
      directory,
      accountId: accountId,
      agentId: agentId,
    );
  }

  @override
  Future<sdk.WorkspaceFile?> readMemoryFile(
    String path, {
    required String agentId,
  }) {
    return _requireEngine().readWorkspaceFile(
      path,
      accountId: _activeAccountId,
      agentId: agentId,
    );
  }

  @override
  Future<List<sdk.JournalDay>> listJournalDays({
    required String agentId,
  }) async {
    final engine = _requireEngine();
    await _ensureAgent(agentId);
    return engine.listJournalDays(
      accountId: _activeAccountId,
      agentId: agentId,
    );
  }

  @override
  Future<List<sdk.JournalTurnRecord>> readJournalDay(
    String date, {
    required String agentId,
  }) async {
    final engine = _requireEngine();
    await _ensureAgent(agentId);
    return engine.readJournalDay(
      date,
      accountId: _activeAccountId,
      agentId: agentId,
    );
  }

  @override
  Future<List<sdk.MemoryRecallSession>> recallSessions(
    String query, {
    required String agentId,
  }) async {
    final engine = _requireEngine();
    await _ensureAgent(agentId);
    return engine.recallSessions(
      query,
      accountId: _activeAccountId,
      agentId: agentId,
    );
  }

  @override
  Future<sdk.RecallIndexStats> rebuildRecallIndex({
    required String agentId,
  }) async {
    final engine = _requireEngine();
    await _ensureAgent(agentId);
    return engine.rebuildRecallIndex(
      accountId: _activeAccountId,
      agentId: agentId,
    );
  }

  @override
  Future<sdk.RecallIndexStats> recallIndexStats({
    required String agentId,
  }) async {
    final engine = _requireEngine();
    await _ensureAgent(agentId);
    return engine.recallIndexStats(
      accountId: _activeAccountId,
      agentId: agentId,
    );
  }

  @override
  Future<bool> deleteMemoryFile(String path, {required String agentId}) {
    return _requireEngine().deleteWorkspaceFile(
      path,
      accountId: _activeAccountId,
      agentId: agentId,
    );
  }

  @override
  Future<List<sdk.WorkspaceFileInfo>> listSandboxWorkspaceFiles({
    required String agentId,
    String? subdir,
    bool recursive = true,
  }) async {
    if (!sdk.NapaxiFileBridge.isInitialized) {
      throw StateError('napaxi file bridge has not been initialized');
    }
    final cliWorkspace = await _cliWorkspaceFiles(
      agentId: agentId,
      subdir: subdir,
      recursive: recursive,
    );
    if (cliWorkspace != null) return cliWorkspace;
    return sdk.NapaxiFileBridge.instance.listFilesScoped(
      accountId: _activeAccountId,
      agentId: agentId,
      subdir: subdir,
      recursive: recursive,
    );
  }

  @override
  Future<void> deleteSandboxWorkspaceFile(
    String sandboxPath, {
    required String agentId,
  }) async {
    if (!sdk.NapaxiFileBridge.isInitialized) {
      throw StateError('napaxi file bridge has not been initialized');
    }
    final cliDeletePath = await _cliSandboxDeletePath(
      agentId: agentId,
      sandboxPath: sandboxPath,
    );
    if (cliDeletePath != null) {
      return sdk.NapaxiFileBridge.instance.deleteFile(cliDeletePath);
    }
    return sdk.NapaxiFileBridge.instance.deleteFileScoped(
      sandboxPath,
      accountId: _activeAccountId,
      agentId: agentId,
    );
  }

  Future<List<sdk.WorkspaceFileInfo>?> _cliWorkspaceFiles({
    required String agentId,
    String? subdir,
    required bool recursive,
  }) async {
    final sandboxRoot = _cliWorkspaceRoot(agentId);
    final hostWorkspaceRoot = await _cliWorkspaceHostPath();
    if (sandboxRoot == null || hostWorkspaceRoot == null) return null;
    final rootDir = Directory(
      '$hostWorkspaceRoot/${_cliWorkspaceFolder(agentId)}',
    );
    if (!rootDir.existsSync()) return const [];

    final normalizedSubdir = _normalizeCliWorkspaceSubdir(subdir);
    final targetDir = normalizedSubdir.isEmpty
        ? rootDir
        : Directory('${rootDir.path}/$normalizedSubdir');
    if (!targetDir.existsSync()) return const [];

    final entries = recursive
        ? targetDir.listSync(recursive: true, followLinks: false)
        : targetDir.listSync(followLinks: false);
    final files = <sdk.WorkspaceFileInfo>[];
    for (final entry in entries) {
      final stat = entry.statSync();
      final relativePath = _relativeCliPath(rootDir.path, entry.path);
      if (relativePath == null || relativePath.isEmpty) continue;
      final sandboxPath = '/workspace/$relativePath';
      files.add(
        sdk.WorkspaceFileInfo(
          name: entry.uri.pathSegments.isEmpty
              ? relativePath.split('/').last
              : entry.uri.pathSegments.last,
          sandboxPath: sandboxPath,
          realPath: entry.path,
          mimeType: entry is Directory
              ? 'inode/directory'
              : _mimeTypeForPath(entry.path),
          isDirectory: entry is Directory,
          sizeBytes: entry is File ? stat.size : 0,
          modified: stat.modified,
        ),
      );
    }
    return files;
  }

  Future<String?> _cliSandboxDeletePath({
    required String agentId,
    required String sandboxPath,
  }) async {
    final root = _cliWorkspaceRoot(agentId);
    final hostWorkspaceRoot = await _cliWorkspaceHostPath();
    if (root == null) return null;
    if (hostWorkspaceRoot == null) return null;
    final hostRoot = '$hostWorkspaceRoot/${_cliWorkspaceFolder(agentId)}';
    final trimmed = sandboxPath.trim();
    if (trimmed == '/workspace') return hostRoot;
    if (trimmed.startsWith('/workspace/')) {
      final suffix = trimmed.substring('/workspace/'.length);
      return '$hostRoot/$suffix';
    }
    if (trimmed == root || trimmed.startsWith('$root/')) {
      final suffix = trimmed == root ? '' : trimmed.substring(root.length + 1);
      return suffix.isEmpty ? hostRoot : '$hostRoot/$suffix';
    }
    if (trimmed == hostRoot || trimmed.startsWith('$hostRoot/')) return trimmed;
    final normalized = _normalizeCliWorkspaceSubdir(trimmed);
    if (normalized.isEmpty) return hostRoot;
    return '$hostRoot/$normalized';
  }

  String? _cliWorkspaceRoot(String agentId) {
    return switch (agentId) {
      'engine.codex' => _CliEngineSpec.codex.workspacePath,
      'engine.cc' => _CliEngineSpec.cc.workspacePath,
      _ => null,
    };
  }

  String? _cliWorkspaceFolder(String agentId) {
    return switch (agentId) {
      'engine.codex' => _CliEngineSpec.codex.id,
      'engine.cc' => _CliEngineSpec.cc.id,
      _ => null,
    };
  }

  Future<String?> _cliWorkspaceHostPath() {
    final inFlight = _cliWorkspaceHostPathFuture;
    if (inFlight != null) return inFlight;
    final future = _resolvedCliWorkspaceHostPath();
    _cliWorkspaceHostPathFuture = future;
    return future;
  }

  String _normalizeCliWorkspaceSubdir(String? subdir) {
    if (subdir == null) return '';
    return subdir
        .trim()
        .replaceAll('\\', '/')
        .split('/')
        .where((segment) => segment.trim().isNotEmpty)
        .join('/');
  }

  String _mimeTypeForPath(String path) {
    final lower = path.toLowerCase();
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) {
      return 'image/jpeg';
    }
    if (lower.endsWith('.gif')) return 'image/gif';
    if (lower.endsWith('.webp')) return 'image/webp';
    if (lower.endsWith('.svg')) return 'image/svg+xml';
    if (lower.endsWith('.html') || lower.endsWith('.htm')) return 'text/html';
    if (lower.endsWith('.json')) return 'application/json';
    if (lower.endsWith('.md')) return 'text/markdown';
    if (lower.endsWith('.txt') || lower.endsWith('.log')) return 'text/plain';
    return 'application/octet-stream';
  }

  String? _relativeCliPath(String rootPath, String entryPath) {
    final rootUri = Directory(rootPath).uri;
    final entryUri = FileSystemEntity.isDirectorySync(entryPath)
        ? Directory(entryPath).uri
        : File(entryPath).uri;
    final relative = rootUri.resolveUri(entryUri).pathSegments;
    if (relative.isEmpty) return null;
    final normalizedRoot = rootPath.endsWith('/') ? rootPath : '$rootPath/';
    final normalizedEntry = entryPath.replaceAll('\\', '/');
    if (!normalizedEntry.startsWith(normalizedRoot.replaceAll('\\', '/'))) {
      return null;
    }
    final suffix = normalizedEntry.substring(
      normalizedRoot.replaceAll('\\', '/').length,
    );
    return suffix.split('/').where((segment) => segment.isNotEmpty).join('/');
  }

  @override
  Future<List<DemoRepositoryInfo>> listGitRepositories() {
    return _automationToolExecutor.listGitRepositories();
  }

  @override
  Future<DemoGitRepositoryStatus> gitRepositoryStatus(String directory) {
    return _automationToolExecutor.gitRepositoryStatus(directory);
  }

  @override
  Future<DemoGitChangeSet> gitChanges(String directory) {
    return _automationToolExecutor.gitChanges(directory);
  }

  @override
  Future<DemoGitOperationResult> stageGitPaths(
    String directory,
    List<String> paths,
  ) {
    return _automationToolExecutor.stageGitPaths(directory, paths);
  }

  @override
  Future<DemoGitOperationResult> unstageGitPaths(
    String directory,
    List<String> paths,
  ) {
    return _automationToolExecutor.unstageGitPaths(directory, paths);
  }

  @override
  Future<DemoGitOperationResult> discardGitPaths(
    String directory,
    List<String> paths,
  ) {
    return _automationToolExecutor.discardGitPaths(directory, paths);
  }

  @override
  Future<DemoGitOperationResult> commitGit(String directory, String message) {
    return _automationToolExecutor.commitGit(directory, message);
  }

  @override
  Future<DemoGitFileDiff> gitFileDiff(
    String directory,
    String path, {
    bool cached = false,
  }) {
    return _automationToolExecutor.gitFileDiff(directory, path, cached: cached);
  }

  @override
  Future<List<DemoGitBranchInfo>> listGitBranches(String directory) {
    return _automationToolExecutor.listGitBranches(directory);
  }

  @override
  Future<DemoGitOperationResult> switchGitBranch(
    String directory,
    String branch, {
    bool remote = false,
    bool allowDirty = false,
  }) {
    return _automationToolExecutor.switchGitBranch(
      directory,
      branch,
      remote: remote,
      allowDirty: allowDirty,
    );
  }

  @override
  Future<List<DemoGitCommitInfo>> listGitCommitHistory(String directory) {
    return _automationToolExecutor.listGitCommitHistory(directory);
  }

  @override
  Future<DemoGitCommitDiff> gitCommitDiff(String directory, String hash) {
    return _automationToolExecutor.gitCommitDiff(directory, hash);
  }

  @override
  Future<List<DemoGitRemoteInfo>> listGitRemotes(String directory) {
    return _automationToolExecutor.listGitRemotes(directory);
  }

  @override
  Future<DemoGitOperationResult> setGitRemote(
    String directory, {
    required String name,
    required String url,
  }) {
    return _automationToolExecutor.setGitRemote(
      directory,
      name: name,
      url: url,
    );
  }

  @override
  Future<DemoGitOperationResult> removeGitRemote(
    String directory, {
    required String name,
  }) {
    return _automationToolExecutor.removeGitRemote(directory, name: name);
  }

  @override
  Future<DemoGitOperationResult> fetchGitRemote(
    String directory, {
    String? remote,
  }) {
    return _automationToolExecutor.fetchGitRemote(directory, remote: remote);
  }

  @override
  Future<DemoGitOperationResult> pushGitRemote(
    String directory, {
    String? remote,
  }) {
    return _automationToolExecutor.pushGitRemote(directory, remote: remote);
  }

  @override
  Future<DemoGitOperationResult> pullGitRemote(
    String directory, {
    String? remote,
  }) {
    return _automationToolExecutor.pullGitRemote(directory, remote: remote);
  }

  @override
  Future<List<DemoRepositoryFileItem>> listGitRepositoryChildren(
    String directory, {
    String subdir = '',
    String query = '',
    int limit = 200,
  }) {
    return _automationToolExecutor.listGitRepositoryChildren(
      directory,
      subdir: subdir,
      query: query,
      limit: limit,
    );
  }

  @override
  List<sdk.ResolvedFile> detectProducedFiles(
    String text, {
    required String agentId,
  }) {
    if (!sdk.NapaxiFileBridge.isInitialized) return const [];
    return sdk.NapaxiFileBridge.instance.detectFileReferencesScoped(
      text,
      accountId: _activeAccountId,
      agentId: agentId,
    );
  }

  @override
  Future<List<sdk.NapaxiScenarioPack>> listScenarioPacks() async {
    return (await _ensureManagementEngine()).capabilities.listScenarioPacks();
  }

  @override
  Future<List<sdk.NapaxiScenarioStatus>> listScenarioStatuses() async {
    final engine = await _ensureManagementEngine();
    return engine.capabilities.listScenarioStatuses(
      profile: await _demoCapabilityProfile(),
      selection: _activeCapabilitySelection,
    );
  }

  @override
  Future<sdk.NapaxiScenarioResolution?> resolveScenario(
    String scenarioId,
  ) async {
    final engine = await _ensureManagementEngine();
    return engine.capabilities.resolveScenario(
      scenarioId,
      profile: await _demoCapabilityProfile(),
      selection: _activeCapabilitySelection,
    );
  }

  @override
  Future<sdk.NapaxiScenarioPackInstallResult?> installScenarioPack(
    sdk.NapaxiScenarioPack pack,
  ) async {
    return (await _ensureManagementEngine()).capabilities.installScenarioPack(
      pack,
    );
  }

  @override
  Future<sdk.NapaxiScenarioPackRemovalResult?> removeScenarioPack(
    String scenarioId,
  ) async {
    return (await _ensureManagementEngine()).capabilities.removeScenarioPack(
      scenarioId,
    );
  }

  @override
  Future<List<sdk.SkillInfo>> listSkills({required String agentId}) async {
    await _ensureAgent(agentId);
    return _requireEngine().listSkills(agentId: agentId);
  }

  @override
  Future<sdk.SkillInfo?> getSkill(
    String skillName, {
    required String agentId,
  }) async {
    await _ensureAgent(agentId);
    return _requireEngine().getSkill(skillName, agentId: agentId);
  }

  @override
  Future<sdk.SkillStatusReport> listSkillStatus({
    required String agentId,
  }) async {
    await _ensureAgent(agentId);
    return _requireEngine().listSkillStatus(agentId: agentId);
  }

  @override
  Future<sdk.SkillSourceReport> listSkillSources({
    required String agentId,
  }) async {
    await _ensureAgent(agentId);
    return _requireEngine().listSkillSources(agentId: agentId);
  }

  @override
  Future<sdk.SkillSnapshotList> listSkillSnapshots({
    required String agentId,
  }) async {
    await _ensureAgent(agentId);
    return _requireEngine().listSkillSnapshots(agentId: agentId, limit: 5);
  }

  @override
  Future<sdk.SkillSecretRequirementReport> listSkillSecretRequirements({
    required String agentId,
    String? skillName,
  }) async {
    await _ensureAgent(agentId);
    return _requireEngine().listSkillSecretRequirements(
      agentId: agentId,
      skillName: skillName,
    );
  }

  @override
  Future<sdk.SkillRemediationRunList> listSkillRemediationRuns({
    required String agentId,
    String? skillName,
  }) async {
    await _ensureAgent(agentId);
    return _requireEngine().listSkillRemediationRuns(
      agentId: agentId,
      skillName: skillName,
      limit: 20,
    );
  }

  @override
  Future<sdk.SkillStatusReport> checkSkills({required String agentId}) async {
    await _ensureAgent(agentId);
    return _requireEngine().checkSkills(agentId: agentId);
  }

  @override
  Future<sdk.SkillCommandReport> listSkillCommands({
    required String agentId,
  }) async {
    await _ensureAgent(agentId);
    return _requireEngine().listSkillCommands(agentId: agentId);
  }

  @override
  Future<sdk.SkillCommandResolution> resolveSkillCommand(
    String text, {
    required String agentId,
  }) async {
    await _ensureAgent(agentId);
    return _requireEngine().resolveSkillCommand(text, agentId: agentId);
  }

  @override
  Future<sdk.SkillCommandRun> runSkillCommand(
    String commandName, {
    required String agentId,
    String? args,
    sdk.SessionKey? sessionKey,
  }) async {
    await _ensureAgent(agentId);
    return _requireEngine().runSkillCommand(
      commandName,
      agentId: agentId,
      args: args,
      sessionKey: sessionKey,
    );
  }

  @override
  Future<String> setSkillEnabled(
    String skillName, {
    required String agentId,
    required bool enabled,
  }) async {
    await _ensureAgent(agentId);
    return _requireEngine().setSkillEnabled(
      skillName,
      agentId: agentId,
      enabled: enabled,
    );
  }

  @override
  Future<String> updateSkillConfig(
    String skillKey,
    Map<String, dynamic> patch, {
    required String agentId,
  }) async {
    await _ensureAgent(agentId);
    return _requireEngine().updateSkillConfig(
      skillKey,
      patch,
      agentId: agentId,
    );
  }

  @override
  Future<String> recordSkillRequirementResolution(
    String skillName,
    String actionId,
    Map<String, dynamic> result, {
    required String agentId,
  }) async {
    await _ensureAgent(agentId);
    return _requireEngine().recordSkillRequirementResolution(
      skillName,
      actionId,
      result,
      agentId: agentId,
    );
  }

  @override
  Future<sdk.SkillRemediationRun> requestSkillRemediation(
    String skillName,
    String actionId, {
    required String agentId,
  }) async {
    await _ensureAgent(agentId);
    return _requireEngine().requestSkillRemediation(
      skillName,
      actionId,
      agentId: agentId,
    );
  }

  @override
  Future<List<sdk.SkillUsageRecord>> listSkillUsage({
    required String agentId,
  }) async {
    await _ensureAgent(agentId);
    return _requireEngine().listSkillUsage(agentId: agentId);
  }

  @override
  Future<List<String>> reloadSkills({required String agentId}) async {
    await _ensureAgent(agentId);
    return _requireEngine().reloadSkills(agentId: agentId);
  }

  @override
  Future<bool> removeSkill(String skillName, {required String agentId}) async {
    await _ensureAgent(agentId);
    return _requireEngine().removeSkill(skillName, agentId: agentId);
  }

  @override
  Future<String> pinSkill(
    String skillName, {
    required String agentId,
    required bool pinned,
  }) async {
    await _ensureAgent(agentId);
    return _requireEngine().pinSkill(
      skillName,
      agentId: agentId,
      pinned: pinned,
    );
  }

  @override
  Future<String> archiveSkill(
    String skillName, {
    required String agentId,
  }) async {
    await _ensureAgent(agentId);
    return _requireEngine().archiveSkill(skillName, agentId: agentId);
  }

  @override
  Future<String> restoreSkill(
    String skillName, {
    required String agentId,
  }) async {
    await _ensureAgent(agentId);
    return _requireEngine().restoreSkill(skillName, agentId: agentId);
  }

  @override
  Future<sdk.CuratorRunSummary> runSkillCurator({
    required String agentId,
    bool dryRun = true,
  }) async {
    await _ensureAgent(agentId);
    return _requireEngine().runSkillCurator(agentId: agentId, dryRun: dryRun);
  }

  @override
  Future<sdk.SkillConsolidationReviewResult> runSkillConsolidationReview({
    required String agentId,
    bool dryRun = true,
  }) async {
    await _ensureAgent(agentId);
    return _requireEngine().runSkillConsolidationReview(
      agentId: agentId,
      dryRun: dryRun,
    );
  }

  @override
  Future<sdk.SkillSupportFileReadResult> readSkillSupportFile(
    String skillName,
    String filePath, {
    required String agentId,
  }) async {
    await _ensureAgent(agentId);
    return _requireEngine().readSkillSupportFile(
      skillName,
      filePath,
      agentId: agentId,
    );
  }

  @override
  Future<sdk.CatalogSearchResult> listCatalogPackages({
    int limit = 50,
    String? cursor,
  }) async {
    final page = await _requireEngine().listCatalogPackages(
      limit: limit,
      cursor: cursor,
    );
    return sdk.CatalogSearchResult(results: page.items, error: page.error);
  }

  @override
  Future<sdk.CatalogSearchResult> searchCatalog(String query) async {
    return sdk.CatalogSearchResult.fromJson(
      await _requireEngine().searchCatalog(query),
    );
  }

  @override
  Future<sdk.SkillInstallResult> installFromCatalog(
    String slug, {
    required String agentId,
  }) async {
    await _ensureAgent(agentId);
    return sdk.SkillInstallResult.fromJson(
      await _requireEngine().installFromCatalog(slug, agentId: agentId),
    );
  }

  @override
  Stream<sdk.A2ALocalTransportEvent> get localA2AEvents async* {
    // Lazily ensure the engine exists before forwarding transport events.
    // Subscribers (e.g. the chat screen's startup A2A subscription) may listen
    // before any LLM profile is configured; mirror the lazy management-engine
    // pattern used by listSessions/getHistory instead of hard-requiring it.
    final engine = await _ensureManagementEngine();
    yield* engine.a2a.localTransportEvents;
  }

  @override
  Future<bool> handleLocalA2ABlobFrame(sdk.A2ALocalTransportEvent event) async {
    return _handleLocalA2ABlobFrame(event);
  }

  void _ensureLocalA2AAutoResponder(sdk.NapaxiEngine engine) {
    if (_localA2AAutoResponder != null) return;
    _localA2AAutoResponder = engine.a2a.localTransportEvents.listen(
      (event) {
        unawaited(_handleLocalA2AAutoResponderEvent(event));
      },
      onError: (Object error) {
        debugPrint('[napaxiToolTrace] local A2A auto responder error=$error');
      },
    );
  }

  Future<void> _stopLocalA2AAutoResponder() async {
    final subscription = _localA2AAutoResponder;
    _localA2AAutoResponder = null;
    _localA2AAutoResponderMessageIds.clear();
    _localA2AAutoResponderTaskIds.clear();
    _localA2AAutoResponderHandledTaskIds.clear();
    await subscription?.cancel();
  }

  @override
  bool claimLocalA2AAutoRunTask(String taskId) {
    final normalized = taskId.trim();
    if (normalized.isEmpty) return false;
    if (_localA2AAutoResponderHandledTaskIds.contains(normalized)) {
      return false;
    }
    return _localA2AAutoResponderTaskIds.add(normalized);
  }

  @override
  void releaseLocalA2AAutoRunTask(String taskId, {bool handled = true}) {
    final normalized = taskId.trim();
    if (normalized.isEmpty) return;
    _localA2AAutoResponderTaskIds.remove(normalized);
    if (!handled) return;
    _localA2AAutoResponderHandledTaskIds.add(normalized);
    if (_localA2AAutoResponderHandledTaskIds.length > 200) {
      _localA2AAutoResponderHandledTaskIds.remove(
        _localA2AAutoResponderHandledTaskIds.first,
      );
    }
  }

  Future<void> _handleLocalA2AAutoResponderEvent(
    sdk.A2ALocalTransportEvent event,
  ) async {
    if (await _handleLocalA2ABlobFrame(event)) return;
    final message = event.message;
    if (message == null || message.kind != 'task_request') return;
    if (!_localA2AAutoResponderMessageIds.add(message.messageId)) return;

    // Give the visible chat page first chance to record, display, and run the
    // task. If no page listener is mounted, this client-level responder keeps
    // Agent-to-Agent delivery working.
    await Future<void>.delayed(const Duration(milliseconds: 450));

    try {
      final delivery = await recordLocalA2AMessage(message);
      if (delivery.status != 'delivered' && delivery.status != 'duplicate') {
        debugPrint(
          '[napaxiToolTrace] local A2A auto responder ignored delivery=${delivery.status} error=${delivery.error}',
        );
        return;
      }
      final taskId = delivery.taskId ?? _a2aTaskIdFromPeerMessage(message);
      if (taskId == null || taskId.isEmpty) return;
      if (!claimLocalA2AAutoRunTask(taskId)) return;
      var handled = false;
      try {
        final task = await getLocalA2ATask(taskId);
        if (!_isAutoRunnableLocalA2ACollaboration(task)) {
          handled = true;
          return;
        }
        if (_isFinishedLocalA2ATask(task)) {
          handled = true;
          return;
        }
        final peer = await _localA2ASavedPeerAdvertisement(message.fromPeerId);
        if (peer == null) {
          debugPrint(
            '[napaxiToolTrace] local A2A auto responder missing saved peer=${message.fromPeerId}',
          );
          return;
        }
        await _runLocalA2AAutoResponseTask(
          taskId: taskId,
          message: message,
          peer: peer,
        );
        handled = true;
      } finally {
        releaseLocalA2AAutoRunTask(taskId, handled: handled);
      }
    } catch (error) {
      debugPrint('[napaxiToolTrace] local A2A auto responder failed=$error');
    }
  }

  Future<bool> _handleLocalA2ABlobFrame(
    sdk.A2ALocalTransportEvent event,
  ) async {
    final frame = _a2aBlobFrameFromEvent(event);
    if (frame == null) return false;
    try {
      final engine = await _ensureManagementEngine();
      final status = await engine.a2a.localTransportStatus();
      final fromPeerId = frame['fromPeerId']?.toString().trim() ?? '';
      final toPeerId = frame['toPeerId']?.toString().trim() ?? '';
      if (fromPeerId.isEmpty ||
          (toPeerId.isNotEmpty && toPeerId != status.peerId)) {
        return true;
      }
      sdk.A2APeer? peer;
      for (final item in engine.a2a.listPeers()) {
        if (item.peerId == fromPeerId) {
          peer = item;
          break;
        }
      }
      final sharedSecret = peer?.sharedSecret.trim() ?? '';
      if (sharedSecret.isEmpty || !_a2aVerifyBlobFrame(frame, sharedSecret)) {
        debugPrint(
          '[napaxiToolTrace] local A2A blob frame rejected peer=$fromPeerId',
        );
        return true;
      }
      final frameType = frame['frameType']?.toString().trim() ?? '';
      if (frameType == 'a2a_blob_manifest') {
        await _recordLocalA2ABlobManifest(frame);
      } else if (frameType == 'a2a_blob_chunk') {
        await _recordLocalA2ABlobChunk(frame);
      } else if (frameType == 'a2a_blob_complete') {
        await _recordLocalA2ABlobComplete(frame);
      }
    } catch (error) {
      debugPrint('[napaxiToolTrace] local A2A blob frame failed=$error');
    }
    return true;
  }

  Map<String, dynamic>? _a2aBlobFrameFromEvent(
    sdk.A2ALocalTransportEvent event,
  ) {
    final payloadFrame = event.message?.payload['a2aBlobFrame'];
    if (payloadFrame is Map) {
      return Map<String, dynamic>.from(payloadFrame);
    }
    final raw = event.messageJson.trim();
    if (raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      final map = Map<String, dynamic>.from(decoded);
      if (map['frameType']?.toString().startsWith('a2a_blob_') == true) {
        return map;
      }
    } catch (_) {}
    return null;
  }

  Future<void> _recordLocalA2ABlobManifest(Map<String, dynamic> frame) async {
    final protocolVersion = frame['protocolVersion']?.toString().trim() ?? '';
    if (protocolVersion != _a2aBlobProtocolVersion) return;
    final manifestId = frame['manifestId']?.toString().trim() ?? '';
    final fromPeerId = frame['fromPeerId']?.toString().trim() ?? '';
    final artifacts = frame['artifacts'];
    if (manifestId.isEmpty || fromPeerId.isEmpty || artifacts is! List) {
      return;
    }
    final entries = <String, _A2ABlobReceiveArtifact>{};
    var totalSize = 0;
    for (final item in artifacts.whereType<Map>()) {
      if (entries.length >= _a2aBlobMaxArtifactsPerManifest) return;
      final map = Map<String, dynamic>.from(item);
      final artifactId =
          map['artifactId']?.toString().trim() ??
          map['artifact_id']?.toString().trim() ??
          '';
      if (artifactId.isEmpty) continue;
      final sizeBytes =
          _a2aIntFromAny(map['sizeBytes'] ?? map['size_bytes']) ?? 0;
      final chunkCount =
          _a2aIntFromAny(map['chunkCount'] ?? map['chunk_count']) ?? 0;
      final chunkSizeBytes =
          _a2aIntFromAny(map['chunkSize'] ?? map['chunk_size']) ??
          _a2aBlobChunkBytes;
      final sha256Hex = map['sha256']?.toString().trim() ?? '';
      final expectedChunkCount = math.max(
        1,
        (sizeBytes / chunkSizeBytes).ceil(),
      );
      if (sizeBytes <= 0 ||
          sizeBytes > _a2aBlobMaxArtifactBytes ||
          chunkSizeBytes <= 0 ||
          chunkSizeBytes > _a2aBlobChunkBytes ||
          chunkCount != expectedChunkCount ||
          sha256Hex.length != 64) {
        return;
      }
      totalSize += sizeBytes;
      if (totalSize > _a2aBlobMaxManifestBytes) return;
      entries[artifactId] = _A2ABlobReceiveArtifact(
        artifactId: artifactId,
        name: map['name']?.toString().trim() ?? artifactId,
        mimeType:
            map['mimeType']?.toString().trim() ??
            map['mime_type']?.toString().trim() ??
            '',
        sizeBytes: sizeBytes,
        sha256Hex: sha256Hex,
        chunkSizeBytes: chunkSizeBytes,
        chunkCount: chunkCount,
      );
    }
    if (entries.isEmpty) return;
    if (_localA2ABlobManifests.containsKey(manifestId)) return;
    final alreadyResolved = entries.keys.every(
      (artifactId) =>
          _localA2AResolvedBlobArtifacts[_a2aBlobKey(manifestId, artifactId)] !=
          null,
    );
    if (alreadyResolved) return;
    _localA2ABlobManifests[manifestId] = _A2ABlobReceiveManifest(
      manifestId: manifestId,
      fromPeerId: fromPeerId,
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      artifacts: entries,
    );
    _pruneLocalA2ABlobState();
  }

  Future<void> _recordLocalA2ABlobChunk(Map<String, dynamic> frame) async {
    final protocolVersion = frame['protocolVersion']?.toString().trim() ?? '';
    if (protocolVersion != _a2aBlobProtocolVersion) return;
    final manifestId = frame['manifestId']?.toString().trim() ?? '';
    final artifactId = frame['artifactId']?.toString().trim() ?? '';
    final index = _a2aIntFromAny(frame['index']);
    final dataBase64 =
        frame['dataBase64']?.toString() ??
        frame['data_base64']?.toString() ??
        '';
    final chunkSha256 =
        frame['chunkSha256']?.toString().trim() ??
        frame['chunk_sha256']?.toString().trim() ??
        '';
    final manifest = _localA2ABlobManifests[manifestId];
    final artifact = manifest?.artifacts[artifactId];
    if (manifest == null ||
        artifact == null ||
        index == null ||
        index < 0 ||
        index >= artifact.chunkCount ||
        dataBase64.isEmpty ||
        dataBase64.length > _a2aBlobMaxChunkBase64Chars) {
      return;
    }
    if (artifact.receivedChunks.contains(index)) return;
    final List<int> bytes;
    try {
      bytes = base64Decode(dataBase64);
    } catch (_) {
      return;
    }
    if (bytes.isEmpty || bytes.length > artifact.chunkSizeBytes) return;
    if (index < artifact.chunkCount - 1 &&
        bytes.length != artifact.chunkSizeBytes) {
      return;
    }
    if (chunkSha256.isNotEmpty && _a2aBytesSha256Hex(bytes) != chunkSha256) {
      debugPrint(
        '[napaxiToolTrace] local A2A blob chunk sha mismatch manifest=$manifestId artifact=$artifactId index=$index',
      );
      return;
    }
    final chunkFile = await _localA2ABlobChunkFile(
      manifestId: manifestId,
      artifactId: artifactId,
      index: index,
    );
    await chunkFile.parent.create(recursive: true);
    await chunkFile.writeAsBytes(bytes, flush: true);
    artifact.receivedChunks.add(index);
    await _tryFinalizeLocalA2ABlobManifest(manifest);
  }

  Future<void> _recordLocalA2ABlobComplete(Map<String, dynamic> frame) async {
    final manifestId = frame['manifestId']?.toString().trim() ?? '';
    final manifest = _localA2ABlobManifests[manifestId];
    if (manifest == null) return;
    manifest.completeReceived = true;
    await _tryFinalizeLocalA2ABlobManifest(manifest);
  }

  Future<File> _localA2ABlobChunkFile({
    required String manifestId,
    required String artifactId,
    required int index,
  }) async {
    final workspace = sdk.NapaxiFileBridge.instance.workspaceDir;
    final safeManifest = _a2aSafeFilename(manifestId, 'manifest');
    final safeArtifact = _a2aSafeFilename(artifactId, 'artifact');
    return File(
      '${workspace.path}/attachments/a2a/.incoming/$safeManifest/$safeArtifact/$index.part',
    );
  }

  Future<void> _tryFinalizeLocalA2ABlobManifest(
    _A2ABlobReceiveManifest manifest,
  ) async {
    if (!manifest.completeReceived) return;
    for (final artifact in manifest.artifacts.values) {
      if (artifact.resolvedArtifact != null || !artifact.hasAllChunks) {
        continue;
      }
      final finalArtifact = await _finalizeLocalA2ABlobArtifact(
        manifest,
        artifact,
      );
      if (finalArtifact == null) continue;
      artifact.resolvedArtifact = finalArtifact;
      final key = _a2aBlobKey(manifest.manifestId, artifact.artifactId);
      _localA2AResolvedBlobArtifacts[key] = finalArtifact;
      await _persistLocalA2AResolvedBlobArtifact(
        manifestId: manifest.manifestId,
        artifactId: artifact.artifactId,
        artifact: finalArtifact,
      );
      _localA2ABlobWaiters.remove(key)?.complete();
      await _deleteLocalA2ABlobChunks(
        manifestId: manifest.manifestId,
        artifactId: artifact.artifactId,
      );
    }
    if (manifest.artifacts.values.every(
      (artifact) => artifact.resolvedArtifact != null,
    )) {
      _localA2ABlobManifests.remove(manifest.manifestId);
    }
  }

  Future<sdk.A2AArtifact?> _finalizeLocalA2ABlobArtifact(
    _A2ABlobReceiveManifest manifest,
    _A2ABlobReceiveArtifact artifact,
  ) async {
    final workspace = sdk.NapaxiFileBridge.instance.workspaceDir;
    final targetDir = Directory('${workspace.path}/attachments/a2a');
    await targetDir.create(recursive: true);
    final ext = _a2aFileExtensionForMime(artifact.mimeType);
    final filename = _a2aSafeFilename(
      artifact.name.isEmpty ? '${artifact.artifactId}$ext' : artifact.name,
      '${artifact.artifactId}$ext',
    );
    final target = await _a2aUniqueFile(targetDir, filename);
    final sink = target.openWrite();
    try {
      for (var i = 0; i < artifact.chunkCount; i++) {
        final chunk = await _localA2ABlobChunkFile(
          manifestId: manifest.manifestId,
          artifactId: artifact.artifactId,
          index: i,
        );
        if (!await chunk.exists()) return null;
        sink.add(await chunk.readAsBytes());
      }
    } finally {
      await sink.close();
    }
    final size = await target.length();
    final sha = await _a2aFileSha256Hex(target);
    if (size != artifact.sizeBytes || sha != artifact.sha256Hex) {
      try {
        await target.delete();
      } catch (_) {}
      debugPrint(
        '[napaxiToolTrace] local A2A blob final sha/size mismatch manifest=${manifest.manifestId} artifact=${artifact.artifactId}',
      );
      return null;
    }
    final sandbox =
        sdk.NapaxiFileBridge.instance.realToSandbox(target.path) ??
        '/workspace/attachments/a2a/${target.uri.pathSegments.last}';
    return sdk.A2AArtifact(
      artifactId: artifact.artifactId,
      mimeType: artifact.mimeType,
      name: artifact.name.isEmpty
          ? target.uri.pathSegments.last
          : artifact.name,
      uri: sandbox,
      metadata: {
        'transport': 'local_blob',
        'manifest_id': manifest.manifestId,
        'blob_id': artifact.artifactId,
        'sha256': sha,
        'size_bytes': size,
        'sandbox_path': sandbox,
      },
    );
  }

  Future<File> _localA2AResolvedBlobIndexFile({
    required String manifestId,
    required String artifactId,
  }) async {
    final workspace = sdk.NapaxiFileBridge.instance.workspaceDir;
    final dir = Directory('${workspace.path}/attachments/a2a/.index');
    await dir.create(recursive: true);
    final safeManifest = _a2aSafeFilename(manifestId, 'manifest');
    final safeArtifact = _a2aSafeFilename(artifactId, 'artifact');
    return File('${dir.path}/$safeManifest--$safeArtifact.json');
  }

  Future<void> _persistLocalA2AResolvedBlobArtifact({
    required String manifestId,
    required String artifactId,
    required sdk.A2AArtifact artifact,
  }) async {
    try {
      final file = await _localA2AResolvedBlobIndexFile(
        manifestId: manifestId,
        artifactId: artifactId,
      );
      await file.writeAsString(jsonEncode(artifact.toJson()));
    } catch (error) {
      debugPrint('[napaxiToolTrace] local A2A blob index persist failed=$error');
    }
  }

  Future<sdk.A2AArtifact?> _loadPersistedLocalA2ABlobArtifact({
    required String manifestId,
    required String artifactId,
  }) async {
    try {
      final file = await _localA2AResolvedBlobIndexFile(
        manifestId: manifestId,
        artifactId: artifactId,
      );
      if (!await file.exists()) return null;
      final artifact = sdk.A2AArtifact.fromJson(
        jsonDecode(await file.readAsString()) as Map<String, dynamic>,
      );
      final uri = artifact.uri?.trim() ?? '';
      if (uri.isEmpty) return null;
      final resolved = await _a2aResolveTransportFile(uri, _requireEngine());
      if (resolved == null) return null;
      return artifact;
    } catch (_) {
      return null;
    }
  }

  Future<List<sdk.A2AArtifact>> _resolveLocalA2ABlobArtifacts(
    List<sdk.A2AArtifact> artifacts, {
    Duration timeout = const Duration(milliseconds: _a2aBlobWaitTimeoutMs),
  }) async {
    if (artifacts.isEmpty) return artifacts;
    final pending = <String, Completer<void>>{};
    for (final artifact in artifacts) {
      final manifestId =
          artifact.metadata['manifest_id']?.toString().trim() ??
          artifact.metadata['manifestId']?.toString().trim() ??
          '';
      if (manifestId.isEmpty) continue;
      final blobId =
          artifact.metadata['blob_id']?.toString().trim() ??
          artifact.metadata['blobId']?.toString().trim() ??
          artifact.artifactId;
      final key = _a2aBlobKey(manifestId, blobId);
      if (_localA2AResolvedBlobArtifacts[key] != null) continue;
      final persisted = await _loadPersistedLocalA2ABlobArtifact(
        manifestId: manifestId,
        artifactId: blobId,
      );
      if (persisted != null) {
        _localA2AResolvedBlobArtifacts[key] = persisted;
        continue;
      }
      pending[key] = _localA2ABlobWaiters.putIfAbsent(
        key,
        () => Completer<void>(),
      );
    }
    if (pending.isNotEmpty) {
      await Future.wait(
        pending.values.map((completer) => completer.future),
      ).timeout(timeout, onTimeout: () => const <void>[]);
    }
    final resolved = <sdk.A2AArtifact>[];
    for (final artifact in artifacts) {
      final manifestId =
          artifact.metadata['manifest_id']?.toString().trim() ??
          artifact.metadata['manifestId']?.toString().trim() ??
          '';
      final blobId =
          artifact.metadata['blob_id']?.toString().trim() ??
          artifact.metadata['blobId']?.toString().trim() ??
          artifact.artifactId;
      if (manifestId.isEmpty) {
        resolved.add(artifact);
        continue;
      }
      final key = _a2aBlobKey(manifestId, blobId);
      final existing = _localA2AResolvedBlobArtifacts[key];
      if (existing != null) {
        resolved.add(existing);
        continue;
      }
      final persisted = await _loadPersistedLocalA2ABlobArtifact(
        manifestId: manifestId,
        artifactId: blobId,
      );
      if (persisted != null) {
        _localA2AResolvedBlobArtifacts[key] = persisted;
        resolved.add(persisted);
        continue;
      }
      resolved.add(artifact);
    }
    return resolved;
  }

  Future<List<Map<String, dynamic>>> _validateResolvedLocalA2AArtifacts(
    List<sdk.A2AArtifact> artifacts,
    sdk.NapaxiEngine engine,
  ) async {
    final issues = <Map<String, dynamic>>[];
    for (final artifact in artifacts) {
      final uri = artifact.uri?.trim() ?? '';
      final metadata = artifact.metadata;
      final manifestId = _a2aStringField(metadata, [
        'manifest_id',
        'manifestId',
      ]);
      final transport = metadata['transport']?.toString().trim() ?? '';
      if (uri.startsWith('a2a-blob://') ||
          (transport == 'local_blob' &&
              manifestId.isNotEmpty &&
              !uri.startsWith('/workspace/'))) {
        issues.add({
          'severity': 'error',
          'code': 'a2a_blob_not_resolved',
          'artifactId': artifact.artifactId,
          'name': artifact.name,
          'uri': uri,
        });
        continue;
      }
      if (!_a2aUriIsLocalOnly(uri)) continue;
      final file = await _a2aResolveTransportFile(
        uri,
        engine,
        metadata: metadata,
      );
      if (file == null) {
        issues.add({
          'severity': 'error',
          'code': 'a2a_artifact_not_available_locally',
          'artifactId': artifact.artifactId,
          'name': artifact.name,
          'uri': uri,
        });
      }
    }
    return issues;
  }

  Future<void> _deleteLocalA2ABlobChunks({
    required String manifestId,
    required String artifactId,
  }) async {
    final workspace = sdk.NapaxiFileBridge.instance.workspaceDir;
    final safeManifest = _a2aSafeFilename(manifestId, 'manifest');
    final safeArtifact = _a2aSafeFilename(artifactId, 'artifact');
    final dir = Directory(
      '${workspace.path}/attachments/a2a/.incoming/$safeManifest/$safeArtifact',
    );
    try {
      if (await dir.exists()) {
        await dir.delete(recursive: true);
      }
    } catch (_) {}
  }

  void _pruneLocalA2ABlobState() {
    final cutoff = DateTime.now().millisecondsSinceEpoch - 30 * 60 * 1000;
    _localA2ABlobManifests.removeWhere(
      (_, value) => value.createdAtMs < cutoff,
    );
    if (_localA2AResolvedBlobArtifacts.length > 500) {
      final keys = _localA2AResolvedBlobArtifacts.keys.toList();
      for (final key in keys.take(keys.length - 500)) {
        _localA2AResolvedBlobArtifacts.remove(key);
      }
    }
  }

  String _a2aBlobKey(String manifestId, String artifactId) =>
      '$manifestId:$artifactId';

  Future<_A2AArtifactTransportResult> _prepareLocalA2AArtifactsForPeer({
    required List<sdk.A2AArtifact> artifacts,
    required sdk.NapaxiEngine engine,
    required sdk.A2APeer peer,
    required sdk.A2APeerEndpoint endpoint,
    required String localPeerId,
  }) async {
    if (artifacts.isEmpty) {
      return const _A2AArtifactTransportResult(artifacts: [], issues: []);
    }
    final sharedSecret = peer.sharedSecret.trim();
    if (sharedSecret.isEmpty) {
      return _A2AArtifactTransportResult(
        artifacts: artifacts,
        issues: const [
          {
            'severity': 'error',
            'code': 'a2a_blob_requires_trusted_peer',
            'message':
                'A2A attachment transfer requires a trusted paired peer.',
          },
        ],
      );
    }
    final plan = await _buildLocalA2ABlobTransferPlan(artifacts, engine);
    if (plan.issues.isNotEmpty) {
      return _A2AArtifactTransportResult(
        artifacts: plan.artifacts,
        issues: plan.issues,
      );
    }
    final portabilityIssues = _a2aUnportableArtifactIssues(plan.artifacts);
    if (portabilityIssues.isNotEmpty) {
      return _A2AArtifactTransportResult(
        artifacts: plan.artifacts,
        issues: portabilityIssues,
      );
    }
    final blobPlan = plan.blobPlan;
    if (blobPlan == null || blobPlan.files.isEmpty) {
      return _A2AArtifactTransportResult(
        artifacts: plan.artifacts,
        issues: const [],
      );
    }
    final sent = await _sendLocalA2ABlobTransferPlan(
      plan: blobPlan,
      engine: engine,
      peer: peer,
      endpoint: endpoint,
      localPeerId: localPeerId,
      sharedSecret: sharedSecret,
    );
    if (!sent) {
      return _A2AArtifactTransportResult(
        artifacts: plan.artifacts,
        issues: const [
          {
            'severity': 'error',
            'code': 'a2a_blob_transfer_failed',
            'message': 'A2A attachment bytes could not be delivered.',
          },
        ],
      );
    }
    return _A2AArtifactTransportResult(
      artifacts: plan.artifacts,
      issues: const [],
    );
  }

  Future<_A2ABlobBuildResult> _buildLocalA2ABlobTransferPlan(
    List<sdk.A2AArtifact> artifacts,
    sdk.NapaxiEngine engine,
  ) async {
    final manifestId =
        'blob-${DateTime.now().microsecondsSinceEpoch}-${math.Random().nextInt(1 << 32)}';
    final prepared = <sdk.A2AArtifact>[];
    final files = <_A2ABlobTransferFile>[];
    final issues = <Map<String, dynamic>>[];
    var totalBlobBytes = 0;
    for (final artifact in artifacts.take(_a2aMaxArtifactsPerTurn)) {
      final metadata = Map<String, dynamic>.from(artifact.metadata);
      final existingData = _a2aStringField(metadata, [
        'dataBase64',
        'data_base64',
      ]);
      if (existingData.isNotEmpty) {
        metadata['data_base64'] = existingData;
        metadata['transport'] = 'inline_base64';
        prepared.add(_a2aArtifactWithMetadata(artifact, metadata));
        continue;
      }

      final path = _a2aArtifactLocalPathCandidate(artifact, metadata);
      if (path.isEmpty) {
        prepared.add(artifact);
        continue;
      }
      final file = await _a2aResolveTransportFile(
        path,
        engine,
        metadata: metadata,
      );
      if (file == null) {
        issues.add({
          'severity': 'error',
          'code': 'local_artifact_unreadable',
          'artifactId': artifact.artifactId,
          'name': artifact.name,
          'uri': artifact.uri,
          'message':
              'The sending device could not read this local attachment from its scoped workspace. Retry after selecting or importing the media again.',
        });
        prepared.add(artifact);
        continue;
      }
      final size = await file.length();
      if (size > _a2aBlobMaxArtifactBytes) {
        issues.add({
          'severity': 'error',
          'code': 'artifact_too_large',
          'artifactId': artifact.artifactId,
          'name': artifact.name,
          'sizeBytes': size,
          'maxBytes': _a2aBlobMaxArtifactBytes,
        });
        prepared.add(artifact);
        continue;
      }
      if (totalBlobBytes + size > _a2aBlobMaxManifestBytes) {
        issues.add({
          'severity': 'error',
          'code': 'artifact_batch_too_large',
          'artifactId': artifact.artifactId,
          'name': artifact.name,
          'sizeBytes': size,
          'maxBytes': _a2aBlobMaxManifestBytes,
        });
        prepared.add(artifact);
        continue;
      }
      if (files.length >= _a2aBlobMaxArtifactsPerManifest) {
        issues.add({
          'severity': 'error',
          'code': 'too_many_blob_artifacts',
          'maxArtifacts': _a2aBlobMaxArtifactsPerManifest,
        });
        prepared.add(artifact);
        continue;
      }
      totalBlobBytes += size;
      final sha = await _a2aFileSha256Hex(file);
      final chunkCount = math.max(1, (size / _a2aBlobChunkBytes).ceil());
      final artifactId = artifact.artifactId.trim().isEmpty
          ? 'artifact-${files.length + 1}'
          : artifact.artifactId.trim();
      final name = artifact.name.trim().isEmpty
          ? file.uri.pathSegments.last
          : artifact.name.trim();
      final mimeType = artifact.mimeType.trim();
      final blobMetadata = {
        ..._a2aTransferableArtifactMetadata(metadata),
        'transport': 'local_blob',
        'manifest_id': manifestId,
        'blob_id': artifactId,
        'sha256': sha,
        'size_bytes': size,
        'chunk_size': _a2aBlobChunkBytes,
        'chunk_count': chunkCount,
        'source_uri': artifact.uri,
      };
      final blobArtifact = sdk.A2AArtifact(
        artifactId: artifactId,
        mimeType: mimeType,
        name: name,
        uri: 'a2a-blob://$manifestId/$artifactId',
        text: artifact.text,
        metadata: blobMetadata,
      );
      prepared.add(blobArtifact);
      files.add(
        _A2ABlobTransferFile(
          artifact: blobArtifact,
          file: file,
          sizeBytes: size,
          sha256Hex: sha,
          chunkCount: chunkCount,
        ),
      );
    }
    return _A2ABlobBuildResult(
      artifacts: prepared,
      issues: issues,
      blobPlan: files.isEmpty
          ? null
          : _A2ABlobTransferPlan(
              manifestId: manifestId,
              artifacts: prepared
                  .where(
                    (item) =>
                        item.metadata['transport']?.toString() == 'local_blob',
                  )
                  .toList(growable: false),
              files: files,
            ),
    );
  }

  Future<bool> _sendLocalA2ABlobTransferPlan({
    required _A2ABlobTransferPlan plan,
    required sdk.NapaxiEngine engine,
    required sdk.A2APeer peer,
    required sdk.A2APeerEndpoint endpoint,
    required String localPeerId,
    required String sharedSecret,
  }) async {
    final now = DateTime.now().toUtc();
    final manifestFrame = {
      'frameType': 'a2a_blob_manifest',
      'protocolVersion': _a2aBlobProtocolVersion,
      'manifestId': plan.manifestId,
      'fromPeerId': localPeerId,
      'toPeerId': peer.peerId,
      'createdAt': now.toIso8601String(),
      'artifactCount': plan.files.length,
      'artifacts': [
        for (final file in plan.files)
          {
            'artifactId': file.artifact.artifactId,
            'name': file.artifact.name,
            'mimeType': file.artifact.mimeType,
            'sizeBytes': file.sizeBytes,
            'sha256': file.sha256Hex,
            'chunkSize': _a2aBlobChunkBytes,
            'chunkCount': file.chunkCount,
          },
      ],
    };
    final socketTarget = _a2aSocketTargetFromEndpoint(endpoint.uri);
    Socket? socket;
    Future<bool> sendFrame(Map<String, dynamic> frame) async {
      final activeSocket = socket;
      if (activeSocket != null) {
        final message = _a2aBlobFrameMessage(
          localPeerId: localPeerId,
          remotePeerId: peer.peerId,
          sharedSecret: sharedSecret,
          frame: frame,
        );
        activeSocket.write(message.toJsonString());
        activeSocket.write('\n');
        await activeSocket.flush();
        return true;
      }
      return _sendLocalA2ABlobFrame(
        engine: engine,
        endpoint: endpoint.uri,
        localPeerId: localPeerId,
        remotePeerId: peer.peerId,
        sharedSecret: sharedSecret,
        frame: frame,
      );
    }

    if (socketTarget != null) {
      try {
        socket = await Socket.connect(
          socketTarget.host,
          socketTarget.port,
          timeout: const Duration(seconds: 5),
        );
        socket.setOption(SocketOption.tcpNoDelay, true);
      } catch (error) {
        debugPrint(
          '[napaxiToolTrace] local A2A blob socket open failed endpoint=${endpoint.uri} error=$error',
        );
        socket = null;
      }
    }

    try {
      if (!await sendFrame(manifestFrame)) return false;
      for (final file in plan.files) {
        for (var index = 0; index < file.chunkCount; index++) {
          final start = index * _a2aBlobChunkBytes;
          final end = math.min(start + _a2aBlobChunkBytes, file.sizeBytes);
          final bytes = await file.file
              .openRead(start, end)
              .fold<List<int>>(
                <int>[],
                (buffer, chunk) => buffer..addAll(chunk),
              );
          final chunkFrame = {
            'frameType': 'a2a_blob_chunk',
            'protocolVersion': _a2aBlobProtocolVersion,
            'manifestId': plan.manifestId,
            'artifactId': file.artifact.artifactId,
            'fromPeerId': localPeerId,
            'toPeerId': peer.peerId,
            'index': index,
            'total': file.chunkCount,
            'chunkSha256': _a2aBytesSha256Hex(bytes),
            'dataBase64': base64Encode(bytes),
          };
          if (!await sendFrame(chunkFrame)) return false;
        }
      }
      return sendFrame({
        'frameType': 'a2a_blob_complete',
        'protocolVersion': _a2aBlobProtocolVersion,
        'manifestId': plan.manifestId,
        'fromPeerId': localPeerId,
        'toPeerId': peer.peerId,
        'completedAt': DateTime.now().toUtc().toIso8601String(),
      });
    } catch (error) {
      debugPrint('[napaxiToolTrace] local A2A blob send failed=$error');
      return false;
    } finally {
      try {
        await socket?.close();
      } catch (_) {
        socket?.destroy();
      }
    }
  }

  _A2ASocketTarget? _a2aSocketTargetFromEndpoint(String endpoint) {
    var clean = endpoint.trim();
    if (clean.startsWith('tcp://')) {
      clean = clean.substring('tcp://'.length);
    } else if (clean.startsWith('jsonl://')) {
      clean = clean.substring('jsonl://'.length);
    }
    if (clean.endsWith('/a2a')) {
      clean = clean.substring(0, clean.length - '/a2a'.length);
    }
    if (clean.startsWith('[')) {
      final hostEnd = clean.indexOf(']');
      if (hostEnd <= 1 || clean.length <= hostEnd + 2) return null;
      if (clean[hostEnd + 1] != ':') return null;
      final port = int.tryParse(clean.substring(hostEnd + 2));
      if (port == null || port <= 0 || port > 65535) return null;
      return _A2ASocketTarget(host: clean.substring(1, hostEnd), port: port);
    }
    final separator = clean.lastIndexOf(':');
    if (separator <= 0 || separator >= clean.length - 1) return null;
    final port = int.tryParse(clean.substring(separator + 1));
    if (port == null || port <= 0 || port > 65535) return null;
    return _A2ASocketTarget(host: clean.substring(0, separator), port: port);
  }

  sdk.A2APeerMessage _a2aBlobFrameMessage({
    required String localPeerId,
    required String remotePeerId,
    required String sharedSecret,
    required Map<String, dynamic> frame,
  }) {
    final now = DateTime.now().toUtc();
    final nonce =
        '${now.microsecondsSinceEpoch}-${math.Random().nextInt(1 << 32)}';
    final signed = _a2aSignBlobFrame({...frame, 'nonce': nonce}, sharedSecret);
    return sdk.A2APeerMessage(
      messageId: 'blob-$nonce',
      sessionId: 'blob:${signed['manifestId'] ?? nonce}',
      fromPeerId: localPeerId,
      toPeerId: remotePeerId,
      kind: 'ping',
      createdAt: now.toIso8601String(),
      expiresAt: now.add(const Duration(minutes: 10)).toIso8601String(),
      nonce: nonce,
      idempotencyKey: 'blob-$nonce',
      payload: {'a2aBlobFrame': signed},
    );
  }

  Future<bool> _sendLocalA2ABlobFrame({
    required sdk.NapaxiEngine engine,
    required String endpoint,
    required String localPeerId,
    required String remotePeerId,
    required String sharedSecret,
    required Map<String, dynamic> frame,
  }) {
    final message = _a2aBlobFrameMessage(
      localPeerId: localPeerId,
      remotePeerId: remotePeerId,
      sharedSecret: sharedSecret,
      frame: frame,
    );
    return engine.a2a.sendDiagnosticPeerMessage(message, endpoint: endpoint);
  }

  bool _isAutoRunnableLocalA2ACollaboration(sdk.A2ATaskRecord? task) {
    if (task == null) return false;
    final collaboration = task.request.context['a2aCollaboration'];
    if (collaboration is! Map) return false;
    final autoAccept = collaboration['autoAcceptLowRisk'] == true;
    final risk = collaboration['risk']?.toString().trim().toLowerCase() ?? '';
    final sessionId = collaboration['sessionId']?.toString().trim() ?? '';
    return autoAccept && risk == 'low' && sessionId.isNotEmpty;
  }

  bool _isFinishedLocalA2ATask(sdk.A2ATaskRecord? task) {
    final status = task?.status.trim().toLowerCase() ?? '';
    return status == 'succeeded' ||
        status == 'failed' ||
        status == 'rejected' ||
        status == 'cancelled';
  }

  Future<sdk.A2ALocalPeerAdvertisement?> _localA2ASavedPeerAdvertisement(
    String peerId,
  ) async {
    final target = peerId.trim();
    if (target.isEmpty) return null;
    for (final peer in await listLocalA2APeers()) {
      if (peer.peerId != target) continue;
      final endpoint = peer.endpoints.isEmpty ? null : peer.endpoints.first;
      if (endpoint == null || endpoint.uri.trim().isEmpty) return null;
      return sdk.A2ALocalPeerAdvertisement(
        peerId: peer.peerId,
        agentId: peer.agentId,
        displayName: peer.displayName,
        publicKey: peer.publicKey,
        transport: endpoint.transport,
        endpoint: endpoint.uri,
      );
    }
    return null;
  }

  String? _a2aTaskIdFromPeerMessage(sdk.A2APeerMessage message) {
    for (final key in const ['task', 'progress', 'result']) {
      final payload = message.payload[key];
      if (payload is! Map) continue;
      final taskId =
          payload['taskId']?.toString().trim() ??
          payload['task_id']?.toString().trim();
      if (taskId != null && taskId.isNotEmpty) return taskId;
    }
    return null;
  }

  Future<void> _runLocalA2AAutoResponseTask({
    required String taskId,
    required sdk.A2APeerMessage message,
    required sdk.A2ALocalPeerAdvertisement peer,
  }) async {
    final task = await getLocalA2ATask(taskId);
    if (task == null) return;
    try {
      try {
        final progress = await createLocalA2AProgressMessage(
          message.sessionId,
          taskId,
          '已收到，正在回复。',
          status: 'running',
        );
        await sendLocalA2AMessage(progress, endpoint: peer.endpoint);
      } catch (_) {
        // Progress is best-effort; the final result is the user-visible event.
      }

      await submitLocalA2AChannelTask(task: task, peer: peer);
      final run = await runLocalA2AChannelTask(
        taskId: taskId,
        agentId: _activeRuntimeProfile.agentId,
      );
      if (!run.delivered) {
        debugPrint(
          '[napaxiToolTrace] local A2A auto response not delivered task=$taskId error=${run.error}',
        );
      }
    } catch (error) {
      try {
        final failure = await createLocalA2AResultMessage(
          message.sessionId,
          taskId,
          '这边的 Agent 暂时没能完成回复：$error',
          status: 'failed',
        );
        await sendLocalA2AMessage(failure, endpoint: peer.endpoint);
      } catch (_) {}
    }
  }

  @override
  Future<sdk.A2ALocalTransportStatus> localA2AStatus() async {
    final engine = await _ensureManagementEngine();
    final status = await engine.a2a.localTransportStatus();
    _setLocalA2AToolsEnabled(status.supported && status.running);
    if (status.supported && status.running) {
      _ensureLocalA2AAutoResponder(engine);
    }
    return status;
  }

  @override
  Future<bool> checkLocalA2APermission() async {
    final engine = await _ensureManagementEngine();
    return engine.a2a.checkLocalTransportPermission();
  }

  @override
  Future<bool> requestLocalA2APermission() async {
    final engine = await _ensureManagementEngine();
    return engine.a2a.requestLocalTransportPermission();
  }

  @override
  String generateLocalA2APairingSecret() {
    return _a2aStatelessHelper.generateLocalPairingSecret();
  }

  @override
  String normalizeLocalA2APairingSecret(String value) {
    return _a2aStatelessHelper.normalizePairingSecret(value);
  }

  @override
  String formatLocalA2APairingSecret(String value) {
    return _a2aStatelessHelper.formatPairingSecret(value);
  }

  @override
  String localA2APairingKey(sdk.A2ALocalPeerAdvertisement peer) {
    return _a2aStatelessHelper.pairingKey(peer);
  }

  @override
  String localA2APairingCode(String peerId, String publicKey) {
    return _a2aStatelessHelper.pairingCodeFromIdentity(peerId, publicKey);
  }

  @override
  String deriveLocalA2ASharedSecret({
    required String localPeerId,
    required String localPublicKey,
    required String localPairingSecret,
    required sdk.A2ALocalPeerAdvertisement peer,
    required String remotePairingSecret,
  }) {
    return _a2aStatelessHelper.deriveLocalSharedSecret(
      localPeerId: localPeerId,
      localPublicKey: localPublicKey,
      localPairingSecret: localPairingSecret,
      peer: peer,
      remotePairingSecret: remotePairingSecret,
    );
  }

  @override
  Future<sdk.A2ALocalTransportStatus> startLocalA2A({
    required String agentId,
    required String displayName,
    String publicKey = '',
  }) async {
    await _ensureAgent(agentId);
    final engine = await _ensureManagementEngine();
    final status = await engine.a2a.startLocalTransport(
      agentId: agentId,
      displayName: displayName,
      publicKey: publicKey,
    );
    _setLocalA2AToolsEnabled(status.supported && status.running);
    if (status.supported && status.running) {
      _ensureLocalA2AAutoResponder(engine);
    }
    return status;
  }

  @override
  Future<sdk.A2ALocalTransportStatus> stopLocalA2A() async {
    final engine = await _ensureManagementEngine();
    final status = await engine.a2a.stopLocalTransport();
    _setLocalA2AToolsEnabled(status.supported && status.running);
    await _stopLocalA2AAutoResponder();
    return status;
  }

  @override
  Future<List<sdk.A2ALocalPeerAdvertisement>> discoverLocalA2APeers({
    int timeoutMs = 5000,
  }) async {
    final engine = await _ensureManagementEngine();
    return engine.a2a.discoverLocalPeers(timeoutMs: timeoutMs);
  }

  @override
  Future<sdk.A2APeerSession> openLocalA2ASession(
    sdk.A2ALocalPeerAdvertisement peer, {
    String sharedSecret = '',
  }) async {
    final engine = await _ensureManagementEngine();
    final status = await engine.a2a.localTransportStatus();
    return engine.a2a.openPeerSession(
      peer.toPeer(trustLevel: 'user_confirmed', sharedSecret: sharedSecret),
      transport: peer.coreTransport,
      endpoint: peer.endpoint,
      localPeerId: status.peerId,
    );
  }

  @override
  Future<List<sdk.A2APeer>> listLocalA2APeers({String agentId = ''}) async =>
      (await _ensureManagementEngine()).a2a.listPeers(agentId: agentId);

  @override
  Future<bool> deleteLocalA2APeer(String peerId) async {
    final engine = await _ensureManagementEngine();
    return engine.a2a.deletePeer(peerId);
  }

  @override
  Future<sdk.A2APeerMessage> createLocalA2ATaskMessage(
    String sessionId,
    String message, {
    Map<String, dynamic> options = const {},
  }) async => (await _ensureManagementEngine()).a2a.createTaskMessage(
    sessionId,
    message,
    options: options,
  );

  @override
  Future<sdk.A2APeerMessage> createLocalA2AProgressMessage(
    String sessionId,
    String taskId,
    String message, {
    String? status,
  }) async => (await _ensureManagementEngine()).a2a.createTaskProgressMessage(
    sessionId,
    taskId,
    message,
    progress: status == null ? const {} : {'status': status},
  );

  @override
  Future<sdk.A2APeerMessage> createLocalA2AResultMessage(
    String sessionId,
    String taskId,
    String message, {
    String? status,
  }) async => (await _ensureManagementEngine()).a2a.createTaskResultMessage(
    sessionId,
    taskId,
    result: {'message': message, 'status': ?status},
  );

  @override
  Future<sdk.A2APeerMessage> createLocalA2ADiagnosticMessage({
    required String localPeerId,
  }) async {
    final now = DateTime.now().toUtc();
    final nonce = now.microsecondsSinceEpoch.toString();
    return sdk.A2APeerMessage(
      messageId: 'diag-$nonce',
      sessionId: 'diagnostic:$localPeerId',
      fromPeerId: localPeerId,
      toPeerId: localPeerId,
      kind: 'ping',
      createdAt: now.toIso8601String(),
      expiresAt: now.add(const Duration(minutes: 5)).toIso8601String(),
      nonce: nonce,
      idempotencyKey: 'diag-$nonce',
      payload: const {'purpose': 'local_a2a_loopback'},
    );
  }

  @override
  Future<bool> sendLocalA2AMessage(
    sdk.A2APeerMessage message, {
    required String endpoint,
  }) async {
    final engine = await _ensureManagementEngine();
    return engine.a2a.sendPeerMessage(message, endpoint: endpoint);
  }

  @override
  Future<bool> sendLocalA2ADiagnosticMessage(
    sdk.A2APeerMessage message, {
    required String endpoint,
  }) async {
    final engine = await _ensureManagementEngine();
    return engine.a2a.sendDiagnosticPeerMessage(message, endpoint: endpoint);
  }

  @override
  Future<sdk.A2ADeliveryRecord> recordLocalA2AMessage(
    sdk.A2APeerMessage message, {
    String source = 'local_transport_require_trusted',
  }) async {
    final engine = await _ensureManagementEngine();
    return engine.a2a.recordPeerMessage(message, source: source);
  }

  @override
  Future<List<sdk.A2ADeliveryRecord>> listLocalA2ADeliveryRecords(
    String sessionId, {
    int limit = 100,
    int offset = 0,
  }) async => (await _ensureManagementEngine()).a2a.listDeliveryRecords(
    sessionId,
    limit: limit,
    offset: offset,
  );

  @override
  Future<List<sdk.A2APeerMessage>> listLocalA2APeerMessages(
    String sessionId, {
    int limit = 100,
    int offset = 0,
  }) async => (await _ensureManagementEngine()).a2a.listPeerMessages(
    sessionId,
    limit: limit,
    offset: offset,
  );

  @override
  Future<sdk.A2ATaskRecord> runLocalA2ATask(String taskId) async =>
      (await _ensureManagementEngine()).a2a.runTask(taskId);

  @override
  Future<sdk.A2ATaskRecord?> getLocalA2ATask(String taskId) async =>
      (await _ensureManagementEngine()).a2a.getTask(taskId);

  @override
  Future<List<sdk.A2ATaskRecord>> listLocalA2ATasks({int limit = 50}) async {
    final engine = await _ensureManagementEngine();
    return engine.a2a
        .listTasks(limit: limit)
        .where((task) {
          return task.source.contains('local_transport') ||
              task.sessionKey != null;
        })
        .toList(growable: false);
  }

  @override
  Future<List<sdk.A2AArtifact>> resolveLocalA2AArtifacts(
    List<sdk.A2AArtifact> artifacts,
  ) async {
    if (artifacts.isEmpty) return const [];
    final engine = await _ensureManagementEngine();
    final resolved = await _resolveLocalA2ABlobArtifacts(
      artifacts,
      timeout: const Duration(milliseconds: 1200),
    );
    final visible = <sdk.A2AArtifact>[];
    for (final artifact in resolved) {
      final issues = await _validateResolvedLocalA2AArtifacts([
        artifact,
      ], engine);
      if (issues.isEmpty) visible.add(artifact);
    }
    return visible;
  }

  @override
  void dispose() {
    _automationToolExecutor.detach();
    _localA2AChannelBridgeSubscription?.cancel();
    unawaited(_localA2AChannelBridge?.dispose(stopBackground: false));
    unawaited(_stopLocalA2AAutoResponder());
    _stopAllDemoQqChannelBridges();
    _stopAllDemoHeadsetChannelBridges();
    unawaited(_channelBridgeEvents.close());
    _engine?.dispose();
    browserController.dispose();
    _engine = null;
    _demoQqChannelProviders.clear();
    _demoHeadsetChannelProviders.clear();
  }

  sdk.NapaxiEngine _requireEngine() {
    final engine = _engine;
    if (engine == null) {
      throw StateError('napaxi engine has not been configured');
    }
    return engine;
  }

  Future<void> _ensureAgent(String agentId) async {
    final engine = await _ensureManagementEngine();
    final runtimeProfile = _activeRuntimeProfile;
    if (!runtimeProfile.supportsAgents && agentId == runtimeProfile.agentId) {
      await _ensureRuntimeAgent(engine);
      return;
    }
    if (agentId == sdk.NapaxiEngine.defaultAgentId) {
      engine.ensureAgent();
      return;
    }
    final definition = await engine.getAgentDefinition(agentId);
    if (definition != null) {
      final created = await engine.createAgentFromDefinition(agentId);
      if (created) return;
      if (engine.listAgents().contains(agentId)) return;
    }
    await engine.getOrCreateAgent(agentId);
  }

  Future<void> _ensureRuntimeAgent(sdk.NapaxiEngine engine) async {
    final runtimeProfile = _activeRuntimeProfile;
    if (runtimeProfile.supportsAgents) {
      engine.ensureAgent();
      return;
    }
    final existing = await engine.getAgentDefinition(runtimeProfile.agentId);
    if (existing == null) {
      await engine.createAgentDefinition(
        sdk.AgentDefinition(
          id: runtimeProfile.agentId,
          name: runtimeProfile.activeEngine.label,
          description: 'Focused mobile development engine runtime.',
          systemPrompt:
              'You are a focused mobile development engine. Prioritize concise project-aware coding help, use dedicated Git/project tools when available, and avoid multi-agent delegation unless the host explicitly exposes it.',
          icon: 'terminal',
        ),
      );
    }
    final created = await engine.createAgentFromDefinition(
      runtimeProfile.agentId,
    );
    if (!created && !engine.listAgents().contains(runtimeProfile.agentId)) {
      await engine.getOrCreateAgent(runtimeProfile.agentId);
    }
    await _ensureRuntimePresetSkills(engine, runtimeProfile);
  }

  Future<void> _ensureRuntimePresetSkills(
    sdk.NapaxiEngine engine,
    DemoScenarioRuntimeProfile runtimeProfile,
  ) async {
    if (!runtimeProfile.isDeveloper) return;
    final installed = {
      for (final skill in engine.listSkills(agentId: runtimeProfile.agentId))
        skill.name.trim().toLowerCase(),
    };
    var changed = false;
    for (final preset in _defaultPresetSkills()) {
      final name = preset.name.trim().toLowerCase();
      if (name.isEmpty || installed.contains(name)) continue;
      final result = await engine.installSkill(
        preset.skillContent,
        agentId: runtimeProfile.agentId,
      );
      if (result.success) {
        installed.add(name);
        changed = true;
      }
    }
    if (changed) {
      await engine.reloadSkills(agentId: runtimeProfile.agentId);
    }
  }

  Future<void> _reloadProviderAgent(String agentId) async {
    final engine = await _ensureManagementEngine();
    if (agentId == sdk.NapaxiEngine.defaultAgentId) {
      engine.ensureAgent();
      return;
    }
    engine.deleteAgent(agentId);
    final definition = await engine.getAgentDefinition(agentId);
    if (definition != null) {
      final created = await engine.createAgentFromDefinition(agentId);
      if (created) return;
    }
    await engine.getOrCreateAgent(agentId);
  }
}

class DemoLocalA2AChannelReceipt {
  const DemoLocalA2AChannelReceipt({
    required this.taskId,
    required this.inboundId,
    this.duplicate = false,
  });

  final String taskId;
  final String inboundId;
  final bool duplicate;
}

class DemoLocalA2AChannelRun {
  const DemoLocalA2AChannelRun({
    required this.taskId,
    required this.delivered,
    required this.phase,
    this.summary = '',
    this.error,
  });

  final String taskId;
  final bool delivered;
  final String phase;
  final String summary;
  final String? error;
}

class _A2AConnectivityReport {
  const _A2AConnectivityReport({
    required this.local,
    required this.savedTrustedPeerCount,
    required this.discoveredPeerCount,
    required this.verifiedPeerCount,
    required this.peers,
    required this.transportCandidates,
  });

  final sdk.A2ALocalTransportStatus local;
  final int savedTrustedPeerCount;
  final int discoveredPeerCount;
  final int verifiedPeerCount;
  final List<sdk.A2APeer> peers;
  final List<_A2ATransportCandidate> transportCandidates;

  bool get hasVerifiedChannel => verifiedPeerCount > 0;

  Map<String, dynamic> toJson() {
    final unavailablePeerCount = peers.length - verifiedPeerCount;
    return {
      'hasVerifiedChannel': hasVerifiedChannel,
      'savedTrustedPeerCount': savedTrustedPeerCount,
      'discoveredPeerCount': discoveredPeerCount,
      'verifiedPeerCount': verifiedPeerCount,
      'unavailableTrustedPeerCount': unavailablePeerCount < 0
          ? 0
          : unavailablePeerCount,
      'local': {
        'supported': local.supported,
        'running': local.running,
        'transport': local.transport,
        'serviceType': local.serviceType,
        'peerId': local.peerId,
        'agentId': local.agentId,
        'displayName': local.displayName,
        'endpoint': local.endpoint,
        'listenerPort': local.listenerPort,
        'registeredName': local.registeredName,
        'multicastLockHeld': local.multicastLockHeld,
        'reason': local.reason,
        'lastError': local.lastError,
      },
      'transportCandidates': transportCandidates
          .map((candidate) => candidate.toJson())
          .toList(growable: false),
      'peers': peers.map(_peerJson).toList(growable: false),
    };
  }

  Map<String, dynamic> summaryJson() {
    final unavailablePeerCount = peers.length - verifiedPeerCount;
    return {
      'hasVerifiedChannel': hasVerifiedChannel,
      'savedTrustedPeerCount': savedTrustedPeerCount,
      'discoveredPeerCount': discoveredPeerCount,
      'verifiedPeerCount': verifiedPeerCount,
      'unavailableTrustedPeerCount': unavailablePeerCount < 0
          ? 0
          : unavailablePeerCount,
      'local': {
        'supported': local.supported,
        'running': local.running,
        'reason': local.reason,
        'lastError': local.lastError,
      },
      'agents': peers
          .map(
            (peer) => {
              'displayLabel': _a2aPeerDisplayLabel(peer),
              'available': peer.endpoints.any(
                (endpoint) => endpoint.uri.trim().isNotEmpty,
              ),
              'trusted':
                  peer.sharedSecret.trim().isNotEmpty ||
                  peer.trustLevel.trim().toLowerCase() == 'trusted' ||
                  peer.trustLevel.trim().toLowerCase() == 'user_confirmed',
            },
          )
          .toList(growable: false),
    };
  }

  static Map<String, dynamic> _peerJson(sdk.A2APeer peer) {
    final verified = peer.endpoints.any(
      (endpoint) => endpoint.uri.trim().isNotEmpty,
    );
    return {
      'peerId': peer.peerId,
      'agentId': peer.agentId,
      'displayName': peer.displayName,
      'displayLabel': _a2aPeerDisplayLabel(peer),
      'trustLevel': peer.trustLevel,
      'verifiedChannel': verified,
      'hasSharedSecret': peer.sharedSecret.trim().isNotEmpty,
      'lastSeenAt': peer.lastSeenAt,
      'endpoints': peer.endpoints
          .map((endpoint) => endpoint.toJson())
          .toList(growable: false),
      if (!verified) 'unavailableReason': 'no_current_verified_endpoint',
    };
  }
}

class _A2ATransportCandidate {
  const _A2ATransportCandidate({
    required this.transport,
    required this.status,
    this.reason = '',
  });

  factory _A2ATransportCandidate.unavailable({
    required String transport,
    required String reason,
  }) {
    return _A2ATransportCandidate(
      transport: transport,
      status: 'unavailable',
      reason: reason,
    );
  }

  final String transport;
  final String status;
  final String reason;

  Map<String, dynamic> toJson() => {
    'transport': transport,
    'status': status,
    if (reason.isNotEmpty) 'reason': reason,
  };
}

class _DemoLocalA2AChannelTaskContext {
  const _DemoLocalA2AChannelTaskContext({
    required this.taskId,
    required this.sessionId,
    required this.peerMessageId,
    required this.peer,
    required this.visibleConversationSessionId,
  });

  final String taskId;
  final String sessionId;
  final String peerMessageId;
  final sdk.A2ALocalPeerAdvertisement peer;
  final String visibleConversationSessionId;

  String get localReplyMessageId => 'a2a-$taskId-local-reply';
}

class _DemoLocalA2AChannelProvider extends sdk.NapaxiChannelProvider {
  _DemoLocalA2AChannelProvider(this.engine, this.owner);

  static const name = 'local_a2a';
  static const accountId = 'local-device';

  final sdk.NapaxiEngine engine;
  final NapaxiSdkChatClient owner;
  final Map<String, _DemoLocalA2AChannelTaskContext> _tasksByTaskId = {};
  final Map<String, _DemoLocalA2AChannelTaskContext> _tasksByMessageId = {};
  final Map<String, _DemoLocalA2AChannelTaskContext> _tasksByInboundId = {};
  final Map<String, Completer<bool>> _resultWaiters = {};
  final Map<String, String> _resultSummariesByTaskId = {};
  String? _activeTaskId;

  @override
  sdk.NapaxiChannelProviderManifest get manifest =>
      const sdk.NapaxiChannelProviderManifest(
        providerId: 'napaxi.demo.local_a2a',
        channelName: name,
        displayName: 'Local A2A',
        description: 'Trusted local device-to-device Agent task channel.',
        accountId: accountId,
        surfaceKind: sdk.NapaxiChannelSurfaceKind.device,
        endpointKinds: [sdk.NapaxiChannelEndpointKind.device],
        modalities: [
          sdk.NapaxiChannelModality.text,
          sdk.NapaxiChannelModality.image,
          sdk.NapaxiChannelModality.file,
        ],
        contentFormats: [sdk.NapaxiChannelContentFormat.markdown],
        transport: 'local_a2a_lan',
      );

  void rememberTask(_DemoLocalA2AChannelTaskContext context) {
    _tasksByTaskId[context.taskId] = context;
    _tasksByMessageId[context.peerMessageId] = context;
  }

  void rememberInbound(String taskId, String inboundId) {
    final context = _tasksByTaskId[taskId.trim()];
    final normalized = inboundId.trim();
    if (context == null || normalized.isEmpty) return;
    _tasksByInboundId[normalized] = context;
  }

  sdk.NapaxiChannelAgentBridgeEvent withUiContext(
    sdk.NapaxiChannelAgentBridgeEvent event,
  ) {
    final context = _contextForBridgeEvent(event);
    if (context == null) return event;
    final raw = Map<String, dynamic>.from(event.raw);
    raw['a2a_ui'] = {
      'taskId': context.taskId,
      'conversationSessionId': context.visibleConversationSessionId,
      'localReplyMessageId': context.localReplyMessageId,
      'peerLabel': _a2aPeerDisplayLabel(context.peer),
    };
    return sdk.NapaxiChannelAgentBridgeEvent(
      type: event.type,
      channelName: event.channelName,
      channelDisplayName: event.channelDisplayName,
      agentId: event.agentId,
      session: event.session,
      inboundId: event.inboundId,
      platformMessageId: event.platformMessageId,
      platformThreadId: event.platformThreadId,
      peerKind: event.peerKind,
      peerId: event.peerId,
      peerDisplayName: event.peerDisplayName,
      senderId: event.senderId,
      senderDisplayName: event.senderDisplayName,
      inboundText: event.inboundText,
      responseText: event.responseText,
      createdAt: event.createdAt,
      assistantMessageId: event.assistantMessageId,
      chatEvent: event.chatEvent,
      openAssistant: event.openAssistant,
      completeAssistant: event.completeAssistant,
      humanRequestId: event.humanRequestId,
      humanQuestion: event.humanQuestion,
      humanOptions: event.humanOptions,
      humanContext: event.humanContext,
      humanResponseRequestId: event.humanResponseRequestId,
      error: event.error,
      raw: raw,
    );
  }

  _DemoLocalA2AChannelTaskContext? _contextForBridgeEvent(
    sdk.NapaxiChannelAgentBridgeEvent event,
  ) {
    final inbound = event.inboundId.trim();
    if (inbound.isNotEmpty) {
      final byInbound = _tasksByInboundId[inbound];
      if (byInbound != null) return byInbound;
    }
    final platformMessageId = event.platformMessageId?.trim() ?? '';
    if (platformMessageId.isNotEmpty) {
      final byMessage = _tasksByMessageId[platformMessageId];
      if (byMessage != null) return byMessage;
    }
    final active = _activeTaskId;
    if (active != null) return _tasksByTaskId[active];
    return null;
  }

  void markActiveTask(String taskId) {
    _activeTaskId = taskId;
  }

  void clearActiveTask(String taskId) {
    if (_activeTaskId == taskId) _activeTaskId = null;
  }

  Future<bool> waitForTaskResult(String taskId) {
    final completer = _resultWaiters.putIfAbsent(
      taskId,
      () => Completer<bool>(),
    );
    return completer.future.timeout(
      const Duration(minutes: 5),
      onTimeout: () => false,
    );
  }

  String takeTaskResultSummary(String taskId) {
    return _resultSummariesByTaskId.remove(taskId.trim()) ?? '';
  }

  @override
  Future<sdk.NapaxiChannelOutboundDeliveryResult> deliverOutbound(
    sdk.NapaxiChannelOutboundMessage message,
  ) async {
    final context = _resolveContext(message);
    if (context == null) {
      return const sdk.NapaxiChannelOutboundDeliveryResult.failed(
        'missing_local_a2a_task_context',
      );
    }
    final text = message.text?.trim() ?? '';
    if (text.isEmpty) {
      return const sdk.NapaxiChannelOutboundDeliveryResult.failed(
        'missing_local_a2a_result_text',
      );
    }
    try {
      final endpointPeer = await _freshPeerForContext(context.peer);
      if (endpointPeer == null && context.peer.endpoint.trim().isEmpty) {
        _resultWaiters.remove(context.taskId)?.complete(false);
        return const sdk.NapaxiChannelOutboundDeliveryResult.failed(
          'local_a2a_no_verified_result_channel',
        );
      }
      final rawStatus = message.raw?['status']?.toString().trim() ?? '';
      final resultStatus = rawStatus == 'failed' ? 'failed' : 'succeeded';
      final resultEndpoint = endpointPeer?.endpoint ?? context.peer.endpoint;
      final resultTransport =
          endpointPeer?.coreTransport ?? context.peer.coreTransport;
      sdk.A2APeer? savedPeer;
      for (final peer in engine.a2a.listPeers()) {
        if (peer.peerId == context.peer.peerId) {
          savedPeer = peer;
          break;
        }
      }
      if (savedPeer == null) {
        _resultWaiters.remove(context.taskId)?.complete(false);
        return const sdk.NapaxiChannelOutboundDeliveryResult.failed(
          'local_a2a_result_peer_not_trusted',
        );
      }
      final localStatus = await engine.a2a.localTransportStatus();
      final transportArtifacts = await owner._prepareLocalA2AArtifactsForPeer(
        artifacts: _a2aArtifactsFromChannelMedia(message.media),
        engine: engine,
        peer: savedPeer,
        endpoint: sdk.A2APeerEndpoint(
          transport: resultTransport,
          uri: resultEndpoint,
        ),
        localPeerId: localStatus.peerId,
      );
      if (!transportArtifacts.ok) {
        _resultWaiters.remove(context.taskId)?.complete(false);
        return const sdk.NapaxiChannelOutboundDeliveryResult.failed(
          'local_a2a_result_artifact_not_portable',
        );
      }
      final artifacts = transportArtifacts.artifacts;
      final result = engine.a2a.createTaskResultMessage(
        context.sessionId,
        context.taskId,
        result: {
          'message': text,
          'status': resultStatus,
          if (artifacts.isNotEmpty)
            'artifacts': _a2aArtifactJsonList(artifacts),
        },
      );
      var sent = await engine.a2a.sendPeerMessage(
        result,
        endpoint: resultEndpoint,
      );
      var deliveredEndpoint = resultEndpoint;
      var deliveredTransport = resultTransport;
      final waiter = _resultWaiters.remove(context.taskId);
      if (!sent) {
        waiter?.complete(false);
        return const sdk.NapaxiChannelOutboundDeliveryResult.failed(
          'local_a2a_result_send_failed',
        );
      }
      _resultSummariesByTaskId[context.taskId] = text;
      waiter?.complete(true);
      return sdk.NapaxiChannelOutboundDeliveryResult.delivered(
        receipt: {
          'task_id': context.taskId,
          'a2a_session_id': context.sessionId,
          'peer_message_id': result.messageId,
          'endpoint': deliveredEndpoint,
          'transport': deliveredTransport,
        },
      );
    } catch (error) {
      _resultWaiters.remove(context.taskId)?.complete(false);
      return sdk.NapaxiChannelOutboundDeliveryResult.failed(error.toString());
    }
  }

  Future<sdk.A2ALocalPeerAdvertisement?> _freshPeerForContext(
    sdk.A2ALocalPeerAdvertisement peer,
  ) async {
    if (peer.peerId.trim().isEmpty) return null;
    try {
      final status = await engine.a2a.localTransportStatus();
      if (!status.supported || !status.running) return null;
      final discovered = await engine.a2a.discoverLocalPeers(
        timeoutMs: _localA2ADiscoveryTimeoutMs,
      );
      for (final candidate in discovered) {
        if (candidate.peerId != peer.peerId) continue;
        if (candidate.endpoint.trim().isEmpty) continue;
        final expectedKey = peer.publicKey.trim();
        final actualKey = candidate.publicKey.trim();
        if (expectedKey.isNotEmpty &&
            actualKey.isNotEmpty &&
            expectedKey != actualKey) {
          continue;
        }
        return candidate;
      }
    } catch (error) {
      debugPrint(
        '[napaxiToolTrace] local A2A result endpoint refresh failed: $error',
      );
    }
    return null;
  }

  _DemoLocalA2AChannelTaskContext? _resolveContext(
    sdk.NapaxiChannelOutboundMessage message,
  ) {
    final raw = message.raw ?? const <String, dynamic>{};
    final rawTaskId = raw['task_id']?.toString().trim() ?? '';
    if (rawTaskId.isNotEmpty) return _tasksByTaskId[rawTaskId];
    final replyTo = message.replyToMessageId?.trim() ?? '';
    if (replyTo.isNotEmpty) {
      final byMessage = _tasksByMessageId[replyTo];
      if (byMessage != null) return byMessage;
    }
    final active = _activeTaskId;
    if (active != null) return _tasksByTaskId[active];
    return null;
  }
}

class _DemoWebViewBrowserBackend implements sdk.NapaxiBrowserBackend {
  _DemoWebViewBrowserBackend() {
    controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onProgress: (progress) {
            _progress = progress;
            _loading = progress < 100;
            onStateChanged?.call();
          },
          onPageStarted: (_) {
            _loading = true;
            _progress = 0;
            _blockedNavigation = null;
            onStateChanged?.call();
          },
          onPageFinished: (_) {
            _loading = false;
            _progress = 100;
            onStateChanged?.call();
          },
          onNavigationRequest: (request) {
            final uri = Uri.tryParse(request.url);
            final scheme = uri?.scheme.toLowerCase();
            if (scheme == 'http' || scheme == 'https' || scheme == 'about') {
              return NavigationDecision.navigate;
            }
            _blockedNavigation = request.url;
            onStateChanged?.call();
            return NavigationDecision.prevent;
          },
        ),
      );
  }

  late final WebViewController controller;
  final GlobalKey _screenshotBoundaryKey = GlobalKey(
    debugLabel: 'napaxi_browser_screenshot_boundary',
  );
  // Assigned right after the owning controller is constructed; see
  // NapaxiSdkChatClient._createBrowserController.
  VoidCallback? onStateChanged;
  bool _loading = false;
  int _progress = 0;
  String? _blockedNavigation;

  @override
  bool get loading => _loading;

  @override
  int get progress => _progress;

  @override
  String? get blockedNavigation => _blockedNavigation;

  @override
  sdk.BrowserBackendCapabilities get capabilities =>
      const sdk.BrowserBackendCapabilities(supportsScreenshot: true);

  @override
  Widget buildWidget() => RepaintBoundary(
    key: _screenshotBoundaryKey,
    child: WebViewWidget(controller: controller),
  );

  @override
  Future<bool> canGoBack() => controller.canGoBack();

  @override
  Future<void> clearCache() => controller.clearCache();

  @override
  Future<void> clearLocalStorage() => controller.clearLocalStorage();

  @override
  Future<sdk.NapaxiBrowserScreenshot?> captureScreenshot(
    sdk.BrowserScreenshotMode mode,
  ) async {
    if (!sdk.NapaxiFileBridge.isInitialized) return null;
    final context = _screenshotBoundaryKey.currentContext;
    if (context == null) return null;
    final renderObject = context.findRenderObject();
    if (renderObject is! RenderRepaintBoundary) return null;
    try {
      final image = await renderObject.toImage(pixelRatio: 1.0);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      if (bytes == null || bytes.lengthInBytes == 0) return null;
      final directory = Directory(
        '${sdk.NapaxiFileBridge.instance.workspaceDir.path}/browser/screenshots',
      );
      await directory.create(recursive: true);
      final timestamp = DateTime.now().toUtc().millisecondsSinceEpoch;
      final file = File('${directory.path}/browser_$timestamp.png');
      await file.writeAsBytes(bytes.buffer.asUint8List(), flush: true);
      final width = image.width;
      final height = image.height;
      image.dispose();
      return sdk.NapaxiBrowserScreenshot(
        sandboxPath:
            '/workspace/browser/screenshots/${file.uri.pathSegments.last}',
        width: width,
        height: height,
      );
    } catch (_) {
      return null;
    }
  }

  @override
  Future<String?> currentUrl() => controller.currentUrl();

  @override
  Future<void> goBack() => controller.goBack();

  @override
  Future<void> loadUrl(String url) => controller.loadRequest(Uri.parse(url));

  @override
  Future<void> setUserAgent(String? userAgent) =>
      controller.setUserAgent(userAgent);

  @override
  Future<void> reload() => controller.reload();

  @override
  Future<void> runJavaScript(String javaScript) =>
      controller.runJavaScript(javaScript);

  @override
  Future<Object?> runJavaScriptReturningResult(String javaScript) =>
      controller.runJavaScriptReturningResult(javaScript);

  @override
  Future<String?> title() => controller.getTitle();
}

class _DemoAutomationToolExecutor extends sdk.McToolExecutor {
  static const gitCapabilityId = 'napaxi.tool.git';
  static const _createTool = 'napaxi_automation_create';
  static const _listTool = 'napaxi_automation_list';
  static const _cancelTool = 'napaxi_automation_cancel';
  static const _syncTool = 'napaxi_automation_sync';
  static const _gitCloneTool = 'git_clone';
  static const _gitStatusTool = 'git_status';
  static const _gitDiffTool = 'git_diff';
  static const _gitListBranchesTool = 'git_list_branches';
  static const _gitSwitchBranchTool = 'git_switch_branch';
  static const _gitListRemotesTool = 'git_list_remotes';
  static const _gitSetRemoteTool = 'git_set_remote';
  static const _gitFetchTool = 'git_fetch';
  static const _androidCreateProjectTool = 'android_create_project';
  static const _androidBuildApkTool = 'android_build_apk';
  static const _a2aListAgentsTool = 'a2a_list_agents';
  static const _a2aStartCollaborationTool = 'a2a_start_collaboration';
  static const _a2aSendMessageTool = 'a2a_send_message';
  static const _a2aWaitMessagesTool = 'a2a_wait_messages';
  static const _a2aFinishCollaborationTool = 'a2a_finish_collaboration';
  static const _a2aToolNames = {
    _a2aListAgentsTool,
    _a2aStartCollaborationTool,
    _a2aSendMessageTool,
    _a2aWaitMessagesTool,
    _a2aFinishCollaborationTool,
  };
  static const _a2aCollaborationStoreKey = 'agent_demo.a2a.collaborations.v1';
  static const MethodChannel _platformContextChannel = MethodChannel(
    'com.napaxi.flutter/platform_context',
  );

  static const toolDefinitions = [
    sdk.CustomToolDef(
      name: _createTool,
      description:
          'Create a mobile scheduled automation/reminder from chat. Use this when the user asks to remind them, run something later, or create a recurring local-time task. Prefer delaySeconds/delayMinutes for relative times like "in 2 minutes"; use localTime for daily/weekday schedules.',
      effect: 'write',
      parameters: {
        'type': 'object',
        'properties': {
          'name': {
            'type': 'string',
            'description': 'Short human-readable task name.',
          },
          'message': {
            'type': 'string',
            'description':
                'The reminder text or agent instruction to run at the scheduled time.',
          },
          'payloadKind': {
            'type': 'string',
            'enum': ['systemEvent', 'agentTurn'],
            'description':
                'Use agentTurn for scheduled work that napaxi should execute. Use systemEvent only for a passive reminder/message injection.',
          },
          'maxIterations': {
            'type': 'integer',
            'description':
                'Optional max tool iterations for an agentTurn automation. Omit to use the engine default.',
          },
          'delaySeconds': {
            'type': 'integer',
            'description':
                'Relative one-shot delay in seconds. Good for "in 2 minutes" tests.',
          },
          'delayMinutes': {
            'type': 'integer',
            'description': 'Relative one-shot delay in minutes.',
          },
          'atMs': {
            'type': 'integer',
            'description':
                'Absolute one-shot Unix epoch time in milliseconds, if already known.',
          },
          'localTime': {
            'type': 'object',
            'description':
                'Recurring local clock schedule, such as every day at 09:30 or weekdays at 18:00.',
            'properties': {
              'hour': {'type': 'integer', 'minimum': 0, 'maximum': 23},
              'minute': {'type': 'integer', 'minimum': 0, 'maximum': 59},
              'timezone': {
                'type': 'string',
                'description':
                    'IANA timezone such as Asia/Shanghai. Omit to use the phone timezone.',
              },
              'daysOfWeek': {
                'type': 'array',
                'items': {'type': 'integer', 'minimum': 1, 'maximum': 7},
                'description': 'Optional ISO weekdays: 1=Monday ... 7=Sunday.',
              },
            },
            'required': ['hour', 'minute'],
          },
          'exact': {
            'type': 'boolean',
            'description':
                'Ask Android for exact alarm scheduling when available. Default false.',
          },
        },
        'required': ['message'],
      },
    ),
    sdk.CustomToolDef(
      name: _listTool,
      description:
          'List mobile scheduled automations and their next run times.',
      effect: 'read',
      parameters: {
        'type': 'object',
        'properties': {
          'enabled': {'type': 'boolean'},
        },
      },
    ),
    sdk.CustomToolDef(
      name: _cancelTool,
      description:
          'Cancel/delete a scheduled automation by job id after the user asks to cancel it.',
      effect: 'write',
      parameters: {
        'type': 'object',
        'properties': {
          'jobId': {'type': 'string'},
        },
        'required': ['jobId'],
      },
    ),
    sdk.CustomToolDef(
      name: _syncTool,
      description:
          'Synchronize mobile automation wakes: drain pending platform wakes, catch up due jobs, and schedule the next Android wake.',
      effect: 'write',
      parameters: {
        'type': 'object',
        'properties': {
          'exact': {'type': 'boolean'},
        },
      },
    ),
    sdk.CustomToolDef(
      name: _a2aListAgentsTool,
      description:
          'List trusted nearby/paired device Agents available for local A2A collaboration. Use this whenever the user says nearby, paired, trusted device, another phone, iPhone, Android, other Agent, ask that Agent, say hello, send a message, discuss with, or delegate to a device Agent.',
      effect: 'read',
      parameters: {
        'type': 'object',
        'properties': {
          'includeUnavailable': {
            'type': 'boolean',
            'description':
                'Include peers that are trusted but missing an endpoint or shared secret.',
          },
        },
      },
    ),
    sdk.CustomToolDef(
      name: _a2aStartCollaborationTool,
      description:
          'Create a durable local A2A collaboration session with one or more trusted nearby Agents after a2a_list_agents returns an available target. Use before a2a_send_message, including simple greetings, questions, discussions, and delegation.',
      effect: 'write',
      parameters: {
        'type': 'object',
        'properties': {
          'goal': {
            'type': 'string',
            'description':
                'The user-facing goal this Agent collaboration should solve.',
          },
          'participants': {
            'type': 'array',
            'items': {'type': 'string'},
            'description':
                'Trusted peerIds, peerId prefixes, display names, or agentIds to invite.',
          },
          'mode': {
            'type': 'string',
            'enum': ['delegate', 'consult', 'debate', 'handoff', 'broadcast'],
            'description':
                'Collaboration style. Use consult/debate for discussion, delegate for a subtask.',
          },
          'autoAcceptLowRisk': {
            'type': 'boolean',
            'description':
                'Whether trusted peers may auto-run low-risk collaboration turns. Default true.',
          },
        },
        'required': ['goal', 'participants'],
      },
    ),
    sdk.CustomToolDef(
      name: _a2aSendMessageTool,
      description:
          'Send a message inside an existing local A2A collaboration session. Use this to actually greet, ask, notify, or discuss with another paired device Agent. Send success only proves delivery was attempted/sent; it is not a remote reply and not a discussion result. Use a2a_wait_messages after sending when expectsReply is true.',
      effect: 'deliver',
      parameters: {
        'type': 'object',
        'properties': {
          'sessionId': {'type': 'string'},
          'toPeerId': {
            'type': 'string',
            'description':
                'Optional peerId/prefix/display name. Omit to send to all participants.',
          },
          'message': {
            'type': 'string',
            'description': 'The message to the remote Agent.',
          },
          'intent': {
            'type': 'string',
            'enum': [
              'question',
              'answer',
              'proposal',
              'critique',
              'result',
              'clarification',
              'final_summary',
            ],
            'description': 'Why this message is being sent.',
          },
          'expectsReply': {
            'type': 'boolean',
            'description':
                'Set false for final summaries or notifications. Default true.',
          },
          'artifacts': {
            'type': 'array',
            'description':
                'Optional generic files or media to send with this Agent turn. Use artifacts returned by media_library, take_photo, or another authorized host/tool source; do not invent or reference unimported device-library assets.',
            'items': {
              'type': 'object',
              'properties': {
                'artifactId': {'type': 'string'},
                'mimeType': {'type': 'string'},
                'name': {'type': 'string'},
                'uri': {
                  'type': 'string',
                  'description':
                      'A sandbox path such as /workspace/... or a host/file URI reference.',
                },
                'text': {
                  'type': 'string',
                  'description': 'Extracted or inline text for this artifact.',
                },
                'dataBase64': {
                  'type': 'string',
                  'description':
                      'Small inline file bytes, base64 encoded. Prefer sandbox uri when available.',
                },
                'metadata': {'type': 'object'},
              },
            },
          },
          'attachRecentArtifacts': {
            'type': 'boolean',
            'description':
                'When true or omitted, attach recent media artifacts returned by media_library/take_photo in this same session if artifacts is empty. Set false only when intentionally sending text without those artifacts.',
          },
        },
        'required': ['sessionId', 'message'],
      },
    ),
    sdk.CustomToolDef(
      name: _a2aWaitMessagesTool,
      description:
          'Wait for new replies or results in a local A2A collaboration session. Use after sending a message when another Agent may respond or ask back. If it times out, report only that no reply has been received yet; do not infer the remote Agent opinion or close the discussion.',
      effect: 'read',
      parameters: {
        'type': 'object',
        'properties': {
          'sessionId': {'type': 'string'},
          'timeoutMs': {
            'type': 'integer',
            'minimum': 500,
            'maximum': 120000,
            'description': 'Maximum wait time. Default 30000.',
          },
          'sinceMs': {
            'type': 'integer',
            'description':
                'Only return tasks/messages updated after this Unix epoch millisecond.',
          },
        },
        'required': ['sessionId'],
      },
    ),
    sdk.CustomToolDef(
      name: _a2aFinishCollaborationTool,
      description:
          'Close a local A2A collaboration session and optionally notify participants with the final summary. Use only after a2a_wait_messages returned an actual remote reply/result, or when the user explicitly says not to wait for the other Agent.',
      effect: 'write',
      parameters: {
        'type': 'object',
        'properties': {
          'sessionId': {'type': 'string'},
          'summary': {'type': 'string'},
          'notifyParticipants': {
            'type': 'boolean',
            'description':
                'Send the final summary to participants. Default true.',
          },
        },
        'required': ['sessionId', 'summary'],
      },
    ),
  ];

  static const gitToolDefinitions = [
    sdk.CustomToolDef(
      name: _gitCloneTool,
      description:
          'Clone a Git repository into the mobile developer workspace. Use after the user asks to fetch, clone, or prepare a codebase. Public HTTPS and file:// URLs work without saved credentials; private repositories require scenario Git settings.',
      effect: 'write',
      parameters: {
        'type': 'object',
        'properties': {
          'url': {
            'type': 'string',
            'description':
                'Repository URL. Prefer HTTPS; file:// is allowed for local validation.',
          },
          'directory': {
            'type': 'string',
            'description':
                'Optional relative directory inside the Git workspace.',
          },
          'branch': {
            'type': 'string',
            'description': 'Optional branch, tag, or ref to checkout.',
          },
          'depth': {
            'type': 'integer',
            'minimum': 1,
            'description':
                'Optional shallow clone depth. Defaults to 1 for mobile-sized workspaces.',
          },
        },
        'required': ['url'],
      },
    ),
    sdk.CustomToolDef(
      name: _gitStatusTool,
      description:
          'Read Git status for a repository previously cloned into the mobile developer workspace.',
      effect: 'read',
      parameters: {
        'type': 'object',
        'properties': {
          'directory': {
            'type': 'string',
            'description':
                'Relative repository directory inside the Git workspace.',
          },
        },
        'required': ['directory'],
      },
    ),
    sdk.CustomToolDef(
      name: _gitDiffTool,
      description:
          'Read Git diff for a repository previously cloned into the mobile developer workspace.',
      effect: 'read',
      parameters: {
        'type': 'object',
        'properties': {
          'directory': {
            'type': 'string',
            'description':
                'Relative repository directory inside the Git workspace.',
          },
          'stat': {
            'type': 'boolean',
            'description': 'Return diff --stat instead of the full patch.',
          },
        },
        'required': ['directory'],
      },
    ),
    sdk.CustomToolDef(
      name: _gitListBranchesTool,
      description:
          'List local and remote branches for a repository in the mobile developer workspace. Use before switching branches or when the user asks what branches are available.',
      effect: 'read',
      parameters: {
        'type': 'object',
        'properties': {
          'directory': {
            'type': 'string',
            'description':
                'Relative repository directory inside the Git workspace.',
          },
        },
        'required': ['directory'],
      },
    ),
    sdk.CustomToolDef(
      name: _gitSwitchBranchTool,
      description:
          'Switch the current branch for a repository. The tool refuses to switch when the working tree has changes unless allowDirty is explicitly true. Remote branches create or update a local tracking branch when possible.',
      effect: 'write',
      parameters: {
        'type': 'object',
        'properties': {
          'directory': {
            'type': 'string',
            'description':
                'Relative repository directory inside the Git workspace.',
          },
          'branch': {
            'type': 'string',
            'description': 'Local branch name or remote branch ref.',
          },
          'remote': {
            'type': 'boolean',
            'description':
                'Set true when branch is a remote branch such as origin/main.',
          },
          'allowDirty': {
            'type': 'boolean',
            'description':
                'Allow switching with a dirty working tree. Default false.',
          },
        },
        'required': ['directory', 'branch'],
      },
    ),
    sdk.CustomToolDef(
      name: _gitListRemotesTool,
      description:
          'List configured Git remotes and their fetch/push URLs for a repository.',
      effect: 'read',
      parameters: {
        'type': 'object',
        'properties': {
          'directory': {
            'type': 'string',
            'description':
                'Relative repository directory inside the Git workspace.',
          },
        },
        'required': ['directory'],
      },
    ),
    sdk.CustomToolDef(
      name: _gitSetRemoteTool,
      description:
          'Add, update, or remove a Git remote. Use action=upsert with url to add/update, or action=remove to delete the remote.',
      effect: 'write',
      parameters: {
        'type': 'object',
        'properties': {
          'directory': {
            'type': 'string',
            'description':
                'Relative repository directory inside the Git workspace.',
          },
          'name': {
            'type': 'string',
            'description': 'Remote name such as origin.',
          },
          'url': {
            'type': 'string',
            'description':
                'Remote URL for action=upsert. HTTPS, SSH, git@host:path, and file:// URLs are accepted.',
          },
          'action': {
            'type': 'string',
            'enum': ['upsert', 'remove'],
            'description': 'Defaults to upsert.',
          },
        },
        'required': ['directory', 'name'],
      },
    ),
    sdk.CustomToolDef(
      name: _gitFetchTool,
      description:
          'Fetch Git refs from all remotes or a named remote for a repository. Defaults to --prune.',
      effect: 'write',
      parameters: {
        'type': 'object',
        'properties': {
          'directory': {
            'type': 'string',
            'description':
                'Relative repository directory inside the Git workspace.',
          },
          'remote': {
            'type': 'string',
            'description': 'Optional remote name such as origin.',
          },
          'prune': {
            'type': 'boolean',
            'description': 'Fetch with --prune. Default true.',
          },
        },
        'required': ['directory'],
      },
    ),
  ];

  static const androidProjectToolDefinitions = [
    sdk.CustomToolDef(
      name: _androidCreateProjectTool,
      description:
          'Create a Git-managed Android application project in the mobile developer workspace. Use this when the user asks to develop/build an app, game, tool, demo, or APK and they did not explicitly ask for HTML/H5/web. The tool creates an Android project, .mobile build profile, stable debug signing location, build script, and initial Git commit so the project appears in the Projects workbench.',
      effect: 'write',
      parameters: {
        'type': 'object',
        'properties': {
          'appName': {
            'type': 'string',
            'description': 'Human-readable Android app name.',
          },
          'directory': {
            'type': 'string',
            'description':
                'Optional relative project directory inside the developer workspace. Defaults to a slug from appName.',
          },
          'packageName': {
            'type': 'string',
            'description':
                'Optional Android applicationId/package, such as app.generated.pet. Generated from appName when omitted.',
          },
          'versionName': {
            'type': 'string',
            'description': 'Initial version name. Defaults to 0.1.0.',
          },
          'minSdk': {
            'type': 'integer',
            'description': 'Android minSdkVersion. Defaults to 21.',
          },
          'targetSdk': {
            'type': 'integer',
            'description': 'Android targetSdkVersion. Defaults to 33.',
          },
          'template': {
            'type': 'string',
            'enum': ['simple', 'canvas'],
            'description':
                'simple creates a basic Activity; canvas creates a drawable custom View for interactive visual apps. This is a project template, not a domain-specific game skill.',
          },
        },
        'required': ['appName'],
      },
    ),
    sdk.CustomToolDef(
      name: _androidBuildApkTool,
      description:
          'Build a previously created Android project into a signed APK. Reuses .mobile/debug.keystore for stable signing, updates version metadata, verifies the APK, records build history, and can open the Android installer. Use after creating or modifying an Android project.',
      effect: 'write',
      parameters: {
        'type': 'object',
        'properties': {
          'directory': {
            'type': 'string',
            'description':
                'Project directory as shown in the Projects workbench, for example git/my-app or my-app.',
          },
          'bumpVersionCode': {
            'type': 'boolean',
            'description':
                'Increment versionCode before building. Defaults to true.',
          },
          'versionName': {
            'type': 'string',
            'description': 'Optional versionName override before building.',
          },
          'install': {
            'type': 'boolean',
            'description':
                'Open Android package installer after a successful build. Defaults to false.',
          },
        },
        'required': ['directory'],
      },
    ),
  ];

  List<sdk.CustomToolDef> toolDefinitionsForSelection(
    sdk.NapaxiCapabilitySelection selection, {
    bool includeA2A = false,
  }) {
    final scenarioId = (selection.config['scenario_id'] as String? ?? '')
        .trim()
        .toLowerCase();
    final gitEnabled =
        scenarioId == _mobileDevelopmentScenarioId &&
        selection.enabledCapabilities.contains(gitCapabilityId) &&
        !selection.disabledCapabilities.contains(gitCapabilityId);
    return [
      ...toolDefinitions.where(
        (tool) => includeA2A || !_a2aToolNames.contains(tool.name),
      ),
      if (gitEnabled) ...gitToolDefinitions,
      if (gitEnabled) ...androidProjectToolDefinitions,
    ];
  }

  sdk.NapaxiEngine? _engine;
  NapaxiSdkChatClient? _owner;
  String? _defaultTimezone;
  sdk.SessionKey? _currentSession;
  String? _currentAgentId;
  final Map<String, List<_A2APendingArtifact>> _pendingArtifactsBySession = {};
  // Per-repo write serialization: concurrent stage/commit/discard/switch/fetch
  // on the same repo race for `.git/index.lock`. Mutating git ops are funneled
  // through a per-directory future chain so they run strictly in arrival order
  // (reads are left unserialized). The executor is a long-lived singleton, so
  // the chain persists across the per-call provider instances.
  final Map<String, Future<void>> _gitWriteChains = {};
  DemoScenarioRuntimeProfile _runtimeProfile = _scenarioRuntimeProfileFor(
    _generalScenarioId,
  );

  void attach(
    sdk.NapaxiEngine engine, {
    String? defaultTimezone,
    NapaxiSdkChatClient? owner,
  }) {
    _engine = engine;
    _owner = owner;
    _defaultTimezone = defaultTimezone;
  }

  void updateRuntimeProfile(DemoScenarioRuntimeProfile runtimeProfile) {
    _runtimeProfile = runtimeProfile;
  }

  void setCurrentSession(sdk.SessionKey session, {required String agentId}) {
    _currentSession = session;
    _currentAgentId = agentId.trim().isEmpty ? null : agentId.trim();
    _prunePendingArtifacts();
  }

  void detach() {
    _engine = null;
    _owner = null;
    _defaultTimezone = null;
    _currentSession = null;
    _currentAgentId = null;
    _pendingArtifactsBySession.clear();
    _runtimeProfile = _scenarioRuntimeProfileFor(_generalScenarioId);
  }

  void observeToolResult(sdk.McToolExecutionResult result) {
    if (result.isError || !_toolResultMayContainA2AArtifacts(result.toolName)) {
      return;
    }
    final artifacts = _a2aArtifactsFromToolResult(result.result);
    if (artifacts.isEmpty) return;
    final key = _artifactCacheKey();
    final now = DateTime.now().millisecondsSinceEpoch;
    final pending = _pendingArtifactsBySession.putIfAbsent(key, () => []);
    for (final artifact in artifacts) {
      final enrichedArtifact = _a2aArtifactWithLocalTransportContext(
        artifact,
        result,
      );
      if (_a2aArtifactIdentity(enrichedArtifact).isEmpty) continue;
      if (pending.any(
        (item) => _sameA2AArtifactForContext(item.artifact, enrichedArtifact),
      )) {
        continue;
      }
      pending.add(
        _A2APendingArtifact(
          artifact: enrichedArtifact,
          sourceTool: result.toolName,
          createdAtMs: now,
        ),
      );
    }
    if (pending.length > _a2aMaxArtifactsPerTurn) {
      pending.removeRange(0, pending.length - _a2aMaxArtifactsPerTurn);
    }
    _prunePendingArtifacts(nowMs: now);
  }

  sdk.A2AArtifact _a2aArtifactWithLocalTransportContext(
    sdk.A2AArtifact artifact,
    sdk.McToolExecutionResult result,
  ) {
    final metadata = Map<String, dynamic>.from(artifact.metadata);
    final context = result.context ?? const <String, dynamic>{};
    final workspaceFilesDir = _a2aStringField(context, [
      'workspace_files_dir',
      'workspaceFilesDir',
    ]);
    if (workspaceFilesDir.isNotEmpty) {
      metadata[_a2aLocalWorkspaceFilesDirMetadata] = workspaceFilesDir;
    }
    final accountId = _a2aStringField(context, ['account_id', 'accountId']);
    metadata[_a2aLocalAccountIdMetadata] = accountId.isNotEmpty
        ? accountId
        : _runtimeProfile.accountId;
    final agentId = _a2aStringField(context, ['agent_id', 'agentId']);
    metadata[_a2aLocalAgentIdMetadata] = agentId.isNotEmpty
        ? agentId
        : (_currentAgentId ?? _runtimeProfile.agentId);
    metadata[_a2aLocalSourceToolMetadata] = result.toolName;
    return _a2aArtifactWithMetadata(artifact, metadata);
  }

  bool _toolResultMayContainA2AArtifacts(String toolName) {
    return toolName == 'media_library' ||
        toolName == 'pick_media' ||
        toolName == 'take_photo' ||
        toolName == 'record_audio';
  }

  List<sdk.A2AArtifact> _a2aArtifactsFromToolResult(String resultJson) {
    try {
      final decoded = jsonDecode(resultJson);
      if (decoded is! Map) return const [];
      final map = Map<String, dynamic>.from(decoded);
      if (map['success'] == false || map['error'] != null) return const [];
      final artifacts = <sdk.A2AArtifact>[];
      void addArtifact(sdk.A2AArtifact? artifact) {
        if (artifact == null) return;
        if (_a2aArtifactIdentity(artifact).isEmpty) return;
        if (artifacts.any((item) => _sameA2AArtifact(item, artifact))) {
          return;
        }
        artifacts.add(artifact);
      }

      addArtifact(_a2aArtifactFromMap(map));
      for (final key in const ['artifacts', 'attachments']) {
        final value = map[key];
        if (value is! List) continue;
        for (final item in value.whereType<Map>()) {
          addArtifact(_a2aArtifactFromMap(Map<String, dynamic>.from(item)));
        }
      }
      return artifacts.take(_a2aMaxArtifactsPerTurn).toList(growable: false);
    } catch (_) {
      return const [];
    }
  }

  List<sdk.A2AArtifact> _pendingArtifactsForCurrentSession() {
    _prunePendingArtifacts();
    final pending = _pendingArtifactsBySession[_artifactCacheKey()];
    if (pending == null || pending.isEmpty) return const [];
    return pending
        .map((item) => item.artifact)
        .take(_a2aMaxArtifactsPerTurn)
        .toList(growable: false);
  }

  List<sdk.A2AArtifact> _enrichArtifactsFromPendingContext(
    List<sdk.A2AArtifact> artifacts,
  ) {
    if (artifacts.isEmpty) return artifacts;
    _prunePendingArtifacts();
    final pending = _pendingArtifactsBySession[_artifactCacheKey()];
    if (pending == null || pending.isEmpty) return artifacts;
    return artifacts
        .map((artifact) {
          _A2APendingArtifact? match;
          for (final item in pending) {
            if (_sameA2AArtifactForContext(item.artifact, artifact)) {
              match = item;
              break;
            }
          }
          if (match == null) return artifact;
          final metadata = Map<String, dynamic>.from(artifact.metadata);
          for (final key in _a2aLocalTransportMetadataKeys) {
            final value = match.artifact.metadata[key];
            if (value != null && value.toString().trim().isNotEmpty) {
              metadata[key] = value;
            }
          }
          return _a2aArtifactWithMetadata(artifact, metadata);
        })
        .take(_a2aMaxArtifactsPerTurn)
        .toList(growable: false);
  }

  List<Map<String, dynamic>> _a2aLocalDisplayArtifactJsonList(
    List<sdk.A2AArtifact> artifacts,
  ) => artifacts
      .map(
        (artifact) => _a2aArtifactWithMetadata(
          artifact,
          _a2aTransferableArtifactMetadata(artifact.metadata),
        ).toJson(),
      )
      .toList(growable: false);

  void _consumePendingArtifactsForCurrentSession(
    List<sdk.A2AArtifact> sentArtifacts,
  ) {
    if (sentArtifacts.isEmpty) return;
    final key = _artifactCacheKey();
    final pending = _pendingArtifactsBySession[key];
    if (pending == null || pending.isEmpty) return;
    pending.removeWhere(
      (item) => sentArtifacts.any(
        (sent) => _sameA2AArtifactForContext(item.artifact, sent),
      ),
    );
    if (pending.isEmpty) _pendingArtifactsBySession.remove(key);
  }

  String _artifactCacheKey() {
    final session = _currentSession;
    if (session != null) return session.toJson();
    return 'agent:${_runtimeProfile.accountId}:${_currentAgentId ?? _runtimeProfile.agentId}';
  }

  void _prunePendingArtifacts({int? nowMs}) {
    final now = nowMs ?? DateTime.now().millisecondsSinceEpoch;
    _pendingArtifactsBySession.removeWhere((_, pending) {
      pending.removeWhere(
        (item) => now - item.createdAtMs > _a2aPendingArtifactTtlMs,
      );
      return pending.isEmpty;
    });
  }

  bool _sameA2AArtifact(sdk.A2AArtifact a, sdk.A2AArtifact b) {
    final left = _a2aArtifactIdentity(a);
    final right = _a2aArtifactIdentity(b);
    return left.isNotEmpty && left == right;
  }

  bool _sameA2AArtifactForContext(sdk.A2AArtifact a, sdk.A2AArtifact b) {
    if (_sameA2AArtifact(a, b)) return true;
    final leftId = a.artifactId.trim();
    final rightId = b.artifactId.trim();
    if (leftId.isNotEmpty && leftId == rightId) return true;
    final leftSandbox = _a2aArtifactSandboxIdentity(a);
    final rightSandbox = _a2aArtifactSandboxIdentity(b);
    return leftSandbox.isNotEmpty && leftSandbox == rightSandbox;
  }

  String _a2aArtifactIdentity(sdk.A2AArtifact artifact) {
    final uri = artifact.uri?.trim() ?? '';
    if (uri.isNotEmpty) return 'uri:$uri';
    final sandbox = _a2aArtifactSandboxIdentity(artifact);
    if (sandbox.isNotEmpty) return 'uri:$sandbox';
    final id = artifact.artifactId.trim();
    if (id.isNotEmpty) return 'id:$id';
    return '';
  }

  String _a2aArtifactSandboxIdentity(sdk.A2AArtifact artifact) {
    final sandbox =
        artifact.metadata['sandbox_path']?.toString().trim() ??
        artifact.metadata['sandboxPath']?.toString().trim() ??
        '';
    return sandbox;
  }

  @override
  Future<String> execute(String toolName, String paramsJson) async {
    debugPrint('[napaxiToolTrace] execute tool=$toolName');
    final params = _decodeParams(paramsJson);
    return switch (toolName) {
      _createTool => _create(params),
      _listTool => _list(params),
      _cancelTool => _cancel(params),
      _syncTool => _sync(params),
      _gitCloneTool => _gitClone(params),
      _gitStatusTool => _gitStatus(params),
      _gitDiffTool => _gitDiff(params),
      _gitListBranchesTool => _gitListBranches(params),
      _gitSwitchBranchTool => _gitSwitchBranch(params),
      _gitListRemotesTool => _gitListRemotes(params),
      _gitSetRemoteTool => _gitSetRemote(params),
      _gitFetchTool => _gitFetch(params),
      _androidCreateProjectTool => _androidCreateProject(params),
      _androidBuildApkTool => _androidBuildApk(params),
      _a2aListAgentsTool => _a2aListAgents(params),
      _a2aStartCollaborationTool => _a2aStartCollaboration(params),
      _a2aSendMessageTool => _a2aSendMessage(params),
      _a2aWaitMessagesTool => _a2aWaitMessages(params),
      _a2aFinishCollaborationTool => _a2aFinishCollaboration(params),
      _ => jsonEncode({
        'success': false,
        'error': 'unsupported tool: $toolName',
      }),
    };
  }

  Future<String> _create(Map<String, dynamic> params) async {
    final engine = _requireEngine();
    final message = (params['message'] as String? ?? '').trim();
    if (message.isEmpty) {
      return jsonEncode({'success': false, 'error': 'message is required'});
    }

    final trigger = _triggerFromParams(params);
    if (trigger == null) {
      return jsonEncode({
        'success': false,
        'error':
            'A clear schedule is required. Provide delaySeconds, delayMinutes, atMs, or localTime.',
      });
    }

    final payloadKind = (params['payloadKind'] as String? ?? 'agentTurn')
        .trim()
        .toLowerCase();
    final currentSession = _currentSession;
    final payload = payloadKind == 'agentturn'
        ? sdk.AutomationPayload.agentTurn(
            message: message,
            sessionKeyJson: currentSession?.toJson(),
            sessionMode: currentSession == null ? 'isolated' : 'main',
            maxIterations: _int(params['maxIterations']),
          )
        : sdk.AutomationPayload.systemEvent(text: message);
    final name = (params['name'] as String? ?? '').trim();
    final job = engine.automation.createAutomationJob(
      sdk.AutomationJob(
        name: name.isEmpty ? _defaultJobName(message) : name,
        accountId: currentSession?.accountId ?? _runtimeProfile.accountId,
        agentId: _currentAgentId ?? _runtimeProfile.agentId,
        trigger: trigger,
        payload: payload,
      ),
    );
    final wake = await engine.automationScheduler?.rescheduleNextWake(
      exact: params['exact'] as bool? ?? false,
    );
    return jsonEncode({
      'success': true,
      'job': _jobJson(job),
      'scheduledWake': _wakeJson(wake),
      'platformWakeScheduled': wake != null,
    });
  }

  Future<String> _list(Map<String, dynamic> params) async {
    final engine = _requireEngine();
    final jobs = engine.automation.listAutomationJobs(
      enabled: params['enabled'] as bool?,
    );
    final status = await engine.automationScheduler?.status();
    return jsonEncode({
      'success': true,
      'jobs': jobs.map(_jobJson).toList(growable: false),
      'scheduler': {
        'supported': status?.supported ?? false,
        'platform': status?.platform,
        'pendingWakeCount': status?.pendingWakeCount ?? 0,
        'nextPendingWake': status?.nextPendingWake?.toJson(),
        'reason': status?.reason,
      },
    });
  }

  Future<String> _cancel(Map<String, dynamic> params) async {
    final engine = _requireEngine();
    final jobId = (params['jobId'] as String? ?? '').trim();
    if (jobId.isEmpty) {
      return jsonEncode({'success': false, 'error': 'jobId is required'});
    }
    final deleted = engine.automation.deleteAutomationJob(jobId);
    final wake = await engine.automationScheduler?.rescheduleNextWake();
    return jsonEncode({
      'success': deleted,
      'jobId': jobId,
      'scheduledWake': _wakeJson(wake),
    });
  }

  Future<String> _sync(Map<String, dynamic> params) async {
    final engine = _requireEngine();
    final sync = await engine.automationScheduler?.sync(
      exact: params['exact'] as bool? ?? false,
    );
    return jsonEncode({
      'success': sync != null,
      'runs': sync?.runs.map(_runJson).toList(growable: false) ?? const [],
      'scheduledWake': _wakeJson(sync?.scheduledWake),
      'platformWakeScheduled': sync?.platformWakeScheduled ?? false,
    });
  }

  Future<String> _a2aListAgents(Map<String, dynamic> params) async {
    final engine = _requireEngine();
    final includeUnavailable = params['includeUnavailable'] as bool? ?? false;
    final status = await engine.a2a.localTransportStatus();
    final connectivity = await _a2aConnectivityForToolRun(
      engine,
      status: status,
    );
    final peers = connectivity.peers
        .where((peer) => includeUnavailable || _a2aPeerAvailable(peer))
        .map((peer) => _a2aPeerToolJson(peer))
        .toList(growable: false);
    final collaborations = await _a2aLoadCollaborations();
    final displayText = peers.isEmpty
        ? _a2aNoVerifiedChannelDisplayText(connectivity)
        : '';
    return jsonEncode({
      'success': true,
      'displayText': displayText,
      'assistantInstruction': peers.isEmpty
          ? 'Use displayText for the user-facing answer. Do not say the remote Agent is offline unless this result explicitly says offline.'
          : 'This is discovery evidence only. If the user asked to talk, greet, ask, discuss with, or delegate to a nearby Agent, continue with a2a_start_collaboration, a2a_send_message, and a2a_wait_messages instead of answering with a discovered-agent count. Only describe the list when the user explicitly asked to list nearby Agents.',
      'local': {
        'running': status.running,
        'supported': status.supported,
        'reason': status.reason,
        'lastError': status.lastError,
      },
      'agents': peers,
      'reachability': connectivity.summaryJson(),
      'activeCollaborations': collaborations
          .where((item) => item['status'] != 'closed')
          .map((item) => _a2aCollaborationPublicJson(item))
          .toList(growable: false),
    });
  }

  Future<String> _a2aStartCollaboration(Map<String, dynamic> params) async {
    final goal = (params['goal'] as String? ?? '').trim();
    if (goal.isEmpty) {
      return jsonEncode({'success': false, 'error': 'goal is required'});
    }
    final requested = _stringList(params['participants']);
    if (requested.isEmpty) {
      return jsonEncode({
        'success': false,
        'error': 'participants must include at least one trusted peer',
      });
    }
    final engine = _requireEngine();
    final status = await _a2aEnsureLocalTransport(engine);
    if (!status.supported || !status.running) {
      return jsonEncode({
        'success': false,
        'error': status.reason.isEmpty
            ? (status.lastError.trim().isEmpty
                  ? 'local A2A transport is not running'
                  : status.lastError)
            : status.reason,
        'status': {'supported': status.supported, 'running': status.running},
      });
    }

    final connectivity = await _a2aConnectivityForToolRun(
      engine,
      status: status,
    );
    final availablePeers = connectivity.peers;
    final peers = <sdk.A2APeer>[];
    final unresolved = <String>[];
    for (final value in requested) {
      final peer = _a2aResolvePeer(value, availablePeers);
      if (peer == null || !_a2aPeerAvailable(peer)) {
        unresolved.add(value);
      } else if (!peers.any((item) => item.peerId == peer.peerId)) {
        peers.add(peer);
      }
    }
    if (peers.isEmpty) {
      final displayText = _a2aNoVerifiedChannelDisplayText(connectivity);
      return jsonEncode({
        'success': false,
        'code': 'a2a_no_verified_channel',
        'error': displayText,
        'displayText': displayText,
        'assistantInstruction':
            'Tell the user this displayText. Do not say the target Agent is offline.',
        'unresolved': unresolved,
        'reachability': connectivity.summaryJson(),
      });
    }

    final now = DateTime.now().toUtc();
    final sessionId = _newA2ACollaborationId();
    final mode = (params['mode'] as String? ?? 'consult').trim().isEmpty
        ? 'consult'
        : (params['mode'] as String).trim();
    final safetyBudget = (_int(params['safetyBudget']) ?? 12).clamp(1, 24);
    final collaboration = <String, dynamic>{
      'sessionId': sessionId,
      'goal': goal,
      'mode': mode,
      'status': 'active',
      'leaderPeerId': status.peerId,
      'leaderAgentId': _currentAgentId ?? _runtimeProfile.agentId,
      'safetyBudget': safetyBudget,
      'exchangeCount': 0,
      'autoAcceptLowRisk': params['autoAcceptLowRisk'] as bool? ?? true,
      'participants': peers
          .map(_a2aPeerParticipantJson)
          .toList(growable: false),
      'createdAt': now.toIso8601String(),
      'updatedAt': now.toIso8601String(),
    };
    await _a2aUpsertCollaboration(collaboration);
    return jsonEncode({
      'success': true,
      'collaboration': _a2aCollaborationPublicJson(collaboration),
      'unresolved': unresolved,
      'next':
          'Use $_a2aSendMessageTool with this sessionId. Use $_a2aWaitMessagesTool after sending when you expect a reply. Continue only when the observed remote reply leaves the goal unresolved.',
    });
  }

  Future<String> _a2aSendMessage(Map<String, dynamic> params) async {
    final sessionId = (params['sessionId'] as String? ?? '').trim();
    final message = (params['message'] as String? ?? '').trim();
    if (sessionId.isEmpty || message.isEmpty) {
      return jsonEncode({
        'success': false,
        'error': 'sessionId and message are required',
      });
    }
    final engine = _requireEngine();
    final owner = _owner;
    if (owner == null) {
      return jsonEncode({
        'success': false,
        'error': 'local A2A runtime is not attached',
      });
    }
    final explicitArtifacts = _enrichArtifactsFromPendingContext(
      _a2aArtifactsFromParam(params['artifacts']),
    );
    final attachRecentArtifacts =
        params['attachRecentArtifacts'] as bool? ?? true;
    final autoAttachedArtifacts =
        explicitArtifacts.isEmpty && attachRecentArtifacts
        ? _pendingArtifactsForCurrentSession()
        : const <sdk.A2AArtifact>[];
    final requestedArtifacts = explicitArtifacts.isNotEmpty
        ? explicitArtifacts
        : autoAttachedArtifacts;
    final status = await _a2aEnsureLocalTransport(engine);
    if (!status.supported || !status.running) {
      return jsonEncode({
        'success': false,
        'error': status.reason.isEmpty
            ? (status.lastError.trim().isEmpty
                  ? 'local A2A transport is not running'
                  : status.lastError)
            : status.reason,
      });
    }
    final collaboration = await _a2aCollaborationForSend(
      sessionId,
      params,
      status,
    );
    final connectivity = await _a2aConnectivityForToolRun(
      engine,
      status: status,
    );
    final targets = _a2aTargetsForSend(
      connectivity.peers,
      collaboration,
      params['toPeerId'] as String?,
    );
    if (targets.isEmpty) {
      final displayText = _a2aNoVerifiedChannelDisplayText(connectivity);
      return jsonEncode({
        'success': false,
        'code': 'a2a_no_verified_channel',
        'error': displayText,
        'displayText': displayText,
        'assistantInstruction':
            'Tell the user this displayText. Do not say the target Agent is offline.',
        'reachability': connectivity.summaryJson(),
      });
    }

    final intent = (params['intent'] as String? ?? 'proposal').trim();
    final expectsReply = params['expectsReply'] as bool? ?? true;
    final exchangeCount =
        ((_int(collaboration['exchangeCount']) ??
                    _int(collaboration['round']) ??
                    0) +
                1)
            .clamp(1, 9999);
    final sendStartedAtMs = DateTime.now().toUtc().millisecondsSinceEpoch;
    collaboration['exchangeCount'] = exchangeCount;
    collaboration['lastSentAtMs'] = sendStartedAtMs;
    collaboration['updatedAt'] = DateTime.now().toUtc().toIso8601String();
    await _a2aUpsertCollaboration(collaboration);

    final deliveries = <Map<String, dynamic>>[];
    final sentMessages = <Map<String, dynamic>>[];
    var sentWithAutoAttachedArtifacts = false;
    var sentWithRequestedArtifacts = false;
    for (final peer in targets) {
      final endpoint = _a2aEndpoint(peer);
      if (endpoint == null) {
        deliveries.add({
          'displayLabel': _a2aPeerDisplayLabel(peer),
          'success': false,
          'displayText': '发送给 ${_a2aPeerDisplayLabel(peer)} 失败',
        });
        continue;
      }
      try {
        final transportArtifacts = await owner._prepareLocalA2AArtifactsForPeer(
          artifacts: requestedArtifacts,
          engine: engine,
          peer: peer,
          endpoint: endpoint,
          localPeerId: status.peerId,
        );
        if (!transportArtifacts.ok) {
          deliveries.add({
            'displayLabel': _a2aPeerDisplayLabel(peer),
            'success': false,
            'code': 'a2a_artifact_not_portable',
            'issues': transportArtifacts.issues,
            'displayText': '发送给 ${_a2aPeerDisplayLabel(peer)} 失败',
          });
          continue;
        }
        final artifacts = transportArtifacts.artifacts;
        final peerSession = engine.a2a.openPeerSession(
          peer,
          transport: endpoint.transport,
          endpoint: endpoint.uri,
          localPeerId: status.peerId,
        );
        final taskId = _newA2ATaskId(sessionId);
        final conversationHistory = _a2aConversationHistoryForPrompt(
          sessionId,
          localLabel: 'Other Agent',
          remoteLabel: 'You',
        );
        final task = engine.a2a.createTaskMessage(
          peerSession.sessionId,
          _a2aCollaborationPrompt(
            collaboration: collaboration,
            message: message,
            intent: intent,
            expectsReply: expectsReply,
            artifacts: artifacts,
            conversationHistory: conversationHistory,
          ),
          options: {
            'taskId': taskId,
            'riskHint': 'low',
            if (artifacts.isNotEmpty)
              'artifacts': _a2aArtifactJsonList(artifacts),
            if (artifacts.isNotEmpty) 'requestedOutputModes': ['text/plain'],
            'context': _a2aCollaborationContext(
              collaboration: collaboration,
              turnId: taskId,
              fromPeerId: status.peerId,
              toPeerId: peer.peerId,
              message: message,
              intent: intent,
              expectsReply: expectsReply,
              artifacts: artifacts,
              conversationHistory: conversationHistory,
            ),
          },
        );
        final delivery = await _a2aSendPeerMessageWithEndpointFallback(
          engine: engine,
          peer: peer,
          message: task,
          endpoint: endpoint,
        );
        if (delivery['success'] == true) {
          if (requestedArtifacts.isNotEmpty) {
            sentWithRequestedArtifacts = true;
          }
          if (autoAttachedArtifacts.isNotEmpty) {
            sentWithAutoAttachedArtifacts = true;
          }
          sentMessages.add({
            'displayLabel': '我',
            'text': message,
            'toDisplayLabel': _a2aPeerDisplayLabel(peer),
            'intent': intent,
            'createdAtMs': sendStartedAtMs,
            if (artifacts.isNotEmpty)
              'artifacts': _a2aArtifactSummaryList(artifacts),
            if (requestedArtifacts.isNotEmpty)
              'visibleArtifacts': _a2aLocalDisplayArtifactJsonList(
                requestedArtifacts,
              ),
          });
        }
        deliveries.add({
          'displayLabel': _a2aPeerDisplayLabel(peer),
          'success': delivery['success'],
          'intent': intent,
          if (artifacts.isNotEmpty) 'artifactCount': artifacts.length,
          'deliveryStatus': delivery['success'] == true ? 'sent' : 'failed',
          if (delivery['success'] != true)
            'displayText': '发送给 ${_a2aPeerDisplayLabel(peer)} 失败',
        });
      } catch (error) {
        deliveries.add({
          'displayLabel': _a2aPeerDisplayLabel(peer),
          'success': false,
          'displayText': '发送给 ${_a2aPeerDisplayLabel(peer)} 失败',
        });
      }
    }
    if (sentWithRequestedArtifacts) {
      _consumePendingArtifactsForCurrentSession(requestedArtifacts);
    }
    return jsonEncode({
      'success': deliveries.any((item) => item['success'] == true),
      'collaboration': _a2aCollaborationPublicJson(collaboration),
      'deliveries': deliveries,
      'sentMessages': sentMessages,
      'artifactHandoff': {
        'explicitArtifactCount': explicitArtifacts.length,
        'autoAttachedArtifactCount': autoAttachedArtifacts.length,
        'sentWithAutoAttachedArtifacts': sentWithAutoAttachedArtifacts,
      },
      'displayText': deliveries.any((item) => item['success'] == true)
          ? ''
          : '消息未送达。',
      'assistantInstruction': expectsReply
          ? 'This is transport evidence only. Do not show a "sent" status to the user and do not answer from send success alone. Call a2a_wait_messages next, then decide from the observed remote reply whether to continue or summarize.'
          : 'This message did not request a reply. You may answer briefly if the user needs confirmation, but do not expose transport identifiers.',
      'reachability': connectivity.summaryJson(),
    });
  }

  Future<String> _a2aWaitMessages(Map<String, dynamic> params) async {
    final sessionId = (params['sessionId'] as String? ?? '').trim();
    if (sessionId.isEmpty) {
      return jsonEncode({'success': false, 'error': 'sessionId is required'});
    }
    final timeoutMs = (_int(params['timeoutMs']) ?? 30000).clamp(500, 120000);
    final collaboration = await _a2aLoadCollaboration(sessionId);
    final sinceMs =
        _int(params['sinceMs']) ?? _int(collaboration?['lastSentAtMs']);
    final includeProgress = params['includeProgress'] as bool? ?? false;
    final startedAt = DateTime.now();
    List<Map<String, dynamic>> observations = const [];
    while (DateTime.now().difference(startedAt).inMilliseconds <= timeoutMs) {
      observations = await _a2aCollaborationObservations(
        sessionId,
        sinceMs: sinceMs,
        includeProgress: includeProgress,
      );
      if (observations.isNotEmpty) break;
      await Future<void>.delayed(const Duration(milliseconds: 800));
    }
    final messages = observations
        .map(_a2aObservationMessageJson)
        .whereType<Map<String, dynamic>>()
        .toList(growable: false);
    final openQuestionCount = messages
        .where((message) => message['requiresResponse'] == true)
        .length;
    final maxObservedAtMs = observations
        .map((item) => item['updatedAtMs'])
        .whereType<int>()
        .fold<int?>(
          null,
          (best, value) => best == null || value > best ? value : best,
        );
    if (collaboration != null && maxObservedAtMs != null) {
      collaboration['lastObservedAtMs'] = maxObservedAtMs;
      collaboration['updatedAt'] = DateTime.now().toUtc().toIso8601String();
      await _a2aUpsertCollaboration(collaboration);
    }
    final mode = collaboration?['mode']?.toString().trim().toLowerCase() ?? '';
    final status =
        collaboration?['status']?.toString().trim().toLowerCase() ?? '';
    final discussionMode = mode == 'consult' || mode == 'debate';
    final safetyBudget = (_int(collaboration?['safetyBudget']) ?? 12).clamp(
      1,
      24,
    );
    final exchangeCount = (_int(collaboration?['exchangeCount']) ?? 0).clamp(
      0,
      9999,
    );
    final withinSafetyBudget = exchangeCount < safetyBudget;
    final finalSummaryCount = messages
        .where((message) => message['speechAct'] == 'final_summary')
        .length;
    final conversationOpen =
        observations.isNotEmpty &&
        status != 'closed' &&
        withinSafetyBudget &&
        finalSummaryCount == 0 &&
        (discussionMode || openQuestionCount > 0);
    return jsonEncode({
      'success': observations.isNotEmpty,
      'timedOut': observations.isEmpty,
      'noRemoteReply': observations.isEmpty,
      'mustNotSpeculate': observations.isEmpty,
      'waitedMs': DateTime.now().difference(startedAt).inMilliseconds,
      'messages': messages,
      'messageCount': messages.length,
      'openQuestionCount': openQuestionCount,
      'conversationNeedsResponse': openQuestionCount > 0,
      'conversationOpen': conversationOpen,
      'collaboration': collaboration == null
          ? null
          : _a2aCollaborationPublicJson(collaboration),
      'displayText': observations.isEmpty ? '目前还没有收到对方 Agent 的回复。' : '',
      'assistantInstruction': observations.isEmpty
          ? 'Final answer must be exactly the displayText. Do not add any guess, reason, personality, advice, remote Agent opinion, "busy/offline/silent" wording, or discussion conclusion.'
          : 'Use messages[].text as private collaboration evidence for your next decision. Do not answer with a generic sent/received/status update, and do not echo the remote turn just because it arrived; the dedicated nearby-Agent conversation already shows the transcript. If any message has requiresResponse=true, answer that Agent with a2a_send_message and then call a2a_wait_messages again unless the user explicitly asked not to continue. If the result says the conversation is still open but no message requires response, decide from the user goal and observed dialogue whether another focused A2A turn is useful before synthesizing a conclusion. If the remote Agent asked a question, requested clarification, challenged an assumption, or gave an incomplete answer, respond with a2a_send_message and then call a2a_wait_messages again. Only synthesize a concise conclusion for the user when the observed conversation actually resolves the user goal. Do not expose sessionId, taskId, peerId, messageId, endpoint, transport, or other protocol fields unless the user asks for diagnostics.',
      'next': observations.isEmpty
          ? 'You may wait again or ask the user whether to retry; do not close the discussion as completed.'
          : discussionMode
          ? 'If one reply is not enough, send another focused A2A message and wait again.'
          : 'You may now summarize the result for the user if the goal is resolved.',
    });
  }

  Future<String> _a2aFinishCollaboration(Map<String, dynamic> params) async {
    final sessionId = (params['sessionId'] as String? ?? '').trim();
    final summary = (params['summary'] as String? ?? '').trim();
    if (sessionId.isEmpty || summary.isEmpty) {
      return jsonEncode({
        'success': false,
        'error': 'sessionId and summary are required',
      });
    }
    final collaboration = await _a2aLoadCollaboration(sessionId);
    if (collaboration == null) {
      return jsonEncode({
        'success': false,
        'error': 'collaboration session not found',
      });
    }
    collaboration['status'] = 'closed';
    collaboration['summary'] = summary;
    collaboration['updatedAt'] = DateTime.now().toUtc().toIso8601String();
    await _a2aUpsertCollaboration(collaboration);
    Map<String, dynamic>? notification;
    if (params['notifyParticipants'] as bool? ?? true) {
      final raw = await _a2aSendMessage({
        'sessionId': sessionId,
        'message': summary,
        'intent': 'final_summary',
        'expectsReply': false,
      });
      notification = jsonDecode(raw) as Map<String, dynamic>;
    }
    return jsonEncode({
      'success': true,
      'collaboration': _a2aCollaborationPublicJson(collaboration),
      'notification': notification,
    });
  }

  Future<String> _gitClone(Map<String, dynamic> params) async {
    return jsonEncode(await (await _gitProvider()).clone(params));
  }

  Future<String> _gitStatus(Map<String, dynamic> params) async {
    return jsonEncode(await (await _gitProvider()).status(params));
  }

  Future<String> _gitDiff(Map<String, dynamic> params) async {
    return jsonEncode(await (await _gitProvider()).diff(params));
  }

  Future<String> _gitListBranches(Map<String, dynamic> params) async {
    return jsonEncode(await (await _gitProvider()).listBranches(params));
  }

  Future<String> _gitSwitchBranch(Map<String, dynamic> params) async {
    return jsonEncode(await (await _gitProvider()).switchBranch(params));
  }

  Future<String> _gitListRemotes(Map<String, dynamic> params) async {
    return jsonEncode(await (await _gitProvider()).listRemotes(params));
  }

  Future<String> _gitSetRemote(Map<String, dynamic> params) async {
    return jsonEncode(await (await _gitProvider()).setRemote(params));
  }

  Future<String> _gitFetch(Map<String, dynamic> params) async {
    return jsonEncode(await (await _gitProvider()).fetch(params));
  }

  Future<String> _androidCreateProject(Map<String, dynamic> params) async {
    final appName = (params['appName'] as String? ?? '').trim();
    if (appName.isEmpty) {
      return jsonEncode({'success': false, 'error': 'appName is required'});
    }
    final requestedDirectory = (params['directory'] as String? ?? '').trim();
    final directory =
        _safeAndroidProjectDirectory(
          requestedDirectory.isEmpty
              ? _slugFromText(appName)
              : requestedDirectory,
        ) ??
        '';
    if (directory.isEmpty) {
      return jsonEncode({
        'success': false,
        'error':
            'directory must be a relative path inside the project workspace',
      });
    }
    final packageName = _validAndroidPackageName(
      (params['packageName'] as String? ?? '').trim(),
      fallbackName: appName,
    );
    final minSdk = (_int(params['minSdk']) ?? 21).clamp(21, 33).toInt();
    final targetSdk = (_int(params['targetSdk']) ?? 33)
        .clamp(minSdk, 35)
        .toInt();
    final versionName = (params['versionName'] as String? ?? '').trim().isEmpty
        ? '0.1.0'
        : (params['versionName'] as String).trim();
    final template = (params['template'] as String? ?? 'simple').trim();
    final workspace = await _gitWorkspaceDirectory();
    await workspace.create(recursive: true);
    final projectDir = Directory('${workspace.path}/$directory');
    if (await projectDir.exists() && !await projectDir.list().isEmpty) {
      return jsonEncode({
        'success': false,
        'error': 'project directory is not empty',
        'directory': directory,
        'path': projectDir.path,
      });
    }
    await _writeAndroidProjectTemplate(
      projectDir: projectDir,
      directory: directory,
      appName: appName,
      packageName: packageName,
      versionName: versionName,
      minSdk: minSdk,
      targetSdk: targetSdk,
      template: template == 'canvas' ? 'canvas' : 'simple',
    );
    final git = await (await _gitProvider()).initRepository(
      directory: directory,
      commitMessage: 'Initial Android project',
    );
    return jsonEncode({
      'success': git['success'] as bool? ?? false,
      'tool': _androidCreateProjectTool,
      'name': appName,
      'directory': directory,
      'projectDirectory': 'git/$directory',
      'path': projectDir.path,
      'packageName': packageName,
      'versionCode': 1,
      'versionName': versionName,
      'git': git,
      if (!(git['success'] as bool? ?? false))
        'error':
            git['error'] ?? 'project created but Git initialization failed',
    });
  }

  Future<String> _androidBuildApk(Map<String, dynamic> params) async {
    final repo = await _resolveRepositoryRoot(
      (params['directory'] as String? ?? '').trim(),
    );
    if (repo == null) {
      return jsonEncode({
        'success': false,
        'error': 'project directory is invalid',
      });
    }
    final profileFile = File(
      '${repo.directory.path}/.mobile/build-profile.json',
    );
    if (!await profileFile.exists()) {
      return jsonEncode({
        'success': false,
        'error':
            'Android build profile is missing. Create the project with android_create_project first.',
        'directory': repo.id,
      });
    }
    final profile = await _loadJsonFile(profileFile);
    final originalProfile = Map<String, dynamic>.from(profile);
    final manifestFile = File('${repo.directory.path}/AndroidManifest.xml');
    final originalManifest = await manifestFile.exists()
        ? await manifestFile.readAsString()
        : null;
    final versionCode =
        (_int(profile['versionCode']) ?? 1) +
        ((params['bumpVersionCode'] as bool? ?? true) ? 1 : 0);
    final versionName = (params['versionName'] as String? ?? '').trim().isEmpty
        ? (profile['versionName'] as String? ?? '0.1.0')
        : (params['versionName'] as String).trim();
    profile['versionCode'] = versionCode;
    profile['versionName'] = versionName;
    profile['updatedAt'] = DateTime.now().toUtc().toIso8601String();
    await _writeJsonFile(profileFile, profile);
    await _writeAndroidManifestFromProfile(repo.directory, profile);

    const command = 'chmod +x build.sh && bash build.sh';
    final build = await _runAndroidProjectShell(
      repo.directory,
      command,
      timeout: const Duration(minutes: 6),
    );
    final apkPath = '${repo.directory.path}/build/app.apk';
    final apkFile = File(apkPath);
    final buildSuccess = build['exitCode'] == 0 && await apkFile.exists();
    if (!buildSuccess) {
      await _writeJsonFile(profileFile, originalProfile);
      if (originalManifest == null) {
        if (await manifestFile.exists()) await manifestFile.delete();
      } else {
        await manifestFile.writeAsString(originalManifest);
      }
    }
    Map<String, dynamic>? installResult;
    if (buildSuccess && (params['install'] as bool? ?? false)) {
      final install = await sdk.NapaxiApkInstaller.installApk(apkPath);
      installResult = install.toMap();
    }
    if (buildSuccess) {
      await _appendAndroidBuildHistory(
        repo.directory,
        profile: profile,
        apkPath: apkPath,
        installed: installResult,
      );
    }
    final response = <String, dynamic>{
      ...build,
      'success': buildSuccess,
      'tool': _androidBuildApkTool,
      'directory': repo.id,
      'path': repo.directory.path,
      'packageName': profile['applicationId'],
      'versionCode': versionCode,
      'versionName': versionName,
      'apkPath': apkPath,
    };
    if (installResult != null) response['install'] = installResult;
    if (!buildSuccess) {
      response['error'] = build['error'] ?? 'Android APK build failed';
    }
    return jsonEncode(response);
  }

  Future<List<DemoRepositoryInfo>> listGitRepositories() async {
    final roots = await _discoverRepositoryRoots();
    final repositories = <DemoRepositoryInfo>[];
    for (final root in roots) {
      final name = _pathName(root.directory.path);
      repositories.add(
        DemoRepositoryInfo(
          name: name,
          directory: root.id,
          displayDirectory: root.displayRelativePath,
          absolutePath: root.directory.path,
          modified: await _entityModified(root.directory),
          locationLabel: root.sourceLabel,
        ),
      );
    }
    repositories.sort(
      (a, b) => b.modified.compareTo(a.modified) == 0
          ? a.name.toLowerCase().compareTo(b.name.toLowerCase())
          : b.modified.compareTo(a.modified),
    );
    return List.unmodifiable(repositories);
  }

  Future<DemoGitRepositoryStatus> gitRepositoryStatus(String directory) async {
    final repo = await _resolveRepositoryRoot(directory);
    if (repo == null) {
      return const DemoGitRepositoryStatus(
        success: false,
        branch: '',
        changedFiles: [],
        error: 'repository directory is invalid',
      );
    }
    final raw = await _gitProviderForRoot(
      repo,
    ).statusDirectory(repo.directory, relativePath: repo.relativePath);
    final stdout = raw['stdout'] as String? ?? '';
    final changedFiles = <String>[];
    var branch = '';
    var detached = false;
    var noCommits = false;
    for (final line in stdout.split('\n')) {
      final trimmed = line.trimRight();
      if (trimmed.isEmpty) continue;
      if (trimmed.startsWith('## ')) {
        final parsed = DemoGitProvider.parseBranchLine(trimmed.substring(3));
        branch = parsed['branch'] as String? ?? '';
        detached = parsed['detached'] as bool? ?? false;
        noCommits = parsed['noCommits'] as bool? ?? false;
        continue;
      }
      final path = trimmed.length > 3 ? trimmed.substring(3).trim() : trimmed;
      if (path.isNotEmpty) changedFiles.add(path);
    }
    return DemoGitRepositoryStatus(
      success: raw['success'] as bool? ?? false,
      branch: branch,
      detached: detached,
      noCommits: noCommits,
      changedFiles: List.unmodifiable(changedFiles),
      error: raw['error'] as String?,
    );
  }

  Future<DemoGitChangeSet> gitChanges(String directory) async {
    final repo = await _resolveRepositoryRoot(directory);
    if (repo == null) {
      return const DemoGitChangeSet(
        success: false,
        error: 'repository directory is invalid',
      );
    }
    final raw = await _gitProviderForRoot(repo).changes({
      'directory': repo.relativePath,
      'absolutePath': repo.directory.path,
    });
    if (raw['success'] != true) {
      return DemoGitChangeSet(
        success: false,
        error: (raw['error'] as String?)?.trim(),
      );
    }
    final entries = raw['entries'];
    return DemoGitChangeSet(
      success: true,
      branch: (raw['branch'] as String? ?? '').trim(),
      detached: raw['detached'] as bool? ?? false,
      noCommits: raw['noCommits'] as bool? ?? false,
      entries: entries is List
          ? List.unmodifiable(
              [
                for (final entry in entries)
                  if (entry is Map) _gitChangeEntry(entry),
              ].whereType<DemoGitChangeEntry>(),
            )
          : const [],
    );
  }

  static DemoGitChangeEntry? _gitChangeEntry(Map<dynamic, dynamic> raw) {
    final path = (raw['path'] as String? ?? '').trim();
    if (path.isEmpty) return null;
    final indexCode = (raw['indexCode'] as String? ?? ' ').trim();
    final workCode = (raw['workCode'] as String? ?? ' ').trim();
    return DemoGitChangeEntry(
      path: path,
      indexCode: indexCode.isEmpty ? ' ' : indexCode,
      workCode: workCode.isEmpty ? ' ' : workCode,
      area: _changeArea(raw['area']),
      category: _changeCategory(raw['category']),
      additions: raw['additions'] is int ? raw['additions'] as int : null,
      deletions: raw['deletions'] is int ? raw['deletions'] as int : null,
      oldPath: (raw['oldPath'] as String?)?.trim().isEmpty == true
          ? null
          : (raw['oldPath'] as String?)?.trim(),
    );
  }

  static DemoGitChangeArea _changeArea(Object? value) {
    switch (value) {
      case 'staged':
        return DemoGitChangeArea.staged;
      case 'untracked':
        return DemoGitChangeArea.untracked;
      default:
        return DemoGitChangeArea.unstaged;
    }
  }

  static DemoGitChangeCategory _changeCategory(Object? value) {
    switch (value) {
      case 'added':
        return DemoGitChangeCategory.added;
      case 'deleted':
        return DemoGitChangeCategory.deleted;
      case 'renamed':
        return DemoGitChangeCategory.renamed;
      case 'unmerged':
        return DemoGitChangeCategory.unmerged;
      case 'untracked':
        return DemoGitChangeCategory.untracked;
      default:
        return DemoGitChangeCategory.modified;
    }
  }

  /// Runs a mutating git operation under per-repo serialization, keyed by the
  /// resolved repository's on-disk directory. See [_gitWriteChains].
  Future<T> _runGitWrite<T>(
    _ResolvedRepositoryRoot repo,
    Future<T> Function() op,
  ) {
    final key = repo.directory.path;
    final previous = _gitWriteChains[key] ?? Future<void>.value();
    final result = previous.then((_) => op());
    // Keep the chain alive even if the op throws, so a failure doesn't poison
    // subsequent ops on the same repo.
    _gitWriteChains[key] = result.then((_) {}, onError: (_) {});
    return result;
  }

  Future<DemoGitOperationResult> stageGitPaths(
    String directory,
    List<String> paths,
  ) async {
    final repo = await _resolveRepositoryRoot(directory);
    if (repo == null) {
      return const DemoGitOperationResult(
        success: false,
        error: 'repository directory is invalid',
      );
    }
    final raw = await _runGitWrite(
      repo,
      () => _gitProviderForRoot(repo).stage({
        'directory': repo.relativePath,
        'absolutePath': repo.directory.path,
        'paths': List<String>.unmodifiable(paths),
      }),
    );
    return _gitOperationResult(raw);
  }

  Future<DemoGitOperationResult> unstageGitPaths(
    String directory,
    List<String> paths,
  ) async {
    final repo = await _resolveRepositoryRoot(directory);
    if (repo == null) {
      return const DemoGitOperationResult(
        success: false,
        error: 'repository directory is invalid',
      );
    }
    final raw = await _runGitWrite(
      repo,
      () => _gitProviderForRoot(repo).unstage({
        'directory': repo.relativePath,
        'absolutePath': repo.directory.path,
        'paths': List<String>.unmodifiable(paths),
      }),
    );
    return _gitOperationResult(raw);
  }

  Future<DemoGitOperationResult> discardGitPaths(
    String directory,
    List<String> paths,
  ) async {
    final repo = await _resolveRepositoryRoot(directory);
    if (repo == null) {
      return const DemoGitOperationResult(
        success: false,
        error: 'repository directory is invalid',
      );
    }
    final raw = await _runGitWrite(
      repo,
      () => _gitProviderForRoot(repo).discard({
        'directory': repo.relativePath,
        'absolutePath': repo.directory.path,
        'paths': List<String>.unmodifiable(paths),
      }),
    );
    return _gitOperationResult(raw);
  }

  Future<DemoGitOperationResult> commitGit(
    String directory,
    String message,
  ) async {
    final repo = await _resolveRepositoryRoot(directory);
    if (repo == null) {
      return const DemoGitOperationResult(
        success: false,
        error: 'repository directory is invalid',
      );
    }
    final raw = await _runGitWrite(
      repo,
      () => _gitProviderForRoot(repo).commit({
        'directory': repo.relativePath,
        'absolutePath': repo.directory.path,
        'message': message,
      }),
    );
    return _gitOperationResult(raw);
  }

  Future<List<DemoGitBranchInfo>> listGitBranches(String directory) async {
    final repo = await _resolveRepositoryRoot(directory);
    if (repo == null) return const [];
    final raw = await _gitProviderForRoot(repo).listBranches({
      'directory': repo.relativePath,
      'absolutePath': repo.directory.path,
    });
    final branches = raw['branches'];
    if (branches is! List) return const [];
    return List.unmodifiable(
      [
        for (final branch in branches)
          if (branch is Map)
            DemoGitBranchInfo(
              name: (branch['name'] as String? ?? '').trim(),
              remote: branch['remote'] as bool? ?? false,
              current: branch['current'] as bool? ?? false,
              upstream: (branch['upstream'] as String? ?? '').trim(),
            ),
      ].where((branch) => branch.name.isNotEmpty),
    );
  }

  Future<DemoGitOperationResult> switchGitBranch(
    String directory,
    String branch, {
    bool remote = false,
    bool allowDirty = false,
  }) async {
    final repo = await _resolveRepositoryRoot(directory);
    if (repo == null) {
      return const DemoGitOperationResult(
        success: false,
        error: 'repository directory is invalid',
      );
    }
    final raw = await _runGitWrite(
      repo,
      () => _gitProviderForRoot(repo).switchBranch({
        'directory': repo.relativePath,
        'absolutePath': repo.directory.path,
        'branch': branch,
        'remote': remote,
        'allowDirty': allowDirty,
      }),
    );
    return _gitOperationResult(raw);
  }

  Future<List<DemoGitCommitInfo>> listGitCommitHistory(String directory) async {
    final repo = await _resolveRepositoryRoot(directory);
    if (repo == null) return const [];
    final raw = await _gitProviderForRoot(repo).commitHistory({
      'directory': repo.relativePath,
      'absolutePath': repo.directory.path,
      'limit': 60,
    });
    final commits = raw['commits'];
    if (raw['success'] != true || commits is! List) return const [];
    return List.unmodifiable(
      [
        for (final commit in commits)
          if (commit is Map) _gitCommitInfo(commit),
      ].whereType<DemoGitCommitInfo>(),
    );
  }

  Future<DemoGitCommitDiff> gitCommitDiff(String directory, String hash) async {
    final repo = await _resolveRepositoryRoot(directory);
    if (repo == null) {
      return const DemoGitCommitDiff(
        success: false,
        error: 'repository directory is invalid',
      );
    }
    final raw = await _gitProviderForRoot(repo).commitDiff({
      'directory': repo.relativePath,
      'absolutePath': repo.directory.path,
      'hash': hash,
    });
    if (raw['success'] != true) {
      return DemoGitCommitDiff(
        success: false,
        error: (raw['error'] as String?)?.trim(),
      );
    }
    final files = raw['files'];
    return DemoGitCommitDiff(
      success: true,
      files: files is List
          ? List.unmodifiable(
              [
                for (final file in files)
                  if (file is Map) _gitCommitFileChange(file),
              ].whereType<DemoGitCommitFileChange>(),
            )
          : const [],
      hunks: raw['tooLarge'] == true
          ? const []
          : List.unmodifiable(
              _parseUnifiedDiff(raw['stdout'] as String? ?? ''),
            ),
      tooLarge: raw['tooLarge'] == true,
    );
  }

  static DemoGitCommitInfo? _gitCommitInfo(Map<dynamic, dynamic> raw) {
    final hash = (raw['hash'] as String? ?? '').trim();
    if (hash.isEmpty) return null;
    final parents = raw['parents'];
    final authoredAtText = (raw['authoredAt'] as String? ?? '').trim();
    return DemoGitCommitInfo(
      graph: (raw['graph'] as String? ?? '').trimRight(),
      hash: hash,
      shortHash: (raw['shortHash'] as String? ?? '').trim(),
      parents: parents is List
          ? List.unmodifiable([
              for (final parent in parents)
                if (parent != null && parent.toString().trim().isNotEmpty)
                  parent.toString().trim(),
            ])
          : const [],
      authorName: (raw['authorName'] as String? ?? '').trim(),
      authorEmail: (raw['authorEmail'] as String? ?? '').trim(),
      authoredAt: DateTime.tryParse(authoredAtText)?.toLocal(),
      refs: (raw['refs'] as String? ?? '').trim(),
      subject: (raw['subject'] as String? ?? '').trim(),
    );
  }

  static DemoGitCommitFileChange? _gitCommitFileChange(
    Map<dynamic, dynamic> raw,
  ) {
    final path = (raw['path'] as String? ?? '').trim();
    if (path.isEmpty) return null;
    return DemoGitCommitFileChange(
      path: path,
      additions: raw['additions'] is int ? raw['additions'] as int : null,
      deletions: raw['deletions'] is int ? raw['deletions'] as int : null,
    );
  }

  Future<List<DemoGitRemoteInfo>> listGitRemotes(String directory) async {
    final repo = await _resolveRepositoryRoot(directory);
    if (repo == null) return const [];
    final raw = await _gitProviderForRoot(repo).listRemotes({
      'directory': repo.relativePath,
      'absolutePath': repo.directory.path,
    });
    final remotes = raw['remotes'];
    if (remotes is! List) return const [];
    return List.unmodifiable(
      [
        for (final remote in remotes)
          if (remote is Map)
            DemoGitRemoteInfo(
              name: (remote['name'] as String? ?? '').trim(),
              fetchUrl: (remote['fetchUrl'] as String? ?? '').trim(),
              pushUrl: (remote['pushUrl'] as String? ?? '').trim(),
            ),
      ].where((remote) => remote.name.isNotEmpty),
    );
  }

  Future<DemoGitOperationResult> setGitRemote(
    String directory, {
    required String name,
    required String url,
  }) async {
    final repo = await _resolveRepositoryRoot(directory);
    if (repo == null) {
      return const DemoGitOperationResult(
        success: false,
        error: 'repository directory is invalid',
      );
    }
    final raw = await _runGitWrite(
      repo,
      () => _gitProviderForRoot(repo).setRemote({
        'directory': repo.relativePath,
        'absolutePath': repo.directory.path,
        'name': name,
        'url': url,
        'action': 'upsert',
      }),
    );
    return _gitOperationResult(raw);
  }

  Future<DemoGitOperationResult> removeGitRemote(
    String directory, {
    required String name,
  }) async {
    final repo = await _resolveRepositoryRoot(directory);
    if (repo == null) {
      return const DemoGitOperationResult(
        success: false,
        error: 'repository directory is invalid',
      );
    }
    final raw = await _runGitWrite(
      repo,
      () => _gitProviderForRoot(repo).setRemote({
        'directory': repo.relativePath,
        'absolutePath': repo.directory.path,
        'name': name,
        'action': 'remove',
      }),
    );
    return _gitOperationResult(raw);
  }

  Future<DemoGitFileDiff> gitFileDiff(
    String directory,
    String path, {
    bool cached = false,
  }) async {
    final repo = await _resolveRepositoryRoot(directory);
    if (repo == null) {
      return const DemoGitFileDiff(
        success: false,
        error: 'repository directory is invalid',
      );
    }
    final raw = await _gitProviderForRoot(repo).fileDiff({
      'directory': repo.relativePath,
      'absolutePath': repo.directory.path,
      'path': path,
      'cached': cached,
    });
    if (raw['success'] != true) {
      return DemoGitFileDiff(
        success: false,
        error: (raw['error'] as String?)?.trim(),
      );
    }
    if (raw['tooLarge'] == true) {
      return const DemoGitFileDiff(success: true, tooLarge: true);
    }
    if (raw['empty'] == true) {
      return const DemoGitFileDiff(success: true, empty: true);
    }
    final diff = raw['stdout'] as String? ?? '';
    return DemoGitFileDiff(
      success: true,
      hunks: List.unmodifiable(_parseUnifiedDiff(diff)),
    );
  }

  Future<DemoGitOperationResult> fetchGitRemote(
    String directory, {
    String? remote,
  }) async {
    final repo = await _resolveRepositoryRoot(directory);
    if (repo == null) {
      return const DemoGitOperationResult(
        success: false,
        error: 'repository directory is invalid',
      );
    }
    final raw = await _runGitWrite(
      repo,
      () => _gitProviderForRoot(repo).fetch({
        'directory': repo.relativePath,
        'absolutePath': repo.directory.path,
        if (remote?.trim().isNotEmpty == true) 'remote': remote!.trim(),
      }),
    );
    return _gitOperationResult(raw);
  }

  Future<DemoGitOperationResult> pushGitRemote(
    String directory, {
    String? remote,
  }) async {
    final repo = await _resolveRepositoryRoot(directory);
    if (repo == null) {
      return const DemoGitOperationResult(
        success: false,
        error: 'repository directory is invalid',
      );
    }
    final raw = await _runGitWrite(
      repo,
      () => _gitProviderForRoot(repo).push({
        'directory': repo.relativePath,
        'absolutePath': repo.directory.path,
        if (remote?.trim().isNotEmpty == true) 'remote': remote!.trim(),
      }),
    );
    return _gitOperationResult(raw);
  }

  Future<DemoGitOperationResult> pullGitRemote(
    String directory, {
    String? remote,
  }) async {
    final repo = await _resolveRepositoryRoot(directory);
    if (repo == null) {
      return const DemoGitOperationResult(
        success: false,
        error: 'repository directory is invalid',
      );
    }
    final raw = await _runGitWrite(
      repo,
      () => _gitProviderForRoot(repo).pull({
        'directory': repo.relativePath,
        'absolutePath': repo.directory.path,
        if (remote?.trim().isNotEmpty == true) 'remote': remote!.trim(),
      }),
    );
    return _gitOperationResult(raw);
  }

  DemoGitOperationResult _gitOperationResult(Map<String, dynamic> raw) {
    final changedFiles = raw['changedFiles'];
    return DemoGitOperationResult(
      success: raw['success'] as bool? ?? false,
      message: (raw['message'] as String? ?? '').trim(),
      error: (raw['error'] as String?)?.trim(),
      branch: (raw['branch'] as String?)?.trim(),
      changedFiles: changedFiles is List
          ? List.unmodifiable([
              for (final file in changedFiles)
                if (file != null && file.toString().trim().isNotEmpty)
                  file.toString().trim(),
            ])
          : const [],
    );
  }

  Future<List<DemoRepositoryFileItem>> listGitRepositoryChildren(
    String directory, {
    String subdir = '',
    String query = '',
    int limit = 200,
  }) async {
    final repo = await _resolveRepositoryRoot(directory);
    if (repo == null) return const [];
    final root = repo.directory;
    if (!await root.exists()) return const [];
    final safeSubdir = subdir.trim().isEmpty
        ? ''
        : _safeRepoRelativePath(subdir);
    if (safeSubdir == null) return const [];
    final normalizedQuery = query.trim().toLowerCase();
    final results = <DemoRepositoryFileItem>[];
    final cappedLimit = limit.clamp(20, 500).toInt();
    if (normalizedQuery.isNotEmpty) {
      await _collectRepoSearchResults(
        root,
        root,
        normalizedQuery,
        results,
        cappedLimit,
      );
    } else {
      final dir = safeSubdir.isEmpty
          ? root
          : Directory('${root.path}/$safeSubdir');
      if (!await dir.exists()) return const [];
      await for (final entity in dir.list(followLinks: false)) {
        final item = await _repoFileItem(root, entity);
        if (item == null) continue;
        results.add(item);
        if (results.length >= cappedLimit) break;
      }
    }
    results.sort((a, b) {
      if (a.isDirectory != b.isDirectory) return a.isDirectory ? -1 : 1;
      return a.relativePath.toLowerCase().compareTo(
        b.relativePath.toLowerCase(),
      );
    });
    return List.unmodifiable(results);
  }

  Future<List<_ResolvedRepositoryRoot>> _discoverRepositoryRoots() async {
    final roots = <String, _ResolvedRepositoryRoot>{};
    await _collectRepositoryRoots(
      base: await _gitWorkspaceDirectory(),
      source: 'git',
      sourceLabel: 'workspace',
      roots: roots,
    );
    if (sdk.NapaxiFileBridge.isInitialized) {
      await _collectRepositoryRoots(
        base: sdk.NapaxiFileBridge.instance.workspaceDir,
        source: 'workspace',
        sourceLabel: 'workspace',
        roots: roots,
      );
    }
    final cliWorkspaceHostPath = await _resolvedCliWorkspaceHostPath();
    if (cliWorkspaceHostPath != null) {
      for (final spec in const [_CliEngineSpec.cc, _CliEngineSpec.codex]) {
        await _collectRepositoryRoots(
          base: Directory('$cliWorkspaceHostPath/${spec.id}'),
          source: 'workspace',
          sourceLabel: 'workspace',
          roots: roots,
          idPrefix: '${spec.id}/',
          displayPrefix: '${spec.id}/',
        );
      }
    }
    return List.unmodifiable(roots.values);
  }

  Future<void> _collectRepositoryRoots({
    required Directory base,
    required String source,
    required String sourceLabel,
    required Map<String, _ResolvedRepositoryRoot> roots,
    String idPrefix = '',
    String displayPrefix = '',
  }) async {
    if (!await base.exists()) return;
    await _collectRepositoryRootsFrom(
      base: base,
      directory: base,
      source: source,
      sourceLabel: sourceLabel,
      roots: roots,
      depth: 0,
      maxDepth: 3,
      idPrefix: idPrefix,
      displayPrefix: displayPrefix,
    );
  }

  Future<void> _collectRepositoryRootsFrom({
    required Directory base,
    required Directory directory,
    required String source,
    required String sourceLabel,
    required Map<String, _ResolvedRepositoryRoot> roots,
    required int depth,
    required int maxDepth,
    required String idPrefix,
    required String displayPrefix,
  }) async {
    if (depth > maxDepth) return;
    await for (final entity in directory.list(followLinks: false)) {
      if (entity is! Directory) continue;
      final name = _pathName(entity.path);
      if (_isIgnoredRepoBrowserName(name)) continue;
      final relativePath = _relativePath(base.path, entity.path);
      if (relativePath.isEmpty) continue;
      final scopedRelativePath = '$idPrefix$relativePath';
      final displayRelativePath = '$displayPrefix$relativePath';
      if (await Directory('${entity.path}/.git').exists()) {
        final id = '$source/$scopedRelativePath';
        roots[id] = _ResolvedRepositoryRoot(
          id: id,
          relativePath: scopedRelativePath,
          displayRelativePath: displayRelativePath,
          directory: entity,
          workspaceRoot: base,
          sourceLabel: sourceLabel,
        );
        continue;
      }
      if (depth < maxDepth) {
        await _collectRepositoryRootsFrom(
          base: base,
          directory: entity,
          source: source,
          sourceLabel: sourceLabel,
          roots: roots,
          depth: depth + 1,
          maxDepth: maxDepth,
          idPrefix: idPrefix,
          displayPrefix: displayPrefix,
        );
      }
    }
  }

  Future<_ResolvedRepositoryRoot?> _resolveRepositoryRoot(
    String directory,
  ) async {
    final safeDirectory = _safeRepoRelativePath(directory);
    if (safeDirectory == null) return null;
    final parts = safeDirectory.split('/');
    if (parts.length >= 2) {
      final source = parts.first;
      final relativePath = parts.skip(1).join('/');
      final explicit = await _repositoryRootForSource(source, relativePath);
      if (explicit != null) return explicit;
    }

    for (final source in const ['git', 'workspace']) {
      final resolved = await _repositoryRootForSource(source, safeDirectory);
      if (resolved != null) return resolved;
    }
    return null;
  }

  Future<_ResolvedRepositoryRoot?> _repositoryRootForSource(
    String source,
    String relativePath,
  ) async {
    if (relativePath.trim().isEmpty) return null;
    final relativeParts = relativePath
        .split('/')
        .where((part) => part.trim().isNotEmpty)
        .toList(growable: false);
    Directory? root;
    Directory? workspaceRoot;
    if (source == 'git') {
      final gitBase = await _gitWorkspaceDirectory();
      workspaceRoot = gitBase;
      root = Directory('${gitBase.path}/$relativePath');
    } else if (source == 'workspace') {
      if (relativeParts.isNotEmpty &&
          (relativeParts.first == _CliEngineSpec.cc.id ||
              relativeParts.first == _CliEngineSpec.codex.id)) {
        final cliWorkspaceHostPath = await _resolvedCliWorkspaceHostPath();
        if (cliWorkspaceHostPath == null) return null;
        workspaceRoot = Directory(cliWorkspaceHostPath);
        root = Directory('${workspaceRoot.path}/$relativePath');
      } else if (sdk.NapaxiFileBridge.isInitialized) {
        workspaceRoot = sdk.NapaxiFileBridge.instance.workspaceDir;
        root = Directory('${workspaceRoot.path}/$relativePath');
      }
    } else {
      return null;
    }
    if (root == null) return null;
    if (!await Directory('${root.path}/.git').exists()) return null;
    return _ResolvedRepositoryRoot(
      id: '$source/$relativePath',
      relativePath: relativePath,
      displayRelativePath: relativePath,
      directory: root,
      workspaceRoot: workspaceRoot ?? root,
      sourceLabel: 'workspace',
    );
  }

  Future<void> _collectRepoSearchResults(
    Directory root,
    Directory dir,
    String query,
    List<DemoRepositoryFileItem> results,
    int limit,
  ) async {
    if (results.length >= limit) return;
    await for (final entity in dir.list(followLinks: false)) {
      if (results.length >= limit) return;
      final name = _pathName(entity.path);
      if (_isIgnoredRepoBrowserName(name)) continue;
      final item = await _repoFileItem(root, entity);
      if (item == null) continue;
      if (name.toLowerCase().contains(query) ||
          item.relativePath.toLowerCase().contains(query)) {
        results.add(item);
      }
      if (entity is Directory) {
        await _collectRepoSearchResults(root, entity, query, results, limit);
      }
    }
  }

  Future<DemoRepositoryFileItem?> _repoFileItem(
    Directory root,
    FileSystemEntity entity,
  ) async {
    final name = _pathName(entity.path);
    if (_isIgnoredRepoBrowserName(name)) return null;
    final relativePath = _relativePath(root.path, entity.path);
    if (relativePath.isEmpty) return null;
    final stat = await entity.stat();
    final isDirectory = stat.type == FileSystemEntityType.directory;
    return DemoRepositoryFileItem(
      name: name,
      relativePath: relativePath,
      absolutePath: entity.path,
      isDirectory: isDirectory,
      sizeBytes: isDirectory ? null : stat.size,
      modified: stat.modified,
      mimeType: isDirectory ? 'inode/directory' : _repoMimeType(name),
    );
  }

  Future<void> _writeAndroidProjectTemplate({
    required Directory projectDir,
    required String directory,
    required String appName,
    required String packageName,
    required String versionName,
    required int minSdk,
    required int targetSdk,
    required String template,
  }) async {
    final packagePath = packageName.replaceAll('.', '/');
    await Directory('${projectDir.path}/.mobile').create(recursive: true);
    await Directory('${projectDir.path}/res/values').create(recursive: true);
    await Directory(
      '${projectDir.path}/src/$packagePath',
    ).create(recursive: true);
    final profile = <String, dynamic>{
      'schemaVersion': 1,
      'platform': 'android',
      'applicationId': packageName,
      'appName': appName,
      'versionCode': 1,
      'versionName': versionName,
      'minSdk': minSdk,
      'targetSdk': targetSdk,
      'buildToolsVersion': '33.0.2',
      'androidPlatform': 'android-33',
      'signing': {
        'debugKeystore': '.mobile/debug.keystore',
        'alias': 'androiddebugkey',
        'storePassword': 'android',
        'keyPassword': 'android',
      },
      'createdAt': DateTime.now().toUtc().toIso8601String(),
      'updatedAt': DateTime.now().toUtc().toIso8601String(),
    };
    await _writeJsonFile(File('${projectDir.path}/.mobile/project.json'), {
      'schemaVersion': 1,
      'type': 'android_app',
      'name': appName,
      'directory': directory,
      'template': template,
      'createdAt': DateTime.now().toUtc().toIso8601String(),
    });
    await _writeJsonFile(
      File('${projectDir.path}/.mobile/build-profile.json'),
      profile,
    );
    await File(
      '${projectDir.path}/.mobile/build-history.json',
    ).writeAsString('[]\n');
    await File(
      '${projectDir.path}/AndroidManifest.xml',
    ).writeAsString(_androidManifestXml(profile));
    await File(
      '${projectDir.path}/res/values/strings.xml',
    ).writeAsString(_androidStringsXml(appName));
    await File(
      '${projectDir.path}/res/values/colors.xml',
    ).writeAsString(_androidColorsXml());
    await File(
      '${projectDir.path}/src/$packagePath/MainActivity.java',
    ).writeAsString(
      _mainActivitySource(
        packageName: packageName,
        appName: appName,
        canvas: template == 'canvas',
      ),
    );
    await File(
      '${projectDir.path}/build.sh',
    ).writeAsString(_androidBuildScript());
    await File(
      '${projectDir.path}/.gitignore',
    ).writeAsString(_androidGitignore());
    await File('${projectDir.path}/README.md').writeAsString(
      '# $appName\n\nAndroid project managed by the mobile development scenario.\n\n'
      '- Build profile: `.mobile/build-profile.json`\n'
      '- Local reusable debug signing key: `.mobile/debug.keystore`\n'
      '- Build command: `bash build.sh`\n',
    );
  }

  Future<Map<String, dynamic>> _runAndroidProjectShell(
    Directory projectDir,
    String command, {
    Duration timeout = const Duration(minutes: 2),
  }) async {
    final startedAt = DateTime.now();
    int durationMs() => DateTime.now().difference(startedAt).inMilliseconds;
    if (Platform.isAndroid) {
      try {
        final response = await _platformContextChannel
            .invokeMethod<String>('executeLinuxProgram', {
              'workspaceDir': projectDir.path,
              'argv': ['/bin/sh', '-lc', command],
              'workdir': '/workspace',
              'timeout': timeout.inSeconds.clamp(1, 600).toInt(),
            })
            .timeout(timeout + const Duration(seconds: 5));
        final decoded = jsonDecode(response ?? '{}');
        if (decoded is! Map) {
          return {
            'providerAvailable': false,
            'exitCode': -1,
            'stdout': '',
            'stderr': '',
            'durationMs': durationMs(),
            'error': 'Android Linux runner returned invalid JSON',
          };
        }
        final result = Map<String, dynamic>.from(decoded);
        return {
          'providerAvailable': result['providerAvailable'] as bool? ?? false,
          'exitCode': result['exitCode'] as int? ?? -1,
          'stdout': (result['stdout'] ?? '').toString(),
          'stderr': (result['stderr'] ?? '').toString(),
          'durationMs': result['durationMs'] as int? ?? durationMs(),
          if (result['error'] != null) 'error': result['error'].toString(),
        };
      } on TimeoutException {
        return {
          'providerAvailable': true,
          'exitCode': -1,
          'stdout': '',
          'stderr': '',
          'durationMs': durationMs(),
          'error': 'command timed out after ${timeout.inSeconds}s',
        };
      } on PlatformException catch (error) {
        return {
          'providerAvailable': false,
          'exitCode': -1,
          'stdout': '',
          'stderr': '',
          'durationMs': durationMs(),
          'error': error.message ?? error.code,
        };
      }
    }
    try {
      final result = await Process.run('/bin/sh', [
        '-lc',
        command,
      ], workingDirectory: projectDir.path).timeout(timeout);
      return {
        'providerAvailable': true,
        'exitCode': result.exitCode,
        'stdout': result.stdout.toString().trim(),
        'stderr': result.stderr.toString().trim(),
        'durationMs': durationMs(),
      };
    } catch (error) {
      return {
        'providerAvailable': false,
        'exitCode': -1,
        'stdout': '',
        'stderr': '',
        'durationMs': durationMs(),
        'error': error.toString(),
      };
    }
  }

  Future<Map<String, dynamic>> _loadJsonFile(File file) async {
    final decoded = jsonDecode(await file.readAsString());
    return decoded is Map ? Map<String, dynamic>.from(decoded) : {};
  }

  Future<void> _writeJsonFile(File file, Map<String, dynamic> value) async {
    await file.parent.create(recursive: true);
    final encoded = const JsonEncoder.withIndent('  ').convert(value);
    await file.writeAsString('$encoded\n');
  }

  Future<void> _writeAndroidManifestFromProfile(
    Directory projectDir,
    Map<String, dynamic> profile,
  ) async {
    await File(
      '${projectDir.path}/AndroidManifest.xml',
    ).writeAsString(_androidManifestXml(profile));
  }

  Future<void> _appendAndroidBuildHistory(
    Directory projectDir, {
    required Map<String, dynamic> profile,
    required String apkPath,
    Map<String, dynamic>? installed,
  }) async {
    final historyFile = File('${projectDir.path}/.mobile/build-history.json');
    var history = <dynamic>[];
    if (await historyFile.exists()) {
      final decoded = jsonDecode(await historyFile.readAsString());
      if (decoded is List) history = decoded;
    }
    final entry = <String, dynamic>{
      'builtAt': DateTime.now().toUtc().toIso8601String(),
      'applicationId': profile['applicationId'],
      'versionCode': profile['versionCode'],
      'versionName': profile['versionName'],
      'apkPath': apkPath,
      'signing': profile['signing'],
    };
    if (installed != null) entry['install'] = installed;
    history.add(entry);
    final encoded = const JsonEncoder.withIndent('  ').convert(history);
    await historyFile.writeAsString('$encoded\n');
  }

  String _androidManifestXml(Map<String, dynamic> profile) {
    final packageName = (profile['applicationId'] as String? ?? '').trim();
    final appName = _xmlEscape((profile['appName'] as String? ?? 'App').trim());
    final versionCode = _int(profile['versionCode']) ?? 1;
    final versionName = _xmlEscape(
      (profile['versionName'] as String? ?? '0.1.0').trim(),
    );
    final minSdk = _int(profile['minSdk']) ?? 21;
    final targetSdk = _int(profile['targetSdk']) ?? 33;
    return '''<?xml version="1.0" encoding="utf-8"?>
<manifest xmlns:android="http://schemas.android.com/apk/res/android"
    package="$packageName"
    android:versionCode="$versionCode"
    android:versionName="$versionName">
  <uses-sdk android:minSdkVersion="$minSdk" android:targetSdkVersion="$targetSdk"/>
  <application android:theme="@style/AppTheme" android:label="$appName" android:allowBackup="false">
    <activity android:name=".MainActivity" android:exported="true">
      <intent-filter>
        <action android:name="android.intent.action.MAIN"/>
        <category android:name="android.intent.category.LAUNCHER"/>
      </intent-filter>
    </activity>
  </application>
</manifest>
''';
  }

  String _androidStringsXml(String appName) {
    return '''<resources>
  <string name="app_name">${_xmlEscape(appName)}</string>
</resources>
''';
  }

  String _androidColorsXml() {
    return '''<resources>
  <style name="AppTheme" parent="@android:style/Theme.Material.Light.NoActionBar">
    <item name="android:fontFamily">sans</item>
    <item name="android:windowLightStatusBar">true</item>
    <item name="android:colorAccent">#2F6BFF</item>
  </style>
</resources>
''';
  }

  String _mainActivitySource({
    required String packageName,
    required String appName,
    required bool canvas,
  }) {
    if (canvas) {
      return '''package $packageName;

import android.app.Activity;
import android.os.Bundle;
import android.graphics.Canvas;
import android.graphics.Color;
import android.graphics.Paint;
import android.view.MotionEvent;
import android.view.View;

public class MainActivity extends Activity {
  @Override protected void onCreate(Bundle state) {
    super.onCreate(state);
    setContentView(new AppCanvas(this));
  }

  static class AppCanvas extends View {
    private final Paint paint = new Paint(Paint.ANTI_ALIAS_FLAG);
    private float x = 240;
    private float y = 360;

    AppCanvas(android.content.Context context) {
      super(context);
      setBackgroundColor(Color.rgb(247, 248, 250));
    }

    @Override protected void onDraw(Canvas canvas) {
      super.onDraw(canvas);
      paint.setColor(Color.rgb(47, 107, 255));
      canvas.drawCircle(x, y, 86, paint);
      paint.setColor(Color.WHITE);
      paint.setTextAlign(Paint.Align.CENTER);
      paint.setTextSize(36);
      canvas.drawText("${_javaEscape(appName)}", getWidth() / 2f, 96, paint);
      paint.setTextSize(24);
      canvas.drawText("Tap anywhere", getWidth() / 2f, getHeight() - 80, paint);
    }

    @Override public boolean onTouchEvent(MotionEvent event) {
      if (event.getAction() == MotionEvent.ACTION_DOWN || event.getAction() == MotionEvent.ACTION_MOVE) {
        x = event.getX();
        y = event.getY();
        invalidate();
        return true;
      }
      return true;
    }
  }
}
''';
    }
    return '''package $packageName;

import android.app.Activity;
import android.os.Bundle;
import android.graphics.Color;
import android.view.Gravity;
import android.widget.Button;
import android.widget.LinearLayout;
import android.widget.TextView;

public class MainActivity extends Activity {
  private int taps = 0;

  @Override protected void onCreate(Bundle state) {
    super.onCreate(state);
    LinearLayout root = new LinearLayout(this);
    root.setOrientation(LinearLayout.VERTICAL);
    root.setGravity(Gravity.CENTER);
    root.setPadding(40, 40, 40, 40);
    root.setBackgroundColor(Color.rgb(247, 248, 250));

    TextView title = new TextView(this);
    title.setText("${_javaEscape(appName)}");
    title.setTextSize(30);
    title.setGravity(Gravity.CENTER);

    TextView status = new TextView(this);
    status.setText("Ready");
    status.setTextSize(20);
    status.setGravity(Gravity.CENTER);

    Button button = new Button(this);
    button.setText("Tap");
    button.setOnClickListener(v -> {
      taps += 1;
      status.setText("Interactions: " + taps);
    });

    root.addView(title);
    root.addView(status);
    root.addView(button);
    setContentView(root);
  }
}
''';
  }

  String _androidBuildScript() {
    return '''#!/bin/bash
set -e

SDK=/opt/android/sdk
BT=\$SDK/build-tools/33.0.2
ANDROID_JAR=\$SDK/platforms/android-33/android.jar
SYSROOT=/opt/x86root/sysroot
QX="qemu-x86_64 -L \$SYSROOT"

rm -rf build
mkdir -p build/classes build/dex build/res-flat build/gen

echo "[1/6] aapt2 compile resources..."
\$QX \$BT/aapt2 compile --dir res -o build/res-flat

echo "[2/6] aapt2 link..."
FLAT=\$(find build/res-flat -name "*.flat" | tr '\\n' ' ')
\$QX \$BT/aapt2 link \\
    -I "\$ANDROID_JAR" \\
    --manifest AndroidManifest.xml \\
    --java build/gen \\
    -o build/base.apk \\
    \$FLAT

echo "[3/6] javac..."
SOURCES=\$(find src build/gen -name "*.java")
javac -source 1.8 -target 1.8 \\
    -bootclasspath "\$ANDROID_JAR" \\
    -cp "\$ANDROID_JAR" \\
    -d build/classes \\
    \$SOURCES

echo "[4/6] d8 dex..."
CLASSFILES=\$(find build/classes -name "*.class")
\$BT/d8 --lib "\$ANDROID_JAR" --output build/dex \$CLASSFILES

echo "[5/6] package dex..."
cp build/base.apk build/unsigned.apk
( cd build/dex && zip -j ../unsigned.apk classes.dex )

echo "[6/6] sign..."
\$QX \$BT/zipalign -f -p 4 build/unsigned.apk build/aligned.apk

KS=.mobile/debug.keystore
if [ ! -f "\$KS" ]; then
  keytool -genkeypair \\
    -keystore "\$KS" -storepass android -keypass android \\
    -alias androiddebugkey -keyalg RSA -keysize 2048 -validity 10000 \\
    -dname "CN=Android Debug,O=Android,C=US" >/dev/null
fi

\$BT/apksigner sign \\
    --ks "\$KS" --ks-pass pass:android --key-pass pass:android \\
    --out build/app.apk \\
    build/aligned.apk

\$BT/apksigner verify build/app.apk
echo "build/app.apk"
''';
  }

  String _androidGitignore() {
    return '''build/
.mobile/debug.keystore
*.apk
*.idsig
''';
  }

  String? _safeAndroidProjectDirectory(String value) {
    var normalized = value.trim().replaceAll('\\', '/');
    if (normalized.startsWith('git/')) {
      normalized = normalized.substring(4);
    }
    normalized = normalized
        .split('/')
        .where((part) => part.trim().isNotEmpty)
        .map(_slugFromText)
        .where((part) => part.isNotEmpty)
        .join('/');
    if (normalized.isEmpty ||
        normalized.startsWith('/') ||
        normalized.contains('..')) {
      return null;
    }
    return normalized;
  }

  String _validAndroidPackageName(
    String value, {
    required String fallbackName,
  }) {
    final normalized = value.trim().toLowerCase();
    final valid = RegExp(
      r'^[a-z][a-z0-9_]*(\.[a-z][a-z0-9_]*){2,}$',
    ).hasMatch(normalized);
    if (valid) return normalized;
    final slug = _slugFromText(fallbackName).replaceAll('-', '');
    final safe = slug.isEmpty ? 'app' : slug;
    return 'app.generated.$safe';
  }

  String _slugFromText(String value) {
    final normalized = value
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    return normalized.isEmpty
        ? 'android-project-${DateTime.now().millisecondsSinceEpoch}'
        : normalized;
  }

  String _xmlEscape(String value) {
    return value
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;')
        .replaceAll("'", '&apos;');
  }

  String _javaEscape(String value) {
    return value
        .replaceAll('\\', r'\\')
        .replaceAll('"', r'\"')
        .replaceAll('\n', r'\n');
  }

  sdk.AutomationTrigger? _triggerFromParams(Map<String, dynamic> params) {
    final atMs = _int(params['atMs']);
    if (atMs != null && atMs > 0) {
      return sdk.AutomationTrigger.oneShotAt(
        atMs: atMs,
        timezone: _timezone(params),
      );
    }

    final delaySeconds = _int(params['delaySeconds']);
    final delayMinutes = _int(params['delayMinutes']);
    final delayMs = (delaySeconds != null && delaySeconds > 0)
        ? delaySeconds * 1000
        : (delayMinutes != null && delayMinutes > 0)
        ? delayMinutes * 60 * 1000
        : null;
    if (delayMs != null) {
      return sdk.AutomationTrigger.oneShotAt(
        atMs: DateTime.now().millisecondsSinceEpoch + delayMs,
        timezone: _timezone(params),
      );
    }

    final localTime = params['localTime'];
    if (localTime is Map) {
      final map = Map<String, dynamic>.from(localTime);
      final hour = _int(map['hour']);
      final minute = _int(map['minute']);
      if (hour == null || minute == null) return null;
      return sdk.AutomationTrigger.localTime(
        hour: hour,
        minute: minute,
        timezone: _timezone(map),
        daysOfWeek: _intList(map['daysOfWeek']),
      );
    }

    return null;
  }

  Future<Directory> _gitWorkspaceDirectory() async {
    if (sdk.NapaxiFileBridge.isInitialized) {
      return sdk.NapaxiFileBridge.instance.workspaceDirScoped(
        accountId: _runtimeProfile.accountId,
        agentId: _runtimeProfile.agentId,
      );
    }
    final documents = await getApplicationDocumentsDirectory();
    return Directory(
      '${documents.path}/git_repos/${_runtimeProfile.accountId}/${_runtimeProfile.agentId}',
    );
  }

  Future<DemoGitProvider> _gitProvider() async {
    return DemoGitProvider(workspaceDirectory: await _gitWorkspaceDirectory());
  }

  DemoGitProvider _gitProviderForRoot(_ResolvedRepositoryRoot repo) {
    return DemoGitProvider(workspaceDirectory: repo.workspaceRoot);
  }

  Map<String, dynamic> _decodeParams(String paramsJson) {
    final decoded = jsonDecode(paramsJson);
    return decoded is Map ? Map<String, dynamic>.from(decoded) : {};
  }

  sdk.NapaxiEngine _requireEngine() {
    final engine = _engine;
    if (engine == null) {
      throw StateError('napaxi engine has not been configured');
    }
    return engine;
  }

  String _timezone(Map<String, dynamic> params) {
    final explicit = (params['timezone'] as String?)?.trim();
    if (explicit != null && explicit.isNotEmpty) return explicit;
    final fallback = _defaultTimezone?.trim();
    return fallback == null || fallback.isEmpty ? 'Asia/Shanghai' : fallback;
  }

  String _defaultJobName(String message) {
    final text = message.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (text.length <= 24) return text;
    return '${text.substring(0, 24)}...';
  }

  Map<String, dynamic> _jobJson(sdk.AutomationJob job) => {
    'id': job.id,
    'name': job.name,
    'enabled': job.enabled,
    'trigger': job.trigger.toJson(),
    'payload': job.payload.toJson(),
    'nextRunAtMs': job.state.nextRunAtMs,
    'lastRunStatus': job.state.lastRunStatus,
    'lastError': job.state.lastError,
  };

  Map<String, dynamic>? _wakeJson(sdk.AutomationWake? wake) => wake == null
      ? null
      : {
          'jobId': wake.jobId,
          'atMs': wake.atMs,
          'trigger': wake.trigger.toJson(),
        };

  Map<String, dynamic> _runJson(sdk.AutomationRun run) => {
    'runId': run.runId,
    'jobId': run.jobId,
    'status': run.status,
    'triggerSource': run.triggerSource,
    'startedAt': run.startedAt,
    'completedAt': run.completedAt,
    'summary': run.summary,
    'error': run.error,
  };

  Future<sdk.A2ALocalTransportStatus> _a2aEnsureLocalTransport(
    sdk.NapaxiEngine engine,
  ) async {
    var status = await engine.a2a.localTransportStatus();
    if (status.running || !status.supported) return status;
    try {
      status = await engine.a2a.startLocalTransport(
        agentId: _currentAgentId ?? _runtimeProfile.agentId,
        displayName: 'Napaxi',
      );
    } catch (_) {
      return status;
    }
    return status;
  }

  bool _a2aPeerAvailable(sdk.A2APeer peer) {
    return _a2aTrustedIdentity(peer) && _a2aEndpoint(peer) != null;
  }

  Future<_A2AConnectivityReport> _a2aConnectivityForToolRun(
    sdk.NapaxiEngine engine, {
    required sdk.A2ALocalTransportStatus status,
  }) async {
    final savedPeers = engine.a2a.listPeers();
    final savedTrusted = savedPeers
        .where((peer) => _a2aTrustedIdentity(peer))
        .toList(growable: false);
    if (!status.supported || !status.running) {
      return _A2AConnectivityReport(
        local: status,
        savedTrustedPeerCount: savedTrusted.length,
        discoveredPeerCount: 0,
        verifiedPeerCount: 0,
        peers: savedTrusted
            .map((peer) => _a2aPeerWithoutCurrentEndpoint(peer))
            .toList(growable: false),
        transportCandidates: [
          _A2ATransportCandidate.unavailable(
            transport: 'lan_tcp',
            reason: status.supported
                ? 'local_transport_not_running'
                : 'local_transport_not_supported',
          ),
          _A2ATransportCandidate.unavailable(
            transport: 'ble',
            reason: 'ble_transport_not_registered',
          ),
          _A2ATransportCandidate.unavailable(
            transport: 'xchannel_relay',
            reason: 'xchannel_relay_not_configured',
          ),
        ],
      );
    }

    final discoveredById = <String, sdk.A2ALocalPeerAdvertisement>{};
    try {
      final discovered = await engine.a2a.discoverLocalPeers(
        timeoutMs: _localA2ADiscoveryTimeoutMs,
      );
      for (final peer in discovered) {
        if (peer.peerId.trim().isEmpty ||
            peer.endpoint.trim().isEmpty ||
            peer.peerId == status.peerId) {
          continue;
        }
        discoveredById[peer.peerId] = peer;
      }
    } catch (error) {
      debugPrint('[napaxiToolTrace] local A2A peer refresh failed: $error');
    }

    final peers = <sdk.A2APeer>[];
    for (final peer in savedTrusted.where(
      (peer) => peer.peerId != status.peerId,
    )) {
      final discovered = discoveredById[peer.peerId];
      if (discovered != null &&
          _a2aAdvertisementMatchesTrustedPeer(peer, discovered)) {
        peers.add(_a2aPeerWithFreshEndpoint(peer, discovered));
        continue;
      }
      final cachedEndpoint = _a2aEndpoint(peer);
      if (cachedEndpoint != null &&
          await _a2aProbeCachedEndpoint(
            engine: engine,
            localPeerId: status.peerId,
            peer: peer,
            endpoint: cachedEndpoint,
          )) {
        peers.add(_a2aPeerWithProbedCachedEndpoint(peer, cachedEndpoint));
        continue;
      }
      peers.add(_a2aPeerWithoutCurrentEndpoint(peer));
    }
    final verifiedPeerCount = peers.where(_a2aPeerAvailable).length;
    return _A2AConnectivityReport(
      local: status,
      savedTrustedPeerCount: savedTrusted.length,
      discoveredPeerCount: discoveredById.length,
      verifiedPeerCount: verifiedPeerCount,
      peers: peers,
      transportCandidates: [
        _A2ATransportCandidate(
          transport: 'lan_tcp',
          status: verifiedPeerCount > 0
              ? 'verified'
              : discoveredById.isEmpty
              ? 'not_discovered'
              : 'discovered_but_untrusted_or_mismatched',
          reason: verifiedPeerCount > 0
              ? ''
              : discoveredById.isEmpty
              ? 'no_trusted_peer_seen_in_current_mdns_window'
              : 'discovered_peer_identity_did_not_match_saved_trust',
        ),
        _A2ATransportCandidate.unavailable(
          transport: 'ble',
          reason: 'ble_transport_not_registered',
        ),
        _A2ATransportCandidate.unavailable(
          transport: 'xchannel_relay',
          reason: 'xchannel_relay_not_configured',
        ),
      ],
    );
  }

  bool _a2aTrustedIdentity(sdk.A2APeer peer) {
    final trust = peer.trustLevel.trim().toLowerCase();
    return (trust == 'trusted' ||
            trust == 'user_confirmed' ||
            peer.sharedSecret.trim().isNotEmpty) &&
        peer.sharedSecret.trim().isNotEmpty;
  }

  bool _a2aAdvertisementMatchesTrustedPeer(
    sdk.A2APeer saved,
    sdk.A2ALocalPeerAdvertisement discovered,
  ) {
    if (saved.peerId != discovered.peerId) return false;
    final savedKey = saved.publicKey.trim();
    final discoveredKey = discovered.publicKey.trim();
    if (savedKey.isNotEmpty &&
        discoveredKey.isNotEmpty &&
        savedKey != discoveredKey) {
      return false;
    }
    return discovered.endpoint.trim().isNotEmpty;
  }

  sdk.A2APeer _a2aPeerWithoutCurrentEndpoint(sdk.A2APeer saved) {
    return sdk.A2APeer(
      peerId: saved.peerId,
      agentId: saved.agentId,
      displayName: saved.displayName,
      deepLinkUrl: saved.deepLinkUrl,
      trustLevel: saved.trustLevel,
      sharedSecret: saved.sharedSecret,
      publicKey: saved.publicKey,
      endpoints: const [],
      lastSeenAt: saved.lastSeenAt,
      createdAt: saved.createdAt,
      updatedAt: saved.updatedAt,
    );
  }

  sdk.A2APeer _a2aPeerWithProbedCachedEndpoint(
    sdk.A2APeer saved,
    sdk.A2APeerEndpoint endpoint,
  ) {
    final now = DateTime.now().toUtc().toIso8601String();
    return sdk.A2APeer(
      peerId: saved.peerId,
      agentId: saved.agentId,
      displayName: saved.displayName,
      deepLinkUrl: saved.deepLinkUrl,
      trustLevel: saved.trustLevel,
      sharedSecret: saved.sharedSecret,
      publicKey: saved.publicKey,
      endpoints: [
        sdk.A2APeerEndpoint(
          transport: endpoint.transport,
          uri: endpoint.uri,
          lastSeenAt: now,
        ),
      ],
      lastSeenAt: now,
      createdAt: saved.createdAt,
      updatedAt: now,
    );
  }

  sdk.A2APeer _a2aPeerWithFreshEndpoint(
    sdk.A2APeer saved,
    sdk.A2ALocalPeerAdvertisement discovered,
  ) {
    final now = DateTime.now().toUtc().toIso8601String();
    return sdk.A2APeer(
      peerId: saved.peerId,
      agentId: saved.agentId.isNotEmpty ? saved.agentId : discovered.agentId,
      displayName: saved.displayName.isNotEmpty
          ? saved.displayName
          : discovered.displayName,
      deepLinkUrl: saved.deepLinkUrl,
      trustLevel: saved.trustLevel,
      sharedSecret: saved.sharedSecret,
      publicKey: saved.publicKey.isNotEmpty
          ? saved.publicKey
          : discovered.publicKey,
      endpoints: [
        sdk.A2APeerEndpoint(
          transport: discovered.coreTransport,
          uri: discovered.endpoint,
          lastSeenAt: now,
        ),
      ],
      lastSeenAt: now,
      createdAt: saved.createdAt,
      updatedAt: now,
    );
  }

  sdk.A2APeerEndpoint? _a2aEndpoint(sdk.A2APeer peer) {
    for (final endpoint in peer.endpoints) {
      if (endpoint.uri.trim().isNotEmpty) return endpoint;
    }
    return null;
  }

  Future<sdk.A2APeer?> _a2aRefreshTrustedPeerForSend(
    sdk.NapaxiEngine engine,
    sdk.A2APeer peer,
  ) async {
    try {
      final discovered = await engine.a2a.discoverLocalPeers(
        timeoutMs: _localA2ADiscoveryTimeoutMs,
      );
      for (final candidate in discovered) {
        if (candidate.peerId != peer.peerId ||
            candidate.endpoint.trim().isEmpty ||
            !_a2aAdvertisementMatchesTrustedPeer(peer, candidate)) {
          continue;
        }
        return _a2aPeerWithFreshEndpoint(peer, candidate);
      }
    } catch (error) {
      debugPrint('[napaxiToolTrace] local A2A peer send refresh failed: $error');
    }
    return null;
  }

  Future<bool> _a2aProbeCachedEndpoint({
    required sdk.NapaxiEngine engine,
    required String localPeerId,
    required sdk.A2APeer peer,
    required sdk.A2APeerEndpoint endpoint,
  }) async {
    if (localPeerId.trim().isEmpty ||
        peer.peerId.trim().isEmpty ||
        endpoint.uri.trim().isEmpty) {
      return false;
    }
    final now = DateTime.now().toUtc();
    final nonce = now.microsecondsSinceEpoch.toString();
    final probe = sdk.A2APeerMessage(
      messageId: 'probe-$nonce',
      sessionId: 'diagnostic:$localPeerId:${peer.peerId}',
      fromPeerId: localPeerId,
      toPeerId: peer.peerId,
      kind: 'ping',
      createdAt: now.toIso8601String(),
      expiresAt: now.add(const Duration(seconds: 30)).toIso8601String(),
      nonce: nonce,
      idempotencyKey: 'probe-$nonce',
      payload: const {'purpose': 'local_a2a_reachability_probe'},
    );
    try {
      final sent = await engine.a2a.sendDiagnosticPeerMessage(
        probe,
        endpoint: endpoint.uri,
      );
      debugPrint(
        '[napaxiToolTrace] local A2A cached endpoint probe peer=${peer.peerId} endpoint=${endpoint.uri} sent=$sent',
      );
      return sent;
    } catch (error) {
      debugPrint(
        '[napaxiToolTrace] local A2A cached endpoint probe failed: $error',
      );
      return false;
    }
  }

  Future<Map<String, dynamic>> _a2aSendPeerMessageWithEndpointFallback({
    required sdk.NapaxiEngine engine,
    required sdk.A2APeer peer,
    required sdk.A2APeerMessage message,
    required sdk.A2APeerEndpoint endpoint,
  }) async {
    final attempts = <Map<String, dynamic>>[];
    Future<bool> tryEndpoint(sdk.A2APeerEndpoint candidate) async {
      try {
        final sent = await engine.a2a.sendPeerMessage(
          message,
          endpoint: candidate.uri,
        );
        attempts.add({
          'endpoint': candidate.uri,
          'transport': candidate.transport,
          'success': sent,
        });
        return sent;
      } catch (error) {
        attempts.add({
          'endpoint': candidate.uri,
          'transport': candidate.transport,
          'success': false,
          'error': error.toString(),
        });
        return false;
      }
    }

    final refreshed = await _a2aRefreshTrustedPeerForSend(engine, peer);
    final refreshedEndpoint = refreshed == null
        ? null
        : _a2aEndpoint(refreshed);
    var usedEndpoint = endpoint;
    var sent = false;
    if (refreshedEndpoint != null) {
      sent = await tryEndpoint(refreshedEndpoint);
      usedEndpoint = refreshedEndpoint;
    }
    if (!sent &&
        (refreshedEndpoint == null ||
            refreshedEndpoint.uri.trim() != endpoint.uri.trim())) {
      sent = await tryEndpoint(endpoint);
      usedEndpoint = endpoint;
    }
    return {
      'success': sent,
      'endpoint': usedEndpoint.uri,
      'transport': usedEndpoint.transport,
      'attempts': attempts,
      if (!sent)
        'code': attempts.any(_a2aAttemptLooksLikeStaleEndpoint)
            ? 'cached_endpoint_stale_or_unreachable'
            : 'a2a_delivery_failed',
    };
  }

  bool _a2aAttemptLooksLikeStaleEndpoint(Map<String, dynamic> attempt) {
    final error = (attempt['error'] ?? '').toString().toLowerCase();
    return error.contains('connection refused') ||
        error.contains('timed out') ||
        error.contains('timeout') ||
        error.contains('network is unreachable') ||
        error.contains('no route to host');
  }

  String _a2aNoVerifiedChannelDisplayText(_A2AConnectivityReport connectivity) {
    if (!connectivity.local.supported) {
      return '当前设备不支持附近 Agent 连接。';
    }
    if (!connectivity.local.running) {
      return '附近连接还没有开启，请先在“附近”里允许连接和被发现。';
    }
    if (connectivity.savedTrustedPeerCount > 0) {
      return '已配对的附近 Agent 还在，但当前没有建立可验证的本地通道；这不能说明对方离线，请确认两台手机都打开“附近”后再试。';
    }
    return '当前没有发现已配对的附近 Agent，请先在“附近”里完成配对。';
  }

  sdk.A2APeer? _a2aResolvePeer(String value, List<sdk.A2APeer> peers) {
    final target = value.trim().toLowerCase();
    if (target.isEmpty) return null;
    for (final peer in peers) {
      final labels = [
        peer.peerId,
        peer.agentId,
        peer.displayName,
        _a2aPeerDisplayLabel(peer),
      ].map((item) => item.trim().toLowerCase());
      if (labels.any((item) => item == target || item.startsWith(target))) {
        return peer;
      }
    }
    return null;
  }

  Map<String, dynamic> _a2aPeerToolJson(sdk.A2APeer peer) {
    final endpoint = _a2aEndpoint(peer);
    final displayLabel = _a2aPeerDisplayLabel(peer);
    return {
      'target': displayLabel,
      'displayLabel': displayLabel,
      'trustLevel': peer.trustLevel,
      'available': _a2aPeerAvailable(peer),
      'hasSharedSecret': peer.sharedSecret.trim().isNotEmpty,
      'hasVerifiedLocalChannel': endpoint != null,
      'lastSeenAt': peer.lastSeenAt,
    };
  }

  Map<String, dynamic> _a2aPeerParticipantJson(sdk.A2APeer peer) {
    return {
      'peerId': peer.peerId,
      'agentId': peer.agentId,
      'displayName': peer.displayName,
      'displayLabel': _a2aPeerDisplayLabel(peer),
    };
  }

  Future<List<Map<String, dynamic>>> _a2aLoadCollaborations() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_a2aCollaborationStoreKey);
    if (raw == null || raw.trim().isEmpty) return <Map<String, dynamic>>[];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return <Map<String, dynamic>>[];
      return decoded
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList();
    } catch (_) {
      return <Map<String, dynamic>>[];
    }
  }

  Future<Map<String, dynamic>?> _a2aLoadCollaboration(String sessionId) async {
    final collaborations = await _a2aLoadCollaborations();
    for (final collaboration in collaborations) {
      if (collaboration['sessionId'] == sessionId) return collaboration;
    }
    return null;
  }

  Future<void> _a2aUpsertCollaboration(
    Map<String, dynamic> collaboration,
  ) async {
    final collaborations = await _a2aLoadCollaborations();
    final sessionId = collaboration['sessionId']?.toString() ?? '';
    collaborations.removeWhere((item) => item['sessionId'] == sessionId);
    collaborations.add(collaboration);
    collaborations.sort(
      (a, b) => (b['updatedAt']?.toString() ?? '').compareTo(
        a['updatedAt']?.toString() ?? '',
      ),
    );
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _a2aCollaborationStoreKey,
      jsonEncode(collaborations.take(40).toList(growable: false)),
    );
  }

  Map<String, dynamic> _a2aCollaborationPublicJson(
    Map<String, dynamic> collaboration,
  ) {
    return {
      'sessionId': collaboration['sessionId'],
      'goal': collaboration['goal'],
      'mode': collaboration['mode'],
      'status': collaboration['status'],
      'autoAcceptLowRisk': collaboration['autoAcceptLowRisk'],
      'participants': _a2aCollaborationParticipantLabels(collaboration),
      'displayText': _a2aCollaborationDisplayText(collaboration),
      'createdAt': collaboration['createdAt'],
      'updatedAt': collaboration['updatedAt'],
      if ((collaboration['summary']?.toString() ?? '').isNotEmpty)
        'summary': collaboration['summary'],
    };
  }

  List<Map<String, dynamic>> _a2aCollaborationParticipantLabels(
    Map<String, dynamic> collaboration,
  ) {
    final participants = collaboration['participants'];
    if (participants is! List) return const [];
    return participants
        .whereType<Map>()
        .map((item) {
          final displayLabel = item['displayLabel']?.toString().trim() ?? '';
          final label = displayLabel.isNotEmpty
              ? displayLabel
              : _a2aParticipantDisplayLabel(
                  item,
                  item['peerId']?.toString() ?? '',
                );
          return {'displayLabel': label};
        })
        .where((item) => (item['displayLabel'] ?? '').isNotEmpty)
        .toList(growable: false);
  }

  String _a2aCollaborationDisplayText(Map<String, dynamic> collaboration) {
    final participants = collaboration['participants'];
    if (participants is! List || participants.isEmpty) {
      return '附近 Agent 对话';
    }
    final labels = participants
        .whereType<Map>()
        .map((item) {
          final displayLabel = item['displayLabel']?.toString().trim();
          if (displayLabel != null && displayLabel.isNotEmpty) {
            return displayLabel;
          }
          final displayName = item['displayName']?.toString().trim() ?? '';
          if (displayName.isEmpty || displayName.toLowerCase() == 'napaxi') {
            return _a2aDefaultPeerDisplayLabel(
              item['peerId']?.toString() ?? '',
            );
          }
          return displayName;
        })
        .where((item) => item.isNotEmpty)
        .toList(growable: false);
    if (labels.isEmpty) return '附近 Agent 对话';
    return '正在和 ${labels.join('、')} 对话';
  }

  Future<Map<String, dynamic>> _a2aCollaborationForSend(
    String sessionId,
    Map<String, dynamic> params,
    sdk.A2ALocalTransportStatus status,
  ) async {
    final existing = await _a2aLoadCollaboration(sessionId);
    if (existing != null) return existing;
    final now = DateTime.now().toUtc().toIso8601String();
    final safetyBudget = (_int(params['safetyBudget']) ?? 12).clamp(1, 24);
    final collaboration = <String, dynamic>{
      'sessionId': sessionId,
      'goal': (params['goal'] as String? ?? 'A2A collaboration').trim(),
      'mode': (params['mode'] as String? ?? 'consult').trim(),
      'status': 'active',
      'leaderPeerId': status.peerId,
      'leaderAgentId': _currentAgentId ?? _runtimeProfile.agentId,
      'safetyBudget': safetyBudget,
      'exchangeCount': 0,
      'autoAcceptLowRisk': params['autoAcceptLowRisk'] as bool? ?? true,
      'participants': const <Map<String, dynamic>>[],
      'createdAt': now,
      'updatedAt': now,
    };
    await _a2aUpsertCollaboration(collaboration);
    return collaboration;
  }

  List<sdk.A2APeer> _a2aTargetsForSend(
    List<sdk.A2APeer> peers,
    Map<String, dynamic> collaboration,
    String? explicitTarget,
  ) {
    final target = explicitTarget?.trim() ?? '';
    if (target.isNotEmpty) {
      final peer = _a2aResolvePeer(target, peers);
      return peer == null || !_a2aPeerAvailable(peer) ? const [] : [peer];
    }
    final participants = collaboration['participants'];
    if (participants is! List) return const [];
    final resolved = <sdk.A2APeer>[];
    for (final participant in participants) {
      if (participant is! Map) continue;
      final peerId = participant['peerId']?.toString().trim() ?? '';
      final peer = _a2aResolvePeer(peerId, peers);
      if (peer != null &&
          _a2aPeerAvailable(peer) &&
          !resolved.any((item) => item.peerId == peer.peerId)) {
        resolved.add(peer);
      }
    }
    return resolved;
  }

  Map<String, dynamic> _a2aCollaborationContext({
    required Map<String, dynamic> collaboration,
    required String turnId,
    required String fromPeerId,
    required String toPeerId,
    required String message,
    required String intent,
    required bool expectsReply,
    List<sdk.A2AArtifact> artifacts = const [],
    List<String> conversationHistory = const [],
  }) {
    final artifactSummaries = _a2aArtifactSummaryList(artifacts);
    return {
      'a2aCollaboration': {
        'version': 1,
        'sessionId': collaboration['sessionId'],
        'goal': collaboration['goal'],
        'mode': collaboration['mode'],
        'status': collaboration['status'],
        'turnKind': 'conversation_turn',
        'turnId': turnId,
        'leaderPeerId': collaboration['leaderPeerId'],
        'leaderAgentId': collaboration['leaderAgentId'],
        'fromPeerId': fromPeerId,
        'toPeerId': toPeerId,
        'intent': intent,
        'message': message,
        'expectsReply': expectsReply,
        if (artifactSummaries.isNotEmpty) 'artifacts': artifactSummaries,
        'autoAcceptLowRisk': collaboration['autoAcceptLowRisk'] == true,
        'risk': 'low',
        'participants': collaboration['participants'] ?? const [],
        'conversationHistory': conversationHistory,
        'createdAt': DateTime.now().toUtc().toIso8601String(),
      },
      'conversationTurn': {
        'version': 1,
        'kind': 'conversation_turn',
        'conversationId': collaboration['sessionId'],
        'turnId': turnId,
        'fromPeerId': fromPeerId,
        'toPeerId': toPeerId,
        'text': message,
        'sentIntent': intent,
        'expectsReply': expectsReply,
        if (artifactSummaries.isNotEmpty) 'artifacts': artifactSummaries,
        'createdAt': DateTime.now().toUtc().toIso8601String(),
      },
    };
  }

  String _a2aCollaborationPrompt({
    required Map<String, dynamic> collaboration,
    required String message,
    required String intent,
    required bool expectsReply,
    List<sdk.A2AArtifact> artifacts = const [],
    List<String> conversationHistory = const [],
  }) {
    final goal = collaboration['goal']?.toString() ?? '';
    final mode = collaboration['mode']?.toString() ?? 'consult';
    final artifactSummaries = _a2aArtifactSummaryList(artifacts);
    return [
      'A trusted nearby Agent is collaborating with you over local A2A.',
      '',
      'Mode: $mode',
      'Goal: $goal',
      'Intent: $intent',
      '',
      if (conversationHistory.isNotEmpty) ...[
        'Conversation so far:',
        ...conversationHistory,
        '',
      ],
      'Message from the other Agent:',
      message,
      '',
      if (artifactSummaries.isNotEmpty) ...[
        'Attached artifacts:',
        for (final artifact in artifactSummaries)
          '- ${artifact['name'] ?? artifact['artifactId'] ?? 'artifact'} (${artifact['mimeType'] ?? 'unknown'})',
        '',
        'Use the attached artifact context only when it is relevant. Do not invent visual or file contents that are not present in the attachment/tool result.',
        '',
      ],
      'Treat this as one turn in an ongoing Agent conversation, not as a one-shot task.',
      if (expectsReply) ...[
        'Your reply may be a question, clarification request, critique, proposal, partial finding, or final answer.',
        'If more exchange is needed, ask the other Agent directly and leave room for the conversation to continue.',
        'Do not pretend the discussion is complete just because you received one message.',
      ] else
        'This message does not require a reply. Record the information and respond briefly only if a short acknowledgement is useful.',
      '',
      'Your output will be delivered as the next natural-language conversation turn.',
      'Write naturally, like an assistant speaking to another assistant in a conversation.',
      'Do not infer the remote Agent opinion or close the discussion.',
      'Do not mention peerId, sessionId, taskId, endpoints, transport, delivery status, or other A2A protocol details unless explicitly asked for diagnostics.',
      'Do not expose unrelated private data. Stay within this collaboration goal.',
    ].join('\n');
  }

  List<String> _a2aConversationHistoryForPrompt(
    String sessionId, {
    required String localLabel,
    required String remoteLabel,
    int maxTurns = 6,
  }) {
    final engine = _requireEngine();
    final rows = <({int atMs, String line})>[];
    for (final task in engine.a2a.listTasks(limit: 200)) {
      if (task.source != 'local_transport_outbound') continue;
      final collaboration = task.request.context['a2aCollaboration'];
      if (collaboration is! Map) continue;
      if (collaboration['sessionId']?.toString() != sessionId) continue;
      final sentAt = _isoMs(task.createdAt) ?? 0;
      final message = collaboration['message']?.toString().trim() ?? '';
      if (message.isNotEmpty) {
        rows.add((atMs: sentAt, line: '$localLabel: $message'));
      }
      final reply = task.summary?.trim() ?? '';
      if (reply.isNotEmpty) {
        rows.add((
          atMs: _isoMs(task.updatedAt) ?? sentAt,
          line: '$remoteLabel: $reply',
        ));
      }
    }
    rows.sort((a, b) => a.atMs.compareTo(b.atMs));
    final compact = rows.map((item) => item.line).toList(growable: false);
    if (compact.length <= maxTurns * 2) return compact;
    return compact.sublist(compact.length - maxTurns * 2);
  }

  Future<List<Map<String, dynamic>>> _a2aCollaborationObservations(
    String sessionId, {
    int? sinceMs,
    bool includeProgress = false,
  }) async {
    final engine = _requireEngine();
    final observations = <Map<String, dynamic>>[];
    for (final task in engine.a2a.listTasks(limit: 100)) {
      final collaboration = task.request.context['a2aCollaboration'];
      if (collaboration is! Map) continue;
      if (collaboration['sessionId']?.toString() != sessionId) continue;
      final updatedMs = _isoMs(task.updatedAt);
      if (sinceMs != null && updatedMs != null && updatedMs <= sinceMs) {
        continue;
      }
      final status = task.status.trim().toLowerCase();
      final text = (task.error?.trim().isNotEmpty ?? false)
          ? task.error!.trim()
          : (task.summary?.trim() ?? '');
      final finalStatus =
          status == 'succeeded' ||
          status == 'failed' ||
          status == 'rejected' ||
          status == 'cancelled';
      if (task.source != 'local_transport_outbound') continue;
      if (!includeProgress && !finalStatus) continue;
      if (text.isEmpty) continue;
      final resolvedArtifacts =
          await (_owner?._resolveLocalA2ABlobArtifacts(
                task.resultArtifacts,
                timeout: const Duration(milliseconds: 300),
              ) ??
              Future.value(task.resultArtifacts));
      observations.add({
        'kind': 'task',
        'taskId': task.taskId,
        'status': task.status,
        'source': task.source,
        'peerMessageId': task.peerMessageId,
        'sessionId': sessionId,
        'fromPeerId': collaboration['fromPeerId'],
        'toPeerId': collaboration['toPeerId'],
        'turnKind':
            collaboration['turnKind']?.toString().trim().isNotEmpty == true
            ? collaboration['turnKind']
            : 'conversation_turn',
        'turnId': collaboration['turnId'] ?? task.taskId,
        'replyToTurnId': collaboration['turnId'] ?? task.taskId,
        'displayLabel': _a2aParticipantDisplayLabel(
          collaboration,
          collaboration['toPeerId']?.toString() ?? '',
        ),
        'sentIntent': collaboration['intent'],
        'message': collaboration['message'] ?? task.request.message,
        'summary': task.summary,
        if (resolvedArtifacts.isNotEmpty)
          'artifacts': _a2aArtifactSummaryList(resolvedArtifacts),
        if (resolvedArtifacts.isNotEmpty)
          'visibleArtifacts': _a2aLocalDisplayArtifactJsonList(
            resolvedArtifacts,
          ),
        'error': task.error,
        'text': text,
        'updatedAt': task.updatedAt,
        'updatedAtMs': updatedMs,
      });
    }
    observations.sort(
      (a, b) => ((a['updatedAtMs'] as int?) ?? 0).compareTo(
        (b['updatedAtMs'] as int?) ?? 0,
      ),
    );
    return observations;
  }

  Map<String, dynamic>? _a2aObservationMessageJson(
    Map<String, dynamic> observation,
  ) {
    final text = observation['text']?.toString().trim() ?? '';
    if (text.isEmpty) return null;
    final label = observation['displayLabel']?.toString().trim() ?? '';
    final remoteIntent = observation['remoteIntent']?.toString().trim();
    final speechAct = _a2aSpeechActForText(text, remoteIntent: remoteIntent);
    final requiresResponse = _a2aMessageRequiresResponse(
      text,
      speechAct: speechAct,
      remoteIntent: remoteIntent,
    );
    return {
      'displayLabel': label.isEmpty ? '附近 Agent' : label,
      'text': text,
      if (observation['artifacts'] is List)
        'artifacts': observation['artifacts'],
      if (observation['visibleArtifacts'] is List)
        'visibleArtifacts': observation['visibleArtifacts'],
      'updatedAtMs': observation['updatedAtMs'],
      if (remoteIntent != null && remoteIntent.isNotEmpty)
        'remoteIntent': remoteIntent,
      'speechAct': speechAct,
      'requiresResponse': requiresResponse,
      'conversationOpen': requiresResponse,
    };
  }

  String _a2aSpeechActForText(String text, {String? remoteIntent}) {
    final normalizedIntent = remoteIntent?.trim().toLowerCase() ?? '';
    if (normalizedIntent == 'question' || normalizedIntent == 'clarification') {
      return 'question';
    }
    if (normalizedIntent == 'critique') return 'critique';
    if (normalizedIntent == 'proposal') return 'proposal';
    if (normalizedIntent == 'final_summary') return 'final_summary';
    if (_a2aLooksLikeQuestion(text)) return 'question';
    return 'statement';
  }

  bool _a2aMessageRequiresResponse(
    String text, {
    required String speechAct,
    String? remoteIntent,
  }) {
    final normalizedIntent = remoteIntent?.trim().toLowerCase() ?? '';
    if (normalizedIntent == 'final_summary') return false;
    if (speechAct == 'question' || speechAct == 'critique') return true;
    if (normalizedIntent == 'question' ||
        normalizedIntent == 'clarification' ||
        normalizedIntent == 'critique') {
      return true;
    }
    return _a2aLooksLikeQuestion(text);
  }

  bool _a2aLooksLikeQuestion(String text) {
    final value = text.trim();
    if (value.isEmpty) return false;
    if (value.contains('?') || value.contains('？')) return true;
    return RegExp(
      r'(吗|么|呢|是否|能否|可否|是不是|有没有|为什么|怎么|如何|哪[个些里]?|什么|要不要|需不需要|能不能)',
    ).hasMatch(value);
  }

  String _a2aParticipantDisplayLabel(
    Map<dynamic, dynamic> collaboration,
    String peerId,
  ) {
    final participants = collaboration['participants'];
    if (participants is List) {
      for (final participant in participants) {
        if (participant is! Map) continue;
        if (participant['peerId']?.toString() != peerId) continue;
        final displayLabel = participant['displayLabel']?.toString().trim();
        if (displayLabel != null && displayLabel.isNotEmpty) {
          return displayLabel;
        }
        final displayName = participant['displayName']?.toString().trim() ?? '';
        if (displayName.isNotEmpty && displayName.toLowerCase() != 'napaxi') {
          return displayName;
        }
      }
    }
    return _a2aDefaultPeerDisplayLabel(peerId);
  }

  String _newA2ACollaborationId() {
    final now = DateTime.now().toUtc().millisecondsSinceEpoch;
    final suffix = math.Random().nextInt(0xFFFFFF).toRadixString(16);
    return 'a2a-collab-$now-$suffix';
  }

  String _newA2ATaskId(String sessionId) {
    final now = DateTime.now().toUtc().millisecondsSinceEpoch;
    final safeSession = sessionId
        .replaceAll(RegExp(r'[^A-Za-z0-9_.-]'), '_')
        .replaceAll(RegExp(r'_+'), '_');
    final suffix = math.Random().nextInt(0xFFFFFF).toRadixString(16);
    return '$safeSession-task-$now-$suffix';
  }

  int? _isoMs(String value) {
    final parsed = DateTime.tryParse(value);
    return parsed?.toUtc().millisecondsSinceEpoch;
  }

  List<String> _stringList(Object? value) {
    if (value is String) {
      return value
          .split(',')
          .map((item) => item.trim())
          .where((item) => item.isNotEmpty)
          .toList(growable: false);
    }
    if (value is! List) return const [];
    return value
        .map((item) => item.toString().trim())
        .where((item) => item.isNotEmpty)
        .toList(growable: false);
  }

  int? _int(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value.trim());
    return null;
  }

  List<int>? _intList(Object? value) {
    if (value is! List) return null;
    return value.map(_int).whereType<int>().toList(growable: false);
  }
}

class _DemoAgentAppActionExecutor extends sdk.AgentAppActionExecutor {
  _DemoAgentAppActionExecutor({this.androidExecutor, this.iosExecutor});

  final sdk.AgentAppActionExecutor? androidExecutor;
  final sdk.AgentAppActionExecutor? iosExecutor;

  @override
  Future<sdk.AgentAppActionResult> execute(
    sdk.AgentAppActionRequest request,
  ) async {
    final binding = request.package['install_binding'];
    if (binding is Map) {
      if (binding['platform'] == 'android' && androidExecutor != null) {
        return androidExecutor!.execute(request);
      }
      if (binding['platform'] == 'ios' && iosExecutor != null) {
        return iosExecutor!.execute(request);
      }
    }
    return sdk.AgentAppActionResult(
      requestId: request.proposal.requestId,
      status: 'succeeded',
      result: {
        'ok': true,
        'action_id': request.proposal.actionId,
        'arguments': request.proposal.arguments,
      },
      providerTraceId: 'demo-${request.proposal.requestId}',
      completedAt: DateTime.now().toUtc().toIso8601String(),
    );
  }
}
