part of '../main.dart';

enum ChatRole { user, assistant }

enum ChatMessageAction { openConfiguration }

enum ChatEvolutionStage { reviewing, reviewed, updated, pending, failed }

class ChatEvolutionStatus {
  const ChatEvolutionStatus({
    required this.runIds,
    required this.reviewTypes,
    required this.stage,
    this.autoAppliedCount = 0,
    this.pendingCount = 0,
  });

  final List<String> runIds;
  final List<String> reviewTypes;
  final ChatEvolutionStage stage;
  final int autoAppliedCount;
  final int pendingCount;
}

class HumanRequest {
  const HumanRequest({
    required this.requestId,
    required this.question,
    this.options = const [],
    this.context,
    this.answered = false,
    this.cancelled = false,
  });

  final String requestId;
  final String question;
  final List<String> options;
  final String? context;
  final bool answered;
  final bool cancelled;

  HumanRequest copyWith({bool? answered, bool? cancelled}) {
    return HumanRequest(
      requestId: requestId,
      question: question,
      options: options,
      context: context,
      answered: answered ?? this.answered,
      cancelled: cancelled ?? this.cancelled,
    );
  }
}

enum PendingInterjectionStatus { queued, failed }

class PendingInterjection {
  const PendingInterjection({
    required this.id,
    required this.content,
    required this.createdAt,
    this.attachments = const [],
    this.attachmentCount = 0,
    this.retractsFromSdk = true,
    this.status = PendingInterjectionStatus.queued,
  });

  final String id;
  final String content;
  final DateTime createdAt;
  final List<ChatAttachment> attachments;
  final int attachmentCount;
  final bool retractsFromSdk;
  final PendingInterjectionStatus status;

  PendingInterjection copyWith({PendingInterjectionStatus? status}) {
    return PendingInterjection(
      id: id,
      content: content,
      createdAt: createdAt,
      attachments: attachments,
      attachmentCount: attachmentCount,
      retractsFromSdk: retractsFromSdk,
      status: status ?? this.status,
    );
  }
}

class AgentToolOutputChunk {
  const AgentToolOutputChunk({required this.stream, required this.content});

  final String stream;
  final String content;

  bool get isStderr => stream == 'stderr';
}

class AgentToolCall {
  const AgentToolCall({
    required this.callId,
    required this.name,
    required this.arguments,
    this.historyMessageId,
    this.output,
    this.isError = false,
    this.streamingOutput = '',
    this.outputChunks = const [],
    required this.startedAt,
    this.completedAt,
    this.interrupted = false,
    this.awaitingHuman = false,
    this.outputTruncated = false,
    this.argumentsTruncated = false,
  });

  final String callId;
  final String name;
  final String arguments;
  final String? historyMessageId;
  final String? output;
  final bool isError;
  final String streamingOutput;
  final List<AgentToolOutputChunk> outputChunks;
  final DateTime startedAt;
  final DateTime? completedAt;
  final bool interrupted;
  final bool awaitingHuman;
  final bool outputTruncated;
  final bool argumentsTruncated;

  bool get isComplete =>
      completedAt != null || output != null || interrupted || awaitingHuman;

  Duration? get duration {
    final end = completedAt;
    if (end == null) return null;
    return end.difference(startedAt);
  }

  AgentToolCall copyWith({
    String? name,
    String? arguments,
    String? historyMessageId,
    String? output,
    bool clearOutput = false,
    bool? isError,
    String? streamingOutput,
    List<AgentToolOutputChunk>? outputChunks,
    DateTime? completedAt,
    bool? interrupted,
    bool? awaitingHuman,
    bool? outputTruncated,
    bool? argumentsTruncated,
  }) {
    return AgentToolCall(
      callId: callId,
      name: name ?? this.name,
      arguments: arguments ?? this.arguments,
      historyMessageId: historyMessageId ?? this.historyMessageId,
      output: clearOutput ? null : output ?? this.output,
      isError: isError ?? this.isError,
      streamingOutput: streamingOutput ?? this.streamingOutput,
      outputChunks: outputChunks ?? this.outputChunks,
      startedAt: startedAt,
      completedAt: completedAt ?? this.completedAt,
      interrupted: interrupted ?? this.interrupted,
      awaitingHuman: awaitingHuman ?? this.awaitingHuman,
      outputTruncated: outputTruncated ?? this.outputTruncated,
      argumentsTruncated: argumentsTruncated ?? this.argumentsTruncated,
    );
  }
}

