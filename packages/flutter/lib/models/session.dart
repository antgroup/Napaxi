import 'dart:convert';

/// 会话标识
class SessionKey {
  final String channelType;
  final String accountId;
  final String threadId;

  const SessionKey({
    required this.channelType,
    required this.accountId,
    required this.threadId,
  });

  String toJson() => jsonEncode({
        'channel_type': channelType,
        'account_id': accountId,
        'thread_id': threadId,
      });

  factory SessionKey.fromJson(String jsonStr) {
    final map = jsonDecode(jsonStr) as Map<String, dynamic>;
    return SessionKey(
      channelType: map['channel_type'] as String? ?? 'app',
      accountId: map['account_id'] as String? ?? '',
      threadId: map['thread_id'] as String? ?? '',
    );
  }

  @override
  String toString() => 'SessionKey($channelType/$accountId/$threadId)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SessionKey &&
          channelType == other.channelType &&
          accountId == other.accountId &&
          threadId == other.threadId;

  @override
  int get hashCode => Object.hash(channelType, accountId, threadId);
}

/// Lifecycle status of an in-flight or finished session run.
enum SessionRunStatus {
  /// The run is actively executing.
  running,

  /// The run is paused awaiting human input.
  waitingForInput,

  /// A cancellation has been requested but not yet finalized.
  cancelling,

  /// The run finished successfully.
  completed,

  /// The run ended with an error.
  failed,

  /// The run was cancelled.
  cancelled,
}

/// Live runtime state of a session run, including its current activity,
/// any pending human request, and start/update timestamps.
class SessionRunInfo {
  final SessionKey key;
  final String agentId;
  final SessionRunStatus status;
  final String activity;
  final String? humanRequestId;
  final String? error;
  final DateTime startedAt;
  final DateTime updatedAt;

  const SessionRunInfo({
    required this.key,
    required this.agentId,
    required this.status,
    required this.activity,
    this.humanRequestId,
    this.error,
    required this.startedAt,
    required this.updatedAt,
  });

  /// Whether the run has reached a terminal state.
  bool get isTerminal =>
      status == SessionRunStatus.completed ||
      status == SessionRunStatus.failed ||
      status == SessionRunStatus.cancelled;

  /// Whether the run is paused waiting for human input.
  bool get needsInput => status == SessionRunStatus.waitingForInput;

  /// Stable identifier combining the agent id and session key parts.
  String get id =>
      '$agentId:${key.channelType}:${key.accountId}:${key.threadId}';

