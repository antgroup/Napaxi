import 'dart:convert';

/// Terminal or in-flight status of a recorded session run.
enum SessionRunRecordStatus {
  /// Run is still executing.
  running('running'),

  /// Run completed successfully.
  succeeded('succeeded'),

  /// Run ended with an error.
  failed('failed'),

  /// Run was cancelled before completing.
  cancelled('cancelled'),

  /// Run appears stuck with no recent progress.
  stalled('stalled'),

  /// Run was lost (e.g. host crashed before recording an outcome).
  lost('lost'),

  /// Run completed but its outcome could not be verified.
  unverified('unverified'),

  /// Status could not be recognized.
  unknown('unknown');

  const SessionRunRecordStatus(this.wireName);

  /// Serialized wire value for this status.
  final String wireName;

  /// Parses a wire value, falling back to [unknown] for unrecognized input.
  static SessionRunRecordStatus fromWire(String? value) {
    return SessionRunRecordStatus.values.firstWhere(
      (item) => item.wireName == value,
      orElse: () => SessionRunRecordStatus.unknown,
    );
  }
}

/// Kind of evidence collected to corroborate what a run actually did.
enum RunEvidenceKind {
  /// Only a textual reply was observed; no side effects.
  replyOnly('reply_only'),

  /// A tool invocation was observed.
  toolObserved('tool_observed'),

  /// An external side effect was observed.
  sideEffectObserved('side_effect_observed'),

  /// A detached/background task was observed.
  detachedTaskObserved('detached_task_observed'),

  /// Evidence kind could not be recognized.
  unknown('unknown');

  const RunEvidenceKind(this.wireName);

  /// Serialized wire value for this evidence kind.
  final String wireName;

  /// Parses a wire value, falling back to [unknown] for unrecognized input.
  static RunEvidenceKind fromWire(String? value) {
    return RunEvidenceKind.values.firstWhere(
      (item) => item.wireName == value,
      orElse: () => RunEvidenceKind.unknown,
    );
  }
}

/// Whether and how a run's outcome was verified.
enum RunVerification {
  /// No verification was required for this run.
  notRequired('not_required'),

  /// The run's outcome was verified.
  verified('verified'),

  /// Verification was expected but not obtained.
  unverified('unverified'),

  /// Verification was attempted and failed.
  failed('failed'),

  /// Verification state could not be recognized.
  unknown('unknown');

  const RunVerification(this.wireName);

  /// Serialized wire value for this verification state.
  final String wireName;

  /// Parses a wire value, falling back to [unknown] for unrecognized input.
  static RunVerification fromWire(String? value) {
    return RunVerification.values.firstWhere(
      (item) => item.wireName == value,
      orElse: () => RunVerification.unknown,
    );
  }
}

/// A single piece of evidence about what a run did (e.g. an observed
/// tool call or side effect), used to classify and verify the run.
class RunEvidence {
  final RunEvidenceKind kind;
  final String source;
  final String? effect;
  final bool isError;
  final String? digest;

  const RunEvidence({
    required this.kind,
    required this.source,
    this.effect,
    this.isError = false,
    this.digest,
  });

  factory RunEvidence.fromJson(Map<String, dynamic> json) {
    return RunEvidence(
      kind: RunEvidenceKind.fromWire(json['kind'] as String?),
      source: json['source'] as String? ?? '',
      effect: json['effect'] as String?,
      isError: json['isError'] as bool? ?? json['is_error'] as bool? ?? false,
      digest: json['digest'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'kind': kind.wireName,
        'source': source,
        if (effect != null) 'effect': effect,
        'isError': isError,
        if (digest != null) 'digest': digest,
      };
}

/// A persisted record of one agent run within a session, including its
/// status, timing, collected evidence, and parent/child run linkage.
class SessionRunRecord {
  final String runId;
  final SessionRunRecordStatus status;
  final String agentId;
  final String sessionKey;
  final String threadId;
  final int startedAt;
  final int? completedAt;
  final int? durationMs;
  final RunEvidenceKind evidenceKind;
  final RunVerification verification;
  final int toolCallCount;
  final List<RunEvidence> evidence;
  final String? summary;
  final String? error;
  final String? parentRunId;
  final List<String> childRunIds;

  const SessionRunRecord({
    required this.runId,
    required this.status,
    required this.agentId,
    required this.sessionKey,
    required this.threadId,
    required this.startedAt,
    this.completedAt,
    this.durationMs,
    required this.evidenceKind,
    required this.verification,
    this.toolCallCount = 0,
    this.evidence = const [],
    this.summary,
    this.error,
    this.parentRunId,
    this.childRunIds = const [],
  });

  factory SessionRunRecord.fromJson(Map<String, dynamic> json) {
    return SessionRunRecord(
      runId: json['runId'] as String? ?? json['run_id'] as String? ?? '',
      status: SessionRunRecordStatus.fromWire(json['status'] as String?),
      agentId: json['agentId'] as String? ?? json['agent_id'] as String? ?? '',
      sessionKey:
          json['sessionKey'] as String? ?? json['session_key'] as String? ?? '',
      threadId:
          json['threadId'] as String? ?? json['thread_id'] as String? ?? '',
      startedAt: _int(json['startedAt'] ?? json['started_at']) ?? 0,
      completedAt: _int(json['completedAt'] ?? json['completed_at']),
      durationMs: _int(json['durationMs'] ?? json['duration_ms']),
      evidenceKind: RunEvidenceKind.fromWire(
        json['evidenceKind'] as String? ?? json['evidence_kind'] as String?,
      ),
      verification: RunVerification.fromWire(json['verification'] as String?),
      toolCallCount:
          _int(json['toolCallCount'] ?? json['tool_call_count']) ?? 0,
      evidence: (json['evidence'] as List?)
              ?.whereType<Map>()
              .map((item) =>
                  RunEvidence.fromJson(Map<String, dynamic>.from(item)))
              .toList(growable: false) ??
          const [],
      summary: json['summary'] as String?,
      error: json['error'] as String?,
      parentRunId:
          json['parentRunId'] as String? ?? json['parent_run_id'] as String?,
      childRunIds: (json['childRunIds'] as List? ??
              json['child_run_ids'] as List? ??
              const [])
          .whereType<String>()
          .toList(growable: false),
    );
  }

  Map<String, dynamic> toJson() => {
        'runId': runId,
        'status': status.wireName,
        'agentId': agentId,
        'sessionKey': sessionKey,
        'threadId': threadId,
        'startedAt': startedAt,
        if (completedAt != null) 'completedAt': completedAt,
        if (durationMs != null) 'durationMs': durationMs,
        'evidenceKind': evidenceKind.wireName,
        'verification': verification.wireName,
        'toolCallCount': toolCallCount,
        'evidence': evidence.map((item) => item.toJson()).toList(),
        if (summary != null) 'summary': summary,
        if (error != null) 'error': error,
        if (parentRunId != null) 'parentRunId': parentRunId,
        if (childRunIds.isNotEmpty) 'childRunIds': childRunIds,
      };
}

/// Decodes a JSON array string into a list of [SessionRunRecord]s,
/// returning an empty list if the payload is not a JSON array.
List<SessionRunRecord> decodeSessionRunRecords(String raw) {
  final decoded = jsonDecode(raw);
  if (decoded is! List) return const [];
  return decoded
      .whereType<Map>()
      .map((item) => SessionRunRecord.fromJson(Map<String, dynamic>.from(item)))
      .toList(growable: false);
}

int? _int(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value);
  return null;
}
