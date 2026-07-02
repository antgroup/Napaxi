/// Lifecycle status of an evolution (self-improvement review) run.
enum EvolutionRunStatus {
  /// Run has been queued but not yet started.
  queued,

  /// Run is currently executing.
  running,

  /// Run finished successfully.
  completed,

  /// Run terminated with an error.
  failed,

  /// Status could not be recognized.
  unknown;

  static EvolutionRunStatus fromString(String value) {
    return switch (value) {
      'queued' => EvolutionRunStatus.queued,
      'running' => EvolutionRunStatus.running,
      'completed' => EvolutionRunStatus.completed,
      'failed' => EvolutionRunStatus.failed,
      _ => EvolutionRunStatus.unknown,
    };
  }
}

/// A single evolution review run, summarizing how many improvement
/// suggestions were produced, auto-applied, or left pending.
class EvolutionRun {
  const EvolutionRun({
    required this.id,
    required this.agentId,
    required this.threadId,
    required this.reviewType,
    required this.status,
    required this.queuedAt,
    this.startedAt,
    this.completedAt,
    this.suggestionsCount = 0,
    this.autoAppliedCount = 0,
    this.pendingCount = 0,
    this.error,
  });

  final String id;
  final String agentId;
  final String threadId;
  final String reviewType;
  final EvolutionRunStatus status;
  final DateTime queuedAt;
  final DateTime? startedAt;
  final DateTime? completedAt;
  final int suggestionsCount;
  final int autoAppliedCount;
  final int pendingCount;
  final String? error;

  /// Whether the run reached a terminal state (completed or failed).
  bool get isFinished =>
      status == EvolutionRunStatus.completed ||
      status == EvolutionRunStatus.failed;

  factory EvolutionRun.fromMap(Map<String, dynamic> map) {
    return EvolutionRun(
      id: map['id'] as String,
      agentId: map['agent_id'] as String,
      threadId: map['thread_id'] as String,
      reviewType: map['review_type'] as String,
      status: EvolutionRunStatus.fromString(map['status'] as String? ?? ''),
      queuedAt: DateTime.parse(map['queued_at'] as String),
      startedAt: _parseOptionalDate(map['started_at']),
      completedAt: _parseOptionalDate(map['completed_at']),
      suggestionsCount: map['suggestions_count'] as int? ?? 0,
      autoAppliedCount: map['auto_applied_count'] as int? ?? 0,
      pendingCount: map['pending_count'] as int? ?? 0,
      error: map['error'] as String?,
    );
  }
}

/// Detailed diagnostic record for an evolution review, capturing its
/// trigger, inputs, tool calls, and outcome for debugging/inspection.
class EvolutionDiagnostic {
  const EvolutionDiagnostic({
    required this.id,
    required this.createdAt,
    required this.agentId,
    required this.threadId,
    required this.reviewType,
    required this.triggerReason,
    this.inputSummary = const {},
    this.toolCalls = const [],
    this.suggestionsCount = 0,
    this.pendingCount = 0,
    this.autoAppliedCount = 0,
    this.applyResult,
    this.failureReason,
  });

  final String id;
  final DateTime createdAt;
  final String agentId;
  final String threadId;
  final String reviewType;
  final String triggerReason;
  final Map<String, dynamic> inputSummary;
  final List<String> toolCalls;
  final int suggestionsCount;
  final int pendingCount;
  final int autoAppliedCount;
  final String? applyResult;
  final String? failureReason;

  factory EvolutionDiagnostic.fromMap(Map<String, dynamic> map) {
    return EvolutionDiagnostic(
      id: map['id'] as String? ?? '',
      createdAt: DateTime.parse(map['created_at'] as String),
      agentId: map['agent_id'] as String? ?? '',
      threadId: map['thread_id'] as String? ?? '',
      reviewType: map['review_type'] as String? ?? '',
      triggerReason: map['trigger_reason'] as String? ?? '',
      inputSummary: Map<String, dynamic>.from(
        (map['input_summary'] as Map?) ?? const {},
      ),
      toolCalls: (map['tool_calls'] as List?)?.cast<String>() ?? const [],
      suggestionsCount: map['suggestions_count'] as int? ?? 0,
      pendingCount: map['pending_count'] as int? ?? 0,
      autoAppliedCount: map['auto_applied_count'] as int? ?? 0,
      applyResult: map['apply_result'] as String?,
      failureReason: map['failure_reason'] as String?,
    );
  }
}

/// Outcome of a skill-consolidation review, which proposes merging or
/// pruning redundant skills (optionally as a dry run before applying).
class SkillConsolidationReviewResult {
  const SkillConsolidationReviewResult({
    required this.reviewed,
    required this.dryRun,
    this.suggestionsCount = 0,
    this.pendingCount = 0,
    this.pendingId,
    this.actions = const [],
    this.warnings = const [],
    this.error,
  });

  final bool reviewed;
  final bool dryRun;
  final int suggestionsCount;
  final int pendingCount;
  final String? pendingId;
  final List<Map<String, dynamic>> actions;
  final List<String> warnings;
  final String? error;

  factory SkillConsolidationReviewResult.fromMap(Map<String, dynamic> map) {
    return SkillConsolidationReviewResult(
      reviewed: map['reviewed'] as bool? ?? false,
      dryRun: map['dry_run'] as bool? ?? true,
      suggestionsCount: map['suggestions_count'] as int? ?? 0,
      pendingCount: map['pending_count'] as int? ?? 0,
      pendingId: map['pending_id'] as String?,
      actions: (map['actions'] as List?)
              ?.whereType<Map>()
              .map((item) => Map<String, dynamic>.from(item))
              .toList(growable: false) ??
          const [],
      warnings: (map['warnings'] as List?)?.cast<String>() ?? const [],
      error: map['error'] as String?,
    );
  }
}

DateTime? _parseOptionalDate(Object? value) {
  if (value is! String || value.trim().isEmpty) return null;
  return DateTime.tryParse(value);
}