  /// Returns a copy with selected fields replaced; pass the `clear*` flags
  /// to null out [humanRequestId] or [error] instead of preserving them.
  SessionRunInfo copyWith({
    SessionRunStatus? status,
    String? activity,
    String? humanRequestId,
    bool clearHumanRequest = false,
    String? error,
    bool clearError = false,
    DateTime? updatedAt,
  }) {
    return SessionRunInfo(
      key: key,
      agentId: agentId,
      status: status ?? this.status,
      activity: activity ?? this.activity,
      humanRequestId:
          clearHumanRequest ? null : humanRequestId ?? this.humanRequestId,
      error: clearError ? null : error ?? this.error,
      startedAt: startedAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

/// 会话信息
class SessionInfo {
  final SessionKey key;
  final String title;
  final String preview;
  final int messageCount;
  final String createdAt;
  final String updatedAt;

  const SessionInfo({
    required this.key,
    this.title = '',
    this.preview = '',
    this.messageCount = 0,
    this.createdAt = '',
    this.updatedAt = '',
  });

  factory SessionInfo.fromJson(String jsonStr) {
    final map = jsonDecode(jsonStr) as Map<String, dynamic>;
    final keyMap = map['key'] as Map<String, dynamic>? ?? {};
    return SessionInfo(
      key: SessionKey(
        channelType: keyMap['channel_type'] as String? ?? 'app',
        accountId: keyMap['account_id'] as String? ?? '',
        threadId: keyMap['thread_id'] as String? ?? '',
      ),
      title: map['title'] as String? ?? '',
      preview: map['preview'] as String? ?? '',
      messageCount: map['message_count'] as int? ?? 0,
      createdAt: map['created_at'] as String? ?? '',
      updatedAt: map['updated_at'] as String? ?? '',
    );
  }
}

/// Paginated conversation history.
class HistoryPage {
  final List<ChatMessage> messages;
  final bool hasMore;
  final String? nextBefore;

  const HistoryPage({
    required this.messages,
    required this.hasMore,
    this.nextBefore,
  });

  factory HistoryPage.fromJson(String jsonStr) {
    final map = jsonDecode(jsonStr) as Map<String, dynamic>;
    final rawMessages = map['messages'] as List? ?? const [];
    return HistoryPage(
      messages: rawMessages
          .map((e) => ChatMessage.fromMap(e as Map<String, dynamic>))
          .toList(),
      hasMore: map['has_more'] as bool? ?? false,
      nextBefore: map['next_before'] as String?,
    );
  }
}

/// Current context compaction state for a session thread.
class ContextStatus {
  final String threadId;
  final String engine;
  final bool summaryPresent;
  final int compactionCount;
  final int tokensBefore;
  final int tokensAfter;
  final int estimatedTokens;
  final int contextWindowTokens;
  final int triggerTokens;
  final int targetTokens;
  final int responseReserveTokens;
  final String responseReserveSource;
  final double usagePercent;
  final double triggerRatio;
  final double targetRatio;
  final String? lastCompactedAt;
  final int displayUsedTokens;
  final String displaySource;
  final int? lastPromptTokens;
  final int? preflightEstimatedTokens;
  final int cacheReadTokens;
  final int cacheWriteTokens;
  final String contextWindowSource;
  final int nativeContextWindowTokens;
  final String nativeContextWindowSource;
  final int effectiveContextWindowTokens;
  final String effectiveContextWindowSource;
  final String contextGuardStatus;
  final String contextGuardReason;
  final String contextRoute;
  final int overflowTokens;
  final ContextTokenBreakdown? breakdown;
  final ContextBudgetStatus? contextBudgetStatus;
  final String? updatedAt;
  final bool fresh;
  final int currentWindowTokens;
  final int transcriptEstimatedTokens;
  final int lastContextDeltaTokens;
  final String lastContextDeltaReason;
  final int toolResultPrunedTokens;
  final int toolResultPrunedChars;
  final String contextDisplayLabel;
  final String compactionStrategy;
  final int? lastCompactionDurationMs;
  final String? providerMetadataFetchedAt;
  final bool providerMetadataStale;
  final String? providerMetadataError;
  final int adaptiveChunkCount;
  final int oversizedMessageCount;
  final int protectedTailTokens;
  final String? overflowRetryAttemptedAt;
  final bool? overflowRetrySucceeded;
  final String? overflowRetryReason;
  final String? overflowRetryError;
  final bool preCompactionMemoryFlushEnabled;
  final String? preCompactionMemoryFlushStatus;
  final String? error;

  const ContextStatus({
    required this.threadId,
    required this.engine,
    required this.summaryPresent,
    required this.compactionCount,
    required this.tokensBefore,
    required this.tokensAfter,
    required this.estimatedTokens,
    required this.contextWindowTokens,
    required this.triggerTokens,
    required this.targetTokens,
    required this.responseReserveTokens,
    this.responseReserveSource = 'unknown',
    required this.usagePercent,
    required this.triggerRatio,
    required this.targetRatio,
    this.lastCompactedAt,
    int? displayUsedTokens,
    this.displaySource = 'legacy',
    this.lastPromptTokens,
    this.preflightEstimatedTokens,
    this.cacheReadTokens = 0,
    this.cacheWriteTokens = 0,
    this.contextWindowSource = 'unknown',
    int? nativeContextWindowTokens,
    this.nativeContextWindowSource = 'unknown',
    int? effectiveContextWindowTokens,
    this.effectiveContextWindowSource = 'unknown',
    this.contextGuardStatus = 'unknown',
    this.contextGuardReason = '',
    this.contextRoute = 'fits',
    this.overflowTokens = 0,
    this.breakdown,
    this.contextBudgetStatus,
    this.updatedAt,
    this.fresh = false,
    int? currentWindowTokens,
    int? transcriptEstimatedTokens,
    this.lastContextDeltaTokens = 0,
    this.lastContextDeltaReason = 'stable',
    this.toolResultPrunedTokens = 0,
    this.toolResultPrunedChars = 0,
    this.contextDisplayLabel = 'current_window',
    this.compactionStrategy = 'llm_summary',
    this.lastCompactionDurationMs,
    this.providerMetadataFetchedAt,
    this.providerMetadataStale = false,
    this.providerMetadataError,
    this.adaptiveChunkCount = 0,
    this.oversizedMessageCount = 0,
    this.protectedTailTokens = 0,
    this.overflowRetryAttemptedAt,
    this.overflowRetrySucceeded,
    this.overflowRetryReason,
    this.overflowRetryError,
    this.preCompactionMemoryFlushEnabled = false,
    this.preCompactionMemoryFlushStatus,
    this.error,
  })  : displayUsedTokens = displayUsedTokens ?? estimatedTokens,
        currentWindowTokens =
            currentWindowTokens ?? displayUsedTokens ?? estimatedTokens,
        transcriptEstimatedTokens =
            transcriptEstimatedTokens ?? estimatedTokens,
        nativeContextWindowTokens =
            nativeContextWindowTokens ?? contextWindowTokens,
        effectiveContextWindowTokens =
            effectiveContextWindowTokens ?? contextWindowTokens;

  /// Whether an error message is present.
  bool get hasError => error != null && error!.isNotEmpty;

  /// Whether usage has reached or exceeded the compaction trigger threshold.
  bool get isNearTrigger =>
      triggerTokens > 0 && displayUsedTokens >= triggerTokens;

  /// Fraction of the context window currently used (0.0–1.0).
  double get usageFraction =>
      contextWindowTokens <= 0 ? 0 : displayUsedTokens / contextWindowTokens;

  /// Whether the displayed usage comes from real provider token counts.
  bool get isProviderBacked => displaySource == 'provider';

  /// Whether the displayed usage comes from a preflight estimate.
  bool get isPreflightEstimate => displaySource == 'preflight';

  /// Whether the displayed usage comes from the legacy local estimate.
  bool get isLegacyEstimate => displaySource == 'legacy';

  /// Whether the context budget guard is blocking further input.
  bool get isBudgetBlocked => contextGuardStatus == 'blocked';

  /// Whether the context budget guard is in a warning state.
  bool get isBudgetWarning => contextGuardStatus == 'warning';

  factory ContextStatus.fromJson(String jsonStr) {
    final map = jsonDecode(jsonStr) as Map<String, dynamic>;
    final estimatedTokens = _intValue(map['estimated_tokens']);
    return ContextStatus(
      threadId: map['thread_id'] as String? ?? '',
      engine: map['engine'] as String? ?? 'compressor',
      summaryPresent: map['summary_present'] as bool? ?? false,
      compactionCount: _intValue(map['compaction_count']),
      tokensBefore: _intValue(map['tokens_before']),
      tokensAfter: _intValue(map['tokens_after']),
      estimatedTokens: estimatedTokens,
      contextWindowTokens: _intValue(map['context_window_tokens']),
      triggerTokens: _intValue(map['trigger_tokens']),
      targetTokens: _intValue(map['target_tokens']),
      responseReserveTokens: _intValue(map['response_reserve_tokens']),
      responseReserveSource:
          map['response_reserve_source'] as String? ?? 'unknown',
      usagePercent: _doubleValue(map['usage_percent']),
      triggerRatio: _doubleValue(map['trigger_ratio']),
      targetRatio: _doubleValue(map['target_ratio']),
      lastCompactedAt: map['last_compacted_at'] as String?,
      displayUsedTokens:
          _optionalIntValue(map['display_used_tokens']) ?? estimatedTokens,
      displaySource: map['display_source'] as String? ?? 'legacy',
      lastPromptTokens: _optionalIntValue(map['last_prompt_tokens']),
      preflightEstimatedTokens:
          _optionalIntValue(map['preflight_estimated_tokens']),
      cacheReadTokens: _intValue(map['cache_read_tokens']),
      cacheWriteTokens: _intValue(map['cache_write_tokens']),
      contextWindowSource: map['context_window_source'] as String? ?? 'unknown',
      nativeContextWindowTokens:
          _optionalIntValue(map['native_context_window_tokens']) ??
              _intValue(map['context_window_tokens']),
      nativeContextWindowSource:
          map['native_context_window_source'] as String? ?? 'unknown',
      effectiveContextWindowTokens:
          _optionalIntValue(map['effective_context_window_tokens']) ??
              _intValue(map['context_window_tokens']),
      effectiveContextWindowSource:
          map['effective_context_window_source'] as String? ??
              (map['context_window_source'] as String? ?? 'unknown'),
      providerMetadataFetchedAt: map['provider_metadata_fetched_at'] as String?,
      providerMetadataStale: map['provider_metadata_stale'] as bool? ?? false,
      providerMetadataError: map['provider_metadata_error'] as String?,
      contextGuardStatus: map['context_guard_status'] as String? ?? 'unknown',
      contextGuardReason: map['context_guard_reason'] as String? ?? '',
      contextRoute: map['context_route'] as String? ??
          (map['context_budget_status'] is Map
              ? (map['context_budget_status'] as Map)['route'] as String?
              : null) ??
          'fits',
      overflowTokens: _intValue(map['overflow_tokens']),
      breakdown: ContextTokenBreakdown.fromMapOrNull(
        _mapValue(map['breakdown']),
      ),
      contextBudgetStatus: ContextBudgetStatus.fromMapOrNull(
        _mapValue(map['context_budget_status']),
      ),
      updatedAt: map['updated_at'] as String?,
      fresh: map['fresh'] as bool? ?? false,
      currentWindowTokens: _optionalIntValue(map['current_window_tokens']) ??
          _optionalIntValue(map['display_used_tokens']) ??
          estimatedTokens,
      transcriptEstimatedTokens:
          _optionalIntValue(map['transcript_estimated_tokens']) ??
              estimatedTokens,
      lastContextDeltaTokens: _intValue(map['last_context_delta_tokens']),
      lastContextDeltaReason:
          map['last_context_delta_reason'] as String? ?? 'stable',
      toolResultPrunedTokens: _intValue(map['tool_result_pruned_tokens']),
      toolResultPrunedChars: _intValue(map['tool_result_pruned_chars']),
      contextDisplayLabel:
          map['context_display_label'] as String? ?? 'current_window',
      compactionStrategy:
          map['compaction_strategy'] as String? ?? 'llm_summary',
      lastCompactionDurationMs:
          _optionalIntValue(map['last_compaction_duration_ms']),
      adaptiveChunkCount: _intValue(map['adaptive_chunk_count']),
      oversizedMessageCount: _intValue(map['oversized_message_count']),
      protectedTailTokens: _intValue(map['protected_tail_tokens']),
      overflowRetryAttemptedAt: map['overflow_retry_attempted_at'] as String?,
      overflowRetrySucceeded: map['overflow_retry_succeeded'] as bool?,
      overflowRetryReason: map['overflow_retry_reason'] as String?,
      overflowRetryError: map['overflow_retry_error'] as String?,
      preCompactionMemoryFlushEnabled:
          map['pre_compaction_memory_flush_enabled'] as bool? ?? false,
      preCompactionMemoryFlushStatus:
          map['pre_compaction_memory_flush_status'] as String?,
      error: map['error'] as String?,
    );
  }
}

/// Per-component breakdown of how the estimated context tokens are
/// distributed across the prompt, history, tool data, and attachments.
class ContextTokenBreakdown {
  final int systemPromptTokens;
  final int summaryTokens;
  final int historyTokens;
  final int toolDescriptorTokens;
  final int toolResultTokens;
  final int toolCallTokens;
  final int attachmentTokens;
  final int imageTokens;
  final int responseReserveTokens;
  final int totalTokens;

  const ContextTokenBreakdown({
    required this.systemPromptTokens,
    required this.summaryTokens,
    required this.historyTokens,
    required this.toolDescriptorTokens,
    required this.toolResultTokens,
    required this.toolCallTokens,
    required this.attachmentTokens,
    required this.imageTokens,
    required this.responseReserveTokens,
    required this.totalTokens,
  });

  factory ContextTokenBreakdown.fromMap(Map<String, dynamic> map) {
    return ContextTokenBreakdown(
      systemPromptTokens: _intValue(map['system_prompt_tokens']),
      summaryTokens: _intValue(map['summary_tokens']),
      historyTokens: _intValue(map['history_tokens']),
      toolDescriptorTokens: _intValue(map['tool_descriptor_tokens']),
      toolResultTokens: _intValue(map['tool_result_tokens']),
      toolCallTokens: _intValue(map['tool_call_tokens']),
      attachmentTokens: _intValue(map['attachment_tokens']),
      imageTokens: _intValue(map['image_tokens']),
      responseReserveTokens: _intValue(map['response_reserve_tokens']),
      totalTokens: _intValue(map['total_tokens']),
    );
  }

  /// Parses [map] into a breakdown, or returns null if [map] is null.
  static ContextTokenBreakdown? fromMapOrNull(Map<String, dynamic>? map) {
    return map == null ? null : ContextTokenBreakdown.fromMap(map);
  }
}

/// Provider/model-aware budget assessment for a thread, including the
/// effective context window, reserve tokens, and overflow accounting.
class ContextBudgetStatus {
  final String source;
  final String provider;
  final String model;
  final String route;
  final bool shouldCompact;
  final int estimatedPromptTokens;
  final int contextTokenBudget;
  final int nativeContextWindowTokens;
  final String nativeContextWindowSource;
  final int effectiveContextWindowTokens;
  final String effectiveContextWindowSource;
  final String responseReserveSource;
  final String? providerMetadataFetchedAt;
  final bool providerMetadataStale;
  final String? providerMetadataError;
  final int promptBudgetBeforeReserve;
  final int reserveTokens;
  final int effectiveReserveTokens;
  final int remainingPromptBudgetTokens;
  final int overflowTokens;
  final int toolResultReducibleChars;
  final int toolResultReducibleTokens;
  final String contextGuardStatus;
  final String contextGuardReason;
  final int messageCount;
  final int unwindowedMessageCount;
  final String updatedAt;

  const ContextBudgetStatus({
    required this.source,
    required this.provider,
    required this.model,
    required this.route,
    required this.shouldCompact,
    required this.estimatedPromptTokens,
    required this.contextTokenBudget,
    this.nativeContextWindowTokens = 0,
    this.nativeContextWindowSource = 'unknown',
    this.effectiveContextWindowTokens = 0,
    this.effectiveContextWindowSource = 'unknown',
    this.responseReserveSource = 'unknown',
    this.providerMetadataFetchedAt,
    this.providerMetadataStale = false,
    this.providerMetadataError,
    required this.promptBudgetBeforeReserve,
    required this.reserveTokens,
    required this.effectiveReserveTokens,
    required this.remainingPromptBudgetTokens,
    required this.overflowTokens,
    required this.toolResultReducibleChars,
    this.toolResultReducibleTokens = 0,
    this.contextGuardStatus = 'unknown',
    this.contextGuardReason = '',
    required this.messageCount,
    required this.unwindowedMessageCount,
    required this.updatedAt,
  });

  factory ContextBudgetStatus.fromMap(Map<String, dynamic> map) {
    return ContextBudgetStatus(
      source: map['source'] as String? ?? '',
      provider: map['provider'] as String? ?? '',
      model: map['model'] as String? ?? '',
      route: map['route'] as String? ?? 'fits',
      shouldCompact: map['should_compact'] as bool? ?? false,
      estimatedPromptTokens: _intValue(map['estimated_prompt_tokens']),
      contextTokenBudget: _intValue(map['context_token_budget']),
      nativeContextWindowTokens:
          _optionalIntValue(map['native_context_window_tokens']) ??
              _intValue(map['context_token_budget']),
      nativeContextWindowSource:
          map['native_context_window_source'] as String? ?? 'unknown',
      effectiveContextWindowTokens:
          _optionalIntValue(map['effective_context_window_tokens']) ??
              _intValue(map['context_token_budget']),
      effectiveContextWindowSource:
          map['effective_context_window_source'] as String? ?? 'unknown',
      responseReserveSource:
          map['response_reserve_source'] as String? ?? 'unknown',
      providerMetadataFetchedAt: map['provider_metadata_fetched_at'] as String?,
      providerMetadataStale: map['provider_metadata_stale'] as bool? ?? false,
      providerMetadataError: map['provider_metadata_error'] as String?,
      promptBudgetBeforeReserve: _intValue(map['prompt_budget_before_reserve']),
      reserveTokens: _intValue(map['reserve_tokens']),
      effectiveReserveTokens: _intValue(map['effective_reserve_tokens']),
      remainingPromptBudgetTokens:
          _intValue(map['remaining_prompt_budget_tokens']),
      overflowTokens: _intValue(map['overflow_tokens']),
      toolResultReducibleChars: _intValue(map['tool_result_reducible_chars']),
      toolResultReducibleTokens: _intValue(map['tool_result_reducible_tokens']),
      contextGuardStatus: map['context_guard_status'] as String? ?? 'unknown',
      contextGuardReason: map['context_guard_reason'] as String? ?? '',
      messageCount: _intValue(map['message_count']),
      unwindowedMessageCount: _intValue(map['unwindowed_message_count']),
      updatedAt: map['updated_at'] as String? ?? '',
    );
  }

  /// Parses [map] into a budget status, or returns null if [map] is null.
  static ContextBudgetStatus? fromMapOrNull(Map<String, dynamic>? map) {
    return map == null ? null : ContextBudgetStatus.fromMap(map);
  }
}

Map<String, dynamic>? _mapValue(Object? value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) return value.cast<String, dynamic>();
  return null;
}

int _intValue(Object? value) => _optionalIntValue(value) ?? 0;

int? _optionalIntValue(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value);
  return null;
}

double _doubleValue(Object? value) {
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value) ?? 0;
  return 0;
}