class AgentTraceStep {
  const AgentTraceStep({this.reasoning = '', this.toolCalls = const []});

  final String reasoning;
  final List<AgentToolCall> toolCalls;

  bool get isEmpty => reasoning.trim().isEmpty && toolCalls.isEmpty;

  AgentTraceStep copyWith({String? reasoning, List<AgentToolCall>? toolCalls}) {
    return AgentTraceStep(
      reasoning: reasoning ?? this.reasoning,
      toolCalls: toolCalls ?? this.toolCalls,
    );
  }
}

class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.role,
    required this.content,
    required this.createdAt,
    this.attachments = const [],
    this.reasoning = '',
    this.toolCalls = const [],
    this.traceSteps = const [],
    this.activatedSkills = const [],
    this.pinnedSkillNames = const [],
    this.humanRequest,
    this.isStreaming = false,
    this.action,
    this.evolutionStatus,
    this.completedAt,
  });

  final String id;
  final ChatRole role;
  final String content;
  final DateTime createdAt;
  final List<ChatAttachment> attachments;
  final String reasoning;
  final List<AgentToolCall> toolCalls;
  final List<AgentTraceStep> traceSteps;
  final List<sdk.ActivatedSkillInfo> activatedSkills;
  final List<String> pinnedSkillNames;
  final HumanRequest? humanRequest;
  final bool isStreaming;
  final ChatMessageAction? action;
  final ChatEvolutionStatus? evolutionStatus;
  final DateTime? completedAt;

  bool get isUser => role == ChatRole.user;

  Duration? get duration {
    final end = completedAt;
    if (end == null) return null;
    return end.difference(createdAt);
  }

  ChatMessage copyWith({
    ChatRole? role,
    String? content,
    List<ChatAttachment>? attachments,
    String? reasoning,
    List<AgentToolCall>? toolCalls,
    List<AgentTraceStep>? traceSteps,
    List<sdk.ActivatedSkillInfo>? activatedSkills,
    List<String>? pinnedSkillNames,
    HumanRequest? humanRequest,
    bool? isStreaming,
    ChatMessageAction? action,
    ChatEvolutionStatus? evolutionStatus,
    bool clearAction = false,
    bool clearEvolutionStatus = false,
    DateTime? completedAt,
  }) {
    return ChatMessage(
      id: id,
      role: role ?? this.role,
      content: content ?? this.content,
      attachments: attachments ?? this.attachments,
      createdAt: createdAt,
      reasoning: reasoning ?? this.reasoning,
      toolCalls: toolCalls ?? this.toolCalls,
      traceSteps: traceSteps ?? this.traceSteps,
      activatedSkills: activatedSkills ?? this.activatedSkills,
      pinnedSkillNames: pinnedSkillNames ?? this.pinnedSkillNames,
      humanRequest: humanRequest ?? this.humanRequest,
      isStreaming: isStreaming ?? this.isStreaming,
      action: clearAction ? null : action ?? this.action,
      evolutionStatus: clearEvolutionStatus
          ? null
          : evolutionStatus ?? this.evolutionStatus,
      completedAt: completedAt ?? this.completedAt,
    );
  }
}

enum ChatAttachmentType { image, file }

enum ChatAttachmentPreviewKind { image, video, audio, html, webLink, file }

class ChatAttachment {
  const ChatAttachment({
    required this.name,
    required this.path,
    required this.type,
    this.sandboxPath,
    this.mimeTypeOverride,
  });

  final String name;
  final String path;
  final ChatAttachmentType type;
  final String? sandboxPath;
  final String? mimeTypeOverride;

  String get extension {
    final dotIndex = name.lastIndexOf('.');
    if (dotIndex == -1 || dotIndex == name.length - 1) return '';
    return name.substring(dotIndex + 1).toLowerCase();
  }

  String get _mimeTypeHint => mimeTypeOverride?.trim().toLowerCase() ?? '';

  bool get isImage =>
      type == ChatAttachmentType.image || _mimeTypeHint.startsWith('image/');