/// 附件元数据（用于历史恢复）
class ChatAttachment {
  /// "image", "document", or "audio"
  final String kind;

  /// MIME type (e.g. "image/jpeg")
  final String mimeType;

  /// Original filename
  final String? filename;

  /// Path in the sandbox workspace
  final String? sandboxPath;

  /// Original host/local file path, if known.
  final String? localPath;

  const ChatAttachment({
    required this.kind,
    required this.mimeType,
    this.filename,
    this.sandboxPath,
    this.localPath,
  });

  factory ChatAttachment.fromMap(Map<String, dynamic> map) {
    final rawPath = map['path'] as String?;
    final localPath = map['local_path'] as String? ??
        map['localPath'] as String? ??
        map['host_path'] as String? ??
        map['hostPath'] as String? ??
        (rawPath != null && !_isLegacyPathSandboxPath(rawPath)
            ? rawPath
            : null);
    return ChatAttachment(
      kind: map['kind'] as String? ?? '',
      mimeType: map['mime_type'] as String? ?? '',
      filename: map['filename'] as String? ?? map['name'] as String?,
      sandboxPath: map['sandbox_path'] as String? ??
          (rawPath != null && _isLegacyPathSandboxPath(rawPath)
              ? rawPath
              : null),
      localPath: localPath,
    );
  }

  Map<String, dynamic> toMap() => {
        'kind': kind,
        'mime_type': mimeType,
        if (filename != null) 'filename': filename,
        if (sandboxPath != null) 'sandbox_path': sandboxPath,
        if (localPath != null) 'path': localPath,
      };
}

bool _isLegacyPathSandboxPath(String path) {
  final value = path.trim();
  return value == '/workspace' ||
      value.startsWith('/workspace/') ||
      value == '/skills' ||
      value.startsWith('/skills/');
}

/// 工具调用信息（从 tool_calls JSON 解析）
class ToolCallInfo {
  final String name;
  final String callId;
  final Map<String, dynamic>? arguments;
  final String? result;
  final String? error;
  final String? rationale;
  final bool interrupted;
  final bool resultTruncated;
  final bool errorTruncated;
  final bool argumentsTruncated;

  const ToolCallInfo({
    required this.name,
    required this.callId,
    this.arguments,
    this.result,
    this.error,
    this.rationale,
    this.interrupted = false,
    this.resultTruncated = false,
    this.errorTruncated = false,
    this.argumentsTruncated = false,
  });

  factory ToolCallInfo.fromMap(Map<String, dynamic> map) {
    final rawArguments = map['arguments'] ?? map['parameters'];
    Map<String, dynamic>? arguments;
    if (rawArguments is Map) {
      arguments = Map<String, dynamic>.from(rawArguments);
    } else if (rawArguments is String && rawArguments.isNotEmpty) {
      try {
        final decoded = jsonDecode(rawArguments);
        if (decoded is Map) arguments = Map<String, dynamic>.from(decoded);
      } catch (_) {}
    }

    return ToolCallInfo(
      name: map['name'] as String? ?? 'unknown',
      callId: map['call_id'] as String? ?? map['tool_call_id'] as String? ?? '',
      arguments: arguments,
      result: map['result']?.toString() ?? map['result_preview']?.toString(),
      error: map['error']?.toString() ?? map['error_preview']?.toString(),
      rationale: map['rationale'] as String?,
      interrupted: map['interrupted'] == true,
      resultTruncated:
          map['result_truncated'] == true || map['result_preview'] != null,
      errorTruncated:
          map['error_truncated'] == true || map['error_preview'] != null,
      argumentsTruncated: map['arguments_truncated'] == true ||
          map['parameters_truncated'] == true,
    );
  }
}