  bool get isVideo =>
      _mimeTypeHint.startsWith('video/') ||
      const {'mp4', 'mov', 'm4v', 'webm', 'avi', 'mkv'}.contains(extension);

  bool get isAudio =>
      _mimeTypeHint.startsWith('audio/') ||
      const {'mp3', 'wav', 'aac', 'flac', 'ogg', 'm4a'}.contains(extension);

  bool get isHtml =>
      _mimeTypeHint == 'text/html' || const {'html', 'htm'}.contains(extension);

  bool get isWebLink {
    final value = path.trim().isNotEmpty ? path.trim() : name.trim();
    final uri = Uri.tryParse(value);
    return uri != null && (uri.scheme == 'http' || uri.scheme == 'https');
  }

  ChatAttachmentPreviewKind get previewKind {
    if (isWebLink) return ChatAttachmentPreviewKind.webLink;
    if (isHtml) return ChatAttachmentPreviewKind.html;
    if (isImage) return ChatAttachmentPreviewKind.image;
    if (isVideo) return ChatAttachmentPreviewKind.video;
    if (isAudio) return ChatAttachmentPreviewKind.audio;
    return ChatAttachmentPreviewKind.file;
  }

  String get typeLabel {
    if (isImage) return 'Image';
    if (isVideo) return 'Video';
    if (isAudio) return 'Audio';
    if (isHtml) return 'HTML';
    if (isWebLink) return 'Link';
    return switch (extension) {
      'pdf' => 'PDF',
      'doc' || 'docx' => 'Word',
      'xls' || 'xlsx' => 'Excel',
      'ppt' || 'pptx' => 'PowerPoint',
      'txt' => 'Text',
      'json' => 'JSON',
      'csv' => 'CSV',
      'zip' || 'rar' || '7z' => 'Archive',
      '' => 'File',
      _ => extension.toUpperCase(),
    };
  }

  String get mimeType {
    final override = mimeTypeOverride?.trim();
    if (override != null && override.isNotEmpty) return override;
    if (isImage) {
      return switch (extension) {
        'png' => 'image/png',
        'webp' => 'image/webp',
        'gif' => 'image/gif',
        _ => 'image/jpeg',
      };
    }
    if (isVideo) {
      return switch (extension) {
        'webm' => 'video/webm',
        'mov' || 'm4v' => 'video/quicktime',
        _ => 'video/mp4',
      };
    }
    if (isAudio) {
      return switch (extension) {
        'wav' => 'audio/wav',
        'aac' => 'audio/aac',
        'flac' => 'audio/flac',
        'ogg' => 'audio/ogg',
        _ => 'audio/mpeg',
      };
    }
    if (isHtml) return 'text/html';
    return switch (extension) {
      'pdf' => 'application/pdf',
      'json' => 'application/json',
      'csv' => 'text/csv',
      'txt' => 'text/plain',
      'doc' => 'application/msword',
      'docx' =>
        'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
      'xls' => 'application/vnd.ms-excel',
      'xlsx' =>
        'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      'ppt' => 'application/vnd.ms-powerpoint',
      'pptx' =>
        'application/vnd.openxmlformats-officedocument.presentationml.presentation',
      'zip' => 'application/zip',
      _ => 'application/octet-stream',
    };
  }
}

class FavoriteAttachment {
  const FavoriteAttachment({
    required this.id,
    required this.attachment,
    required this.createdAt,
    this.accountId = _demoAccountId,
    this.agentId = sdk.NapaxiEngine.defaultAgentId,
  });

  final String id;
  final ChatAttachment attachment;
  final DateTime createdAt;
  final String accountId;
  final String agentId;

  Map<String, Object?> toMap() => {
    'id': id,
    'account_id': accountId,
    'agent_id': agentId,
    'name': attachment.name,
    'path': attachment.path,
    'type': attachment.type.name,
    'created_at': createdAt.toIso8601String(),
    if (attachment.sandboxPath != null &&
        attachment.sandboxPath!.trim().isNotEmpty)
      'sandbox_path': attachment.sandboxPath,
    if (attachment.mimeTypeOverride != null &&
        attachment.mimeTypeOverride!.trim().isNotEmpty)
      'mime_type': attachment.mimeTypeOverride,
  };

  factory FavoriteAttachment.fromMap(Map<String, Object?> map) {
    final rawType = map['type'] as String? ?? ChatAttachmentType.file.name;
    return FavoriteAttachment(
      id: map['id'] as String? ?? '',
      accountId: map['account_id'] as String? ?? _demoAccountId,
      agentId: map['agent_id'] as String? ?? sdk.NapaxiEngine.defaultAgentId,
      attachment: ChatAttachment(
        name: map['name'] as String? ?? 'Attachment',
        path: map['path'] as String? ?? '',
        type: rawType == ChatAttachmentType.image.name
            ? ChatAttachmentType.image
            : ChatAttachmentType.file,
        sandboxPath: map['sandbox_path'] as String?,
        mimeTypeOverride: map['mime_type'] as String?,
      ),
      createdAt: _parseStoredDate(map['created_at'] as String? ?? ''),
    );
  }
}

String _attachmentFavoriteId(ChatAttachment attachment) {
  final sandboxPath = attachment.sandboxPath?.trim();
  if (sandboxPath != null && sandboxPath.isNotEmpty) {
    return 'sandbox:$sandboxPath';
  }
  final path = attachment.path.trim();
  if (path.isNotEmpty) return 'path:$path';
  return 'name:${attachment.name.trim()}|mime:${attachment.mimeType}';
}

bool _favoriteMatchesAttachment(
  FavoriteAttachment favorite,
  ChatAttachment attachment,
) {
  if (favorite.id == _attachmentFavoriteId(attachment)) return true;
  return _sameUploadedAttachmentFavorite(favorite.attachment, attachment);
}

List<FavoriteAttachment> _dedupeFavoriteAttachments(
  Iterable<FavoriteAttachment> favorites,
) {
  final deduped = <FavoriteAttachment>[];
  for (final favorite in favorites) {
    final existingIndex = deduped.indexWhere((existing) {
      final sameScope =
          existing.accountId == favorite.accountId &&
          existing.agentId == favorite.agentId;
      return sameScope &&
          (existing.id == favorite.id ||
              _sameUploadedAttachmentFavorite(
                existing.attachment,
                favorite.attachment,
              ));
    });
    if (existingIndex == -1) {
      deduped.add(favorite);
      continue;
    }
    deduped[existingIndex] = _preferredFavoriteAttachment(
      deduped[existingIndex],
      favorite,
    );
  }
  return List.unmodifiable(deduped);
}

FavoriteAttachment _preferredFavoriteAttachment(
  FavoriteAttachment current,
  FavoriteAttachment candidate,
) {
  final currentScore = _favoriteMetadataScore(current);
  final candidateScore = _favoriteMetadataScore(candidate);
  if (candidateScore != currentScore) {
    return candidateScore > currentScore ? candidate : current;
  }
  return candidate.createdAt.isAfter(current.createdAt) ? candidate : current;
}

int _favoriteMetadataScore(FavoriteAttachment favorite) {
  final attachment = favorite.attachment;
  var score = 0;
  if (_hasUploadedAttachmentSandboxIdentity(attachment)) score += 4;
  if ((attachment.sandboxPath ?? '').trim().isNotEmpty) score += 2;
  if (attachment.path.trim().isNotEmpty) score += 1;
  if ((attachment.mimeTypeOverride ?? '').trim().isNotEmpty) score += 1;
  return score;
}

bool _sameUploadedAttachmentFavorite(ChatAttachment a, ChatAttachment b) {
  final aSandboxPath = _uploadedAttachmentSandboxPath(a);
  final bSandboxPath = _uploadedAttachmentSandboxPath(b);
  if (aSandboxPath == null && bSandboxPath == null) {
    return false;
  }
  if (aSandboxPath != null && bSandboxPath != null) {
    return aSandboxPath == bSandboxPath;
  }
  final aName = _normalizedAttachmentBasename(a);
  final bName = _normalizedAttachmentBasename(b);
  if (aName.isEmpty || aName != bName) return false;
  return a.mimeType.trim().toLowerCase() == b.mimeType.trim().toLowerCase();
}

bool _hasUploadedAttachmentSandboxIdentity(ChatAttachment attachment) {
  return _uploadedAttachmentSandboxPath(attachment) != null;
}