/// 对话消息
class ChatMessage {
  final String role;
  final String content;
  final List<ChatAttachment> attachments;
  final String? id;
  final String? createdAt;
  final String? thinkingContent;
  final String? reasoningContent;
  final List<ToolCallInfo>? toolCalls;
  final String? humanRequestId;
  final String? humanQuestion;
  final List<String> humanOptions;
  final String? humanContext;
  final bool interrupted;

  const ChatMessage({
    required this.role,
    required this.content,
    this.attachments = const [],
    this.id,
    this.createdAt,
    this.thinkingContent,
    this.reasoningContent,
    this.toolCalls,
    this.humanRequestId,
    this.humanQuestion,
    this.humanOptions = const [],
    this.humanContext,
    this.interrupted = false,
  });

  factory ChatMessage.fromMap(Map<String, dynamic> map) {
    final rawAttachments = map['attachments'] as List?;
    String? thinkingContent;
    String? reasoningContent;
    List<ToolCallInfo>? toolCalls;
    String? humanRequestId;
    String? humanQuestion;
    List<String> humanOptions = const [];
    String? humanContext;

    final role = map['role'] as String? ?? '';
    if (role == 'thinking') {
      thinkingContent = map['content'] as String?;
    } else if (role == 'reasoning') {
      reasoningContent = map['content'] as String?;
    } else if (role == 'tool_calls') {
      try {
        final contentStr = map['content'] as String? ?? '';
        final decoded = jsonDecode(contentStr);
        if (decoded is Map<String, dynamic>) {
          thinkingContent = decoded['narrative'] as String?;
          final calls = decoded['calls'] as List?;
          if (calls != null) {
            toolCalls = calls
                .map((c) => ToolCallInfo.fromMap(c as Map<String, dynamic>))
                .toList();
          }
        }
      } catch (_) {
        // Malformed tool_calls JSON — leave toolCalls null.
      }
    } else if (role == 'asking_human') {
      try {
        final contentStr = map['content'] as String? ?? '';
        final decoded = jsonDecode(contentStr);
        if (decoded is Map<String, dynamic>) {
          humanRequestId = decoded['request_id'] as String?;
          humanQuestion = decoded['question'] as String?;
          humanOptions = (decoded['options'] as List? ?? const [])
              .whereType<String>()
              .toList(growable: false);
          humanContext = decoded['context'] as String?;
        }
      } catch (_) {
        humanQuestion = map['content'] as String?;
      }
    }

    return ChatMessage(
      role: role,
      content: map['content'] as String? ?? '',
      attachments: rawAttachments
              ?.map((e) => ChatAttachment.fromMap(e as Map<String, dynamic>))
              .toList() ??
          const [],
      id: map['id'] as String?,
      createdAt: map['created_at'] as String?,
      thinkingContent: thinkingContent,
      reasoningContent: reasoningContent,
      toolCalls: toolCalls,
      humanRequestId: humanRequestId,
      humanQuestion: humanQuestion,
      humanOptions: humanOptions,
      humanContext: humanContext,
      interrupted: map['interrupted'] == true,
    );
  }

  /// Whether this message was authored by the user.
  bool get isUser => role == 'user';

  /// Whether this message was authored by the assistant.
  bool get isAssistant => role == 'assistant';

  /// Whether this message holds the assistant's thinking content.
  bool get isThinking => role == 'thinking';

  /// Whether this message holds the assistant's reasoning content.
  bool get isReasoning => role == 'reasoning';

  /// Whether this message represents one or more tool calls.
  bool get isToolCalls => role == 'tool_calls';

  /// Whether this message is a request for human input.
  bool get isAskingHuman => role == 'asking_human';
}