String? _uploadedAttachmentSandboxPath(ChatAttachment attachment) {
  final sandboxPath = attachment.sandboxPath?.trim();
  if (sandboxPath != null && _isUploadedAttachmentSandboxPath(sandboxPath)) {
    return sandboxPath;
  }
  final path = attachment.path.trim();
  return _isUploadedAttachmentSandboxPath(path) ? path : null;
}

bool _isUploadedAttachmentSandboxPath(String path) {
  if (path == '/workspace/attachments' ||
      path.startsWith('/workspace/attachments/')) {
    return true;
  }
  return path.contains('/workspace/attachments/');
}

String _normalizedAttachmentBasename(ChatAttachment attachment) {
  final name = attachment.name.trim();
  if (name.isNotEmpty) return name.toLowerCase();
  final path = attachment.path.trim();
  if (path.isEmpty) return '';
  return path.replaceAll('\\', '/').split('/').last.toLowerCase();
}

DateTime _parseStoredDate(String value) {
  return DateTime.tryParse(value) ?? DateTime.now();
}

int _nextSessionNumber(List<ChatSession> sessions) {
  var maxNumber = 0;
  for (final session in sessions) {
    final match = RegExp(r'^session-(\d+)$').firstMatch(session.id);
    final number = int.tryParse(match?.group(1) ?? '');
    if (number != null && number > maxNumber) maxNumber = number;
  }
  return maxNumber + 1;
}

int _nextMessageNumber(List<ChatSession> sessions) {
  var maxNumber = 0;
  for (final session in sessions) {
    for (final message in session.messages) {
      final match = RegExp(
        r'^(?:user|assistant)-(\d+)$',
      ).firstMatch(message.id);
      final number = int.tryParse(match?.group(1) ?? '');
      if (number != null && number > maxNumber) maxNumber = number;
    }
  }
  return maxNumber + 1;
}

List<ChatMessage> _messagesFromSdkHistory(
  List<sdk.ChatMessage> history, {
  required String accountId,
  required String agentId,
  int generatedIdStart = 1,
}) {
  final messages = <ChatMessage>[];
  final pendingTraceSteps = <AgentTraceStep>[];
  final pendingToolCalls = <AgentToolCall>[];
  var pendingReasoning = '';
  var pendingStepReasoning = '';
  final pendingStepToolCalls = <AgentToolCall>[];
  var generatedId = generatedIdStart;

  ChatMessage newAssistantShell(DateTime createdAt) {
    return ChatMessage(
      id: 'assistant-${generatedId++}',
      role: ChatRole.assistant,
      content: '',
      createdAt: createdAt,
    );
  }

  String appendReasoning(String current, String next) {
    final trimmedNext = next.trim();
    if (trimmedNext.isEmpty) return current;
    final trimmedCurrent = current.trim();
    if (trimmedCurrent.isEmpty) return next;
    if (trimmedCurrent.contains(trimmedNext)) return current;
    if (trimmedNext.contains(trimmedCurrent)) return next;
    return '$current\n$next';
  }

  bool appendPendingReasoning(String reasoning) {
    final before = pendingReasoning;
    pendingReasoning = appendReasoning(pendingReasoning, reasoning);
    return pendingReasoning != before;
  }

  void flushPendingStep() {
    final step = AgentTraceStep(
      reasoning: _sanitizeA2AProtocolText(pendingStepReasoning),
      toolCalls: List.unmodifiable(pendingStepToolCalls),
    );
    if (!step.isEmpty) pendingTraceSteps.add(step);
    pendingStepReasoning = '';
    pendingStepToolCalls.clear();
  }

  void flushPendingTrace(DateTime createdAt) {
    flushPendingStep();
    final reasoning = _sanitizeA2AProtocolText(pendingReasoning);
    final toolCalls = List<AgentToolCall>.unmodifiable(pendingToolCalls);
    final traceSteps = List<AgentTraceStep>.unmodifiable(pendingTraceSteps);
    if (reasoning.trim().isEmpty && toolCalls.isEmpty && traceSteps.isEmpty) {
      pendingReasoning = '';
      pendingToolCalls.clear();
      pendingTraceSteps.clear();
      return;
    }
    messages.add(
      newAssistantShell(createdAt).copyWith(
        reasoning: reasoning,
        toolCalls: toolCalls,
        traceSteps: traceSteps,
      ),
    );
    pendingReasoning = '';
    pendingToolCalls.clear();
    pendingTraceSteps.clear();
  }

  for (final item in history) {
    final createdAt = _parseStoredDate(item.createdAt ?? '');
    if (item.isUser) {
      flushPendingTrace(createdAt);
      messages.add(
        ChatMessage(
          id: item.id ?? '${item.role}-${generatedId++}',
          role: ChatRole.user,
          content: item.content,
          attachments: item.attachments
              .map(
                (attachment) => _attachmentFromSdk(
                  attachment,
                  accountId: accountId,
                  agentId: agentId,
                ),
              )
              .toList(),
          createdAt: createdAt,
        ),
      );
      continue;
    }
    if (item.isAskingHuman) {
      flushPendingTrace(createdAt);
      messages.add(
        ChatMessage(
          id: item.id ?? 'human-request-${generatedId++}',
          role: ChatRole.assistant,
          content: '',
          humanRequest: HumanRequest(
            requestId: item.humanRequestId ?? '',
            question: item.humanQuestion ?? item.content,
            options: item.humanOptions,
            context: item.humanContext,
            answered: !item.interrupted,
            cancelled: item.interrupted,
          ),
          createdAt: createdAt,
        ),
      );
      continue;
    }
    if (item.isAssistant) {
      flushPendingStep();
      final reasoning = _sanitizeA2AProtocolText(pendingReasoning);
      final toolCalls = List<AgentToolCall>.unmodifiable(pendingToolCalls);
      final traceSteps = List<AgentTraceStep>.unmodifiable(pendingTraceSteps);
      final content = _sanitizeA2AProtocolText(item.content);
      final attachments = item.attachments
          .map(
            (attachment) => _attachmentFromSdk(
              attachment,
              accountId: accountId,
              agentId: agentId,
            ),
          )
          .toList();
      pendingReasoning = '';
      pendingToolCalls.clear();
      pendingTraceSteps.clear();
      if (content.trim().isEmpty &&
          attachments.isEmpty &&
          reasoning.trim().isEmpty &&
          toolCalls.isEmpty &&
          traceSteps.isEmpty) {
        continue;
      }
      messages.add(
        ChatMessage(
          id: item.id ?? '${item.role}-${generatedId++}',
          role: ChatRole.assistant,
          content: content,
          attachments: attachments,
          reasoning: reasoning,
          toolCalls: toolCalls,
          traceSteps: traceSteps,
          createdAt: createdAt,
        ),
      );
      continue;
    }
    if (item.isThinking || item.isReasoning) {
      if (pendingStepToolCalls.isNotEmpty) flushPendingStep();
      final reasoning =
          item.thinkingContent ?? item.reasoningContent ?? item.content;
      if (appendPendingReasoning(reasoning)) {
        pendingStepReasoning = appendReasoning(pendingStepReasoning, reasoning);
      }
      continue;
    }
    if (item.isToolCalls) {
      final toolCalls = item.toolCalls ?? const [];
      final convertedCalls = [
        for (final call in toolCalls)
          if (!_isA2AToolName(call.name))
            _toolCallFromSdk(call, createdAt, historyMessageId: item.id),
      ];
      final reasoning = item.thinkingContent ?? item.reasoningContent;
      // CLI-engine backfill (Codex/CC) emits tool calls *after* the assistant
      // text of the same turn ([assistant → tool_calls]). Attach them back to
      // the preceding bare assistant when nothing is pending for a later
      // assistant. The check runs before the narrative below is folded into
      // pendingReasoning, and SDK-style order ([reasoning → tool_calls →
      // assistant]) always has pending reasoning here so it falls through to
      // the accumulate path unchanged.
      if (convertedCalls.isNotEmpty &&
          messages.isNotEmpty &&
          messages.last.role == ChatRole.assistant &&
          messages.last.toolCalls.isEmpty &&
          pendingReasoning.trim().isEmpty &&
          pendingStepToolCalls.isEmpty &&
          pendingTraceSteps.isEmpty) {
        final narrative = reasoning?.trim() ?? '';
        final prevReasoning = messages.last.reasoning;
        messages[messages.length - 1] = messages.last.copyWith(
          toolCalls: List<AgentToolCall>.unmodifiable(convertedCalls),
          reasoning: prevReasoning.trim().isEmpty && narrative.isNotEmpty
              ? narrative
              : prevReasoning,
        );
        continue;
      }
      if (reasoning != null) {
        final didAppendReasoning = appendPendingReasoning(reasoning);
        if (didAppendReasoning) {
          if (pendingStepToolCalls.isNotEmpty) flushPendingStep();
          pendingStepReasoning = appendReasoning(
            pendingStepReasoning,
            reasoning,
          );
        }
      }
      pendingToolCalls.addAll(convertedCalls);
      pendingStepToolCalls.addAll(convertedCalls);
    }
  }
  flushPendingTrace(DateTime.now());

  if (messages.isEmpty) {
    return [
      ChatMessage(
        id: 'welcome',
        role: ChatRole.assistant,
        content: AppStrings.english.welcomeMessage,
        createdAt: DateTime.now(),
      ),
    ];
  }
  return messages;
}

/// Test-only wrapper around [_messagesFromSdkHistory] so unit tests can assert
/// how history-item order (e.g. CLI-engine backfill `[assistant → tool_calls]`)
/// maps onto rendered messages without spinning up a widget tree.
@visibleForTesting
List<ChatMessage> messagesFromSdkHistoryForTesting(
  List<sdk.ChatMessage> history, {
  required String accountId,
  required String agentId,
}) =>
    _messagesFromSdkHistory(history, accountId: accountId, agentId: agentId);

ChatAttachment _attachmentFromSdk(
  sdk.ChatAttachment attachment, {
  required String accountId,
  required String agentId,
}) {
  final name =
      attachment.filename ??
      attachment.sandboxPath?.split(Platform.pathSeparator).last ??
      attachment.localPath?.split(Platform.pathSeparator).last ??
      'Attachment';
  final realPath = attachment.localPath?.trim().isNotEmpty == true
      ? attachment.localPath!.trim()
      : _resolveAttachmentRealPath(
          attachment,
          accountId: accountId,
          agentId: agentId,
        );
  return ChatAttachment(
    name: name,
    path: realPath,
    sandboxPath: attachment.sandboxPath,
    mimeTypeOverride: attachment.mimeType,
    type: attachment.kind == 'image' || attachment.mimeType.startsWith('image/')
        ? ChatAttachmentType.image
        : ChatAttachmentType.file,
  );
}

String _resolveAttachmentRealPath(
  sdk.ChatAttachment attachment, {
  required String accountId,
  required String agentId,
}) {
  final sandboxPath = attachment.sandboxPath;
  if (sandboxPath == null || sandboxPath.trim().isEmpty) {
    return '';
  }
  if (!sdk.NapaxiFileBridge.isInitialized) {
    return sandboxPath;
  }

  final resolved = sdk.NapaxiFileBridge.instance.sandboxToRealScoped(
    sandboxPath,
    accountId: accountId,
    agentId: agentId,
  );
  if (resolved != null && resolved.isNotEmpty) {
    return resolved;
  }

  if (!sandboxPath.startsWith('/workspace/')) {
    return sandboxPath;
  }

  final workspaceDir = sdk.NapaxiFileBridge.instance
      .workspaceDirScoped(accountId: accountId, agentId: agentId)
      .path;
  final relative = sandboxPath.substring('/workspace/'.length);
  return '$workspaceDir/$relative';
}

AgentToolCall _toolCallFromSdk(
  sdk.ToolCallInfo call,
  DateTime createdAt, {
  String? historyMessageId,
}) {
  final arguments = call.arguments == null ? '' : jsonEncode(call.arguments);
  final output = call.error ?? call.result;
  return AgentToolCall(
    callId: call.callId,
    name: call.name,
    arguments: arguments,
    historyMessageId: historyMessageId,
    output: output,
    isError: call.error != null,
    startedAt: createdAt,
    interrupted: call.interrupted,
    // Backfilled tool calls are always finished — they come from persisted
    // history. Without this, calls carrying no output (e.g. codex `webSearch`
    // or a successful `fileChange`) would render as "running".
    completedAt: createdAt,
    outputTruncated: call.resultTruncated || call.errorTruncated,
    argumentsTruncated: call.argumentsTruncated,
  );
}

class ChatSessionRunState {
  const ChatSessionRunState({
    required this.sessionKey,
    required this.agentId,
    required this.assistantMessageId,
    required this.subscription,
    required this.startedAt,
    required this.updatedAt,
    this.status = sdk.SessionRunStatus.running,
    this.activity = 'Running',
    this.pendingHumanRequestId,
    this.pendingHumanMessageId,
    this.pendingInterjections = const [],
    this.unread = false,
    this.error,
  });

  final sdk.SessionKey sessionKey;
  final String agentId;
  final String assistantMessageId;
  final StreamSubscription<sdk.ChatEvent> subscription;
  final DateTime startedAt;
  final DateTime updatedAt;
  final sdk.SessionRunStatus status;
  final String activity;
  final String? pendingHumanRequestId;
  final String? pendingHumanMessageId;
  final List<PendingInterjection> pendingInterjections;
  final bool unread;
  final String? error;

  bool get isTerminal =>
      status == sdk.SessionRunStatus.completed ||
      status == sdk.SessionRunStatus.failed ||
      status == sdk.SessionRunStatus.cancelled;

  bool get isRunning =>
      !isTerminal && status != sdk.SessionRunStatus.cancelling;

  bool get needsInput => status == sdk.SessionRunStatus.waitingForInput;

  bool get needsAttention =>
      unread || needsInput || status == sdk.SessionRunStatus.failed;

  ChatSessionRunState copyWith({
    String? assistantMessageId,
    StreamSubscription<sdk.ChatEvent>? subscription,
    DateTime? updatedAt,
    sdk.SessionRunStatus? status,
    String? activity,
    String? pendingHumanRequestId,
    bool clearPendingHumanRequest = false,
    String? pendingHumanMessageId,
    bool clearPendingHumanMessage = false,
    List<PendingInterjection>? pendingInterjections,
    bool? unread,
    String? error,
    bool clearError = false,
  }) {
    return ChatSessionRunState(
      sessionKey: sessionKey,
      agentId: agentId,
      assistantMessageId: assistantMessageId ?? this.assistantMessageId,
      subscription: subscription ?? this.subscription,
      startedAt: startedAt,
      updatedAt: updatedAt ?? this.updatedAt,
      status: status ?? this.status,
      activity: activity ?? this.activity,
      pendingHumanRequestId: clearPendingHumanRequest
          ? null
          : pendingHumanRequestId ?? this.pendingHumanRequestId,
      pendingHumanMessageId: clearPendingHumanMessage
          ? null
          : pendingHumanMessageId ?? this.pendingHumanMessageId,
      pendingInterjections: pendingInterjections ?? this.pendingInterjections,
      unread: unread ?? this.unread,
      error: clearError ? null : error ?? this.error,
    );
  }
}

class ChatSession {
  const ChatSession({
    required this.id,
    required this.createdAt,
    required this.updatedAt,
    required this.messages,
    this.title = '',
    this.isPinned = false,
  });

  final String id;
  final String title;
  final bool isPinned;
  final DateTime createdAt;
  final DateTime updatedAt;
  final List<ChatMessage> messages;

  String get displayTitle {
    if (title.trim().isNotEmpty) return title.trim();
    ChatMessage? firstUserMessage;
    for (final message in messages) {
      if (message.isUser) {
        firstUserMessage = message;
        break;
      }
    }
    final content = firstUserMessage?.content.trim() ?? '';
    if (content.isEmpty) return 'Untitled chat';
    return content.length <= 42 ? content : '${content.substring(0, 42)}...';
  }

  String get preview {
    if (messages.isEmpty) return '';
    final message = messages.reversed.firstWhere(
      (message) => message.id != 'welcome',
      orElse: () => messages.last,
    );
    if (message.content.trim().isEmpty && message.attachments.isNotEmpty) {
      return '${message.attachments.length} attachment(s)';
    }
    return message.content.trim();
  }

  ChatSession copyWith({
    String? id,
    String? title,
    bool? isPinned,
    DateTime? updatedAt,
    List<ChatMessage>? messages,
  }) {
    return ChatSession(
      id: id ?? this.id,
      title: title ?? this.title,
      isPinned: isPinned ?? this.isPinned,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      messages: messages ?? this.messages,
    );
  }
}
