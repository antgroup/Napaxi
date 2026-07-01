import 'dart:convert';

/// Describes when an automation job fires: a one-shot time, a recurring
/// local time, a fixed interval, a manual trigger, or a host event.
class AutomationTrigger {
  final String kind;
  final int? atMs;
  final String? timezone;
  final int? hour;
  final int? minute;
  final List<int>? daysOfWeek;
  final int? everyMs;
  final int? anchorMs;
  final String? eventType;
  final String? source;

  const AutomationTrigger._({
    required this.kind,
    this.atMs,
    this.timezone,
    this.hour,
    this.minute,
    this.daysOfWeek,
    this.everyMs,
    this.anchorMs,
    this.eventType,
    this.source,
  });

  /// Fires once at the absolute time [atMs] (epoch ms, in [timezone]).
  const AutomationTrigger.oneShotAt({required int atMs, String? timezone})
      : this._(kind: 'oneShotAt', atMs: atMs, timezone: timezone);

  /// Fires daily at [hour]:[minute] in [timezone], optionally restricted to
  /// [daysOfWeek].
  const AutomationTrigger.localTime({
    required int hour,
    required int minute,
    required String timezone,
    List<int>? daysOfWeek,
  }) : this._(
          kind: 'localTime',
          hour: hour,
          minute: minute,
          timezone: timezone,
          daysOfWeek: daysOfWeek,
        );

  /// Fires every [everyMs] milliseconds, optionally aligned to [anchorMs].
  const AutomationTrigger.interval({required int everyMs, int? anchorMs})
      : this._(kind: 'interval', everyMs: everyMs, anchorMs: anchorMs);

  /// Fires only when explicitly run by the user.
  const AutomationTrigger.manual() : this._(kind: 'manual');

  /// Fires when the host emits an event of [eventType] from [source].
  const AutomationTrigger.hostEvent({required String eventType, String? source})
      : this._(kind: 'hostEvent', eventType: eventType, source: source);

  factory AutomationTrigger.fromJson(Map<String, dynamic> json) {
    return AutomationTrigger._(
      kind: json['kind'] as String? ?? 'manual',
      atMs: _int(json['atMs'] ?? json['at_ms']),
      timezone: json['timezone'] as String?,
      hour: _int(json['hour']),
      minute: _int(json['minute']),
      daysOfWeek: _intList(json['daysOfWeek'] ?? json['days_of_week']),
      everyMs: _int(json['everyMs'] ?? json['every_ms']),
      anchorMs: _int(json['anchorMs'] ?? json['anchor_ms']),
      eventType: json['eventType'] as String? ?? json['event_type'] as String?,
      source: json['source'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'kind': kind,
        if (atMs != null) 'atMs': atMs,
        if (timezone != null) 'timezone': timezone,
        if (hour != null) 'hour': hour,
        if (minute != null) 'minute': minute,
        if (daysOfWeek != null) 'daysOfWeek': daysOfWeek,
        if (everyMs != null) 'everyMs': everyMs,
        if (anchorMs != null) 'anchorMs': anchorMs,
        if (eventType != null) 'eventType': eventType,
        if (source != null) 'source': source,
      };
}

/// What an automation job does when it fires: inject a system event or run a
/// full agent turn, with the relevant session/model parameters.
class AutomationPayload {
  final String kind;
  final String? text;
  final String? sessionKeyJson;
  final String? wakeMode;
  final String? message;
  final String? sessionMode;
  final String? modelProfileId;
  final int? maxIterations;

  const AutomationPayload._({
    required this.kind,
    this.text,
    this.sessionKeyJson,
    this.wakeMode,
    this.message,
    this.sessionMode,
    this.modelProfileId,
    this.maxIterations,
  });

  /// Injects [text] as a system event, delivered per [wakeMode], into the
  /// session identified by [sessionKeyJson].
  const AutomationPayload.systemEvent({
    required String text,
    String? sessionKeyJson,
    String wakeMode = 'next_foreground_or_host_wake',
  }) : this._(
          kind: 'systemEvent',
          text: text,
          sessionKeyJson: sessionKeyJson,
          wakeMode: wakeMode,
        );

  /// Runs an agent turn with [message] under [sessionMode], optionally
  /// pinning a [modelProfileId] and capping [maxIterations].
  const AutomationPayload.agentTurn({
    required String message,
    String? sessionKeyJson,
    String sessionMode = 'isolated',
    String? modelProfileId,
    int? maxIterations,
  }) : this._(
          kind: 'agentTurn',
          message: message,
          sessionKeyJson: sessionKeyJson,
          sessionMode: sessionMode,
          modelProfileId: modelProfileId,
          maxIterations: maxIterations,
        );

  factory AutomationPayload.fromJson(Map<String, dynamic> json) {
    return AutomationPayload._(
      kind: json['kind'] as String? ?? 'systemEvent',
      text: json['text'] as String?,
      sessionKeyJson:
          json['sessionKey'] as String? ?? json['session_key'] as String?,
      wakeMode: json['wakeMode'] as String? ??
          json['wake_mode'] as String? ??
          'next_foreground_or_host_wake',
      message: json['message'] as String?,
      sessionMode: json['sessionMode'] as String? ??
          json['session_mode'] as String? ??
          'isolated',
      modelProfileId: json['modelProfileId'] as String? ??
          json['model_profile_id'] as String?,
      maxIterations: _int(json['maxIterations'] ?? json['max_iterations']),
    );
  }

  Map<String, dynamic> toJson() => {
        'kind': kind,
        if (text != null) 'text': text,
        if (sessionKeyJson != null) 'sessionKey': sessionKeyJson,
        if (wakeMode != null) 'wakeMode': wakeMode,
        if (message != null) 'message': message,
        if (sessionMode != null) 'sessionMode': sessionMode,
        if (modelProfileId != null) 'modelProfileId': modelProfileId,
        if (maxIterations != null) 'maxIterations': maxIterations,
      };
}

/// Execution constraints for an automation job: notification requirement,
/// high-risk tool allowance, duration cap, and retry/backoff behavior.
class AutomationPolicy {
  final bool requiresUserVisibleNotification;
  final bool allowHighRiskTools;
  final int maxRunDurationMs;
  final int maxRetries;
  final List<int> retryBackoffMs;
  final bool? deleteAfterSuccess;

  const AutomationPolicy({
    this.requiresUserVisibleNotification = true,
    this.allowHighRiskTools = false,
    this.maxRunDurationMs = 600000,
    this.maxRetries = 2,
    this.retryBackoffMs = const [30000, 300000],
    this.deleteAfterSuccess,
  });

  factory AutomationPolicy.fromJson(Map<String, dynamic> json) {
    return AutomationPolicy(
      requiresUserVisibleNotification:
          json['requiresUserVisibleNotification'] as bool? ??
              json['requires_user_visible_notification'] as bool? ??
              true,
      allowHighRiskTools: json['allowHighRiskTools'] as bool? ??
          json['allow_high_risk_tools'] as bool? ??
          false,
      maxRunDurationMs:
          _int(json['maxRunDurationMs'] ?? json['max_run_duration_ms']) ??
              600000,
      maxRetries: _int(json['maxRetries'] ?? json['max_retries']) ?? 2,
      retryBackoffMs: (json['retryBackoffMs'] as List? ??
              json['retry_backoff_ms'] as List? ??
              const [30000, 300000])
          .map((item) => _int(item) ?? 0)
          .where((item) => item > 0)
          .toList(growable: false),
      deleteAfterSuccess: json['deleteAfterSuccess'] as bool? ??
          json['delete_after_success'] as bool?,
    );
  }

  Map<String, dynamic> toJson() => {
        'requiresUserVisibleNotification': requiresUserVisibleNotification,
        'allowHighRiskTools': allowHighRiskTools,
        'maxRunDurationMs': maxRunDurationMs,
        'maxRetries': maxRetries,
        'retryBackoffMs': retryBackoffMs,
        if (deleteAfterSuccess != null)
          'deleteAfterSuccess': deleteAfterSuccess,
      };
}

/// Mutable runtime state of an automation job: next/last run timing, last
/// status and error, error streak, and any in-flight run or wake metadata.
class AutomationJobState {
  final int? nextRunAtMs;
  final int? lastRunAtMs;
  final String? lastRunStatus;
  final String? lastError;
  final int consecutiveErrors;
  final String? runningRunId;
  final int? runningAtMs;
  final String? lastWakeSource;
  final int? lastWakeAtMs;

  const AutomationJobState({
    this.nextRunAtMs,
    this.lastRunAtMs,
    this.lastRunStatus,
    this.lastError,
    this.consecutiveErrors = 0,
    this.runningRunId,
    this.runningAtMs,
    this.lastWakeSource,
    this.lastWakeAtMs,
  });

  factory AutomationJobState.fromJson(Map<String, dynamic> json) {
    return AutomationJobState(
      nextRunAtMs: _int(json['nextRunAtMs'] ?? json['next_run_at_ms']),
      lastRunAtMs: _int(json['lastRunAtMs'] ?? json['last_run_at_ms']),
      lastRunStatus: json['lastRunStatus'] as String? ??
          json['last_run_status'] as String?,
      lastError: json['lastError'] as String? ?? json['last_error'] as String?,
      consecutiveErrors:
          _int(json['consecutiveErrors'] ?? json['consecutive_errors']) ?? 0,
      runningRunId:
          json['runningRunId'] as String? ?? json['running_run_id'] as String?,
      runningAtMs: _int(json['runningAtMs'] ?? json['running_at_ms']),
      lastWakeSource: json['lastWakeSource'] as String? ??
          json['last_wake_source'] as String?,
      lastWakeAtMs: _int(json['lastWakeAtMs'] ?? json['last_wake_at_ms']),
    );
  }

  Map<String, dynamic> toJson() => {
        if (nextRunAtMs != null) 'nextRunAtMs': nextRunAtMs,
        if (lastRunAtMs != null) 'lastRunAtMs': lastRunAtMs,
        if (lastRunStatus != null) 'lastRunStatus': lastRunStatus,
        if (lastError != null) 'lastError': lastError,
        'consecutiveErrors': consecutiveErrors,
        if (runningRunId != null) 'runningRunId': runningRunId,
        if (runningAtMs != null) 'runningAtMs': runningAtMs,
        if (lastWakeSource != null) 'lastWakeSource': lastWakeSource,
        if (lastWakeAtMs != null) 'lastWakeAtMs': lastWakeAtMs,
      };
}

/// A scheduled or triggered agent task: its identity, owning account/agent,
/// trigger, payload, policy, and current runtime state.
class AutomationJob {
  final String id;
  final String name;
  final bool enabled;
  final String accountId;
  final String agentId;
  final AutomationTrigger trigger;
  final AutomationPayload payload;
  final AutomationPolicy policy;
  final AutomationJobState state;
  final int createdAt;
  final int updatedAt;

  const AutomationJob({
    this.id = '',
    required this.name,
    this.enabled = true,
    this.accountId = '',
    this.agentId = '',
    required this.trigger,
    required this.payload,
    this.policy = const AutomationPolicy(),
    this.state = const AutomationJobState(),
    this.createdAt = 0,
    this.updatedAt = 0,
  });

  factory AutomationJob.fromJson(Map<String, dynamic> json) {
    return AutomationJob(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      enabled: json['enabled'] as bool? ?? true,
      accountId:
          json['accountId'] as String? ?? json['account_id'] as String? ?? '',
      agentId: json['agentId'] as String? ?? json['agent_id'] as String? ?? '',
      trigger: AutomationTrigger.fromJson(
        Map<String, dynamic>.from(json['trigger'] as Map? ?? const {}),
      ),
      payload: AutomationPayload.fromJson(
        Map<String, dynamic>.from(json['payload'] as Map? ?? const {}),
      ),
      policy: AutomationPolicy.fromJson(
        Map<String, dynamic>.from(json['policy'] as Map? ?? const {}),
      ),
      state: AutomationJobState.fromJson(
        Map<String, dynamic>.from(json['state'] as Map? ?? const {}),
      ),
      createdAt: _int(json['createdAt'] ?? json['created_at']) ?? 0,
      updatedAt: _int(json['updatedAt'] ?? json['updated_at']) ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
        if (id.isNotEmpty) 'id': id,
        'name': name,
        'enabled': enabled,
        if (accountId.isNotEmpty) 'accountId': accountId,
        if (agentId.isNotEmpty) 'agentId': agentId,
        'trigger': trigger.toJson(),
        'payload': payload.toJson(),
        'policy': policy.toJson(),
        if (createdAt > 0) 'createdAt': createdAt,
        if (updatedAt > 0) 'updatedAt': updatedAt,
      };

  String toJsonString() => jsonEncode(toJson());
}

/// A single execution record of an automation job: status, timing, the
/// originating trigger source, result summary/error, and delivery outcome.
class AutomationRun {
  final String runId;
  final String jobId;
  final String status;
  final String triggerSource;
  final int startedAt;
  final int? completedAt;
  final int? durationMs;
  final String? sessionKeyJson;
  final String? summary;
  final String? error;
  final int toolCallCount;
  final String deliveryStatus;

  const AutomationRun({
    required this.runId,
    required this.jobId,
    required this.status,
    required this.triggerSource,
    required this.startedAt,
    this.completedAt,
    this.durationMs,
    this.sessionKeyJson,
    this.summary,
    this.error,
    this.toolCallCount = 0,
    required this.deliveryStatus,
  });

  factory AutomationRun.fromJson(Map<String, dynamic> json) {
    return AutomationRun(
      runId: json['runId'] as String? ?? json['run_id'] as String? ?? '',
      jobId: json['jobId'] as String? ?? json['job_id'] as String? ?? '',
      status: json['status'] as String? ?? '',
      triggerSource: json['triggerSource'] as String? ??
          json['trigger_source'] as String? ??
          '',
      startedAt: _int(json['startedAt'] ?? json['started_at']) ?? 0,
      completedAt: _int(json['completedAt'] ?? json['completed_at']),
      durationMs: _int(json['durationMs'] ?? json['duration_ms']),
      sessionKeyJson:
          json['sessionKey'] as String? ?? json['session_key'] as String?,
      summary: json['summary'] as String?,
      error: json['error'] as String?,
      toolCallCount:
          _int(json['toolCallCount'] ?? json['tool_call_count']) ?? 0,
      deliveryStatus: json['deliveryStatus'] as String? ??
          json['delivery_status'] as String? ??
          'unknown',
    );
  }
}

/// A request to wake a job at [atMs] to evaluate its [trigger].
class AutomationWake {
  final String jobId;
  final int atMs;
  final AutomationTrigger trigger;

  const AutomationWake({
    required this.jobId,
    required this.atMs,
    required this.trigger,
  });

  factory AutomationWake.fromJson(Map<String, dynamic> json) {
    return AutomationWake(
      jobId: json['jobId'] as String? ?? '',
      atMs: _int(json['atMs']) ?? 0,
      trigger: AutomationTrigger.fromJson(
        Map<String, dynamic>.from(json['trigger'] as Map? ?? const {}),
      ),
    );
  }
}

/// Whether the platform supports background scheduling, with the count and
/// next of any pending wakes, plus a reason when unsupported.
class AutomationSchedulerStatus {
  final bool supported;
  final String platform;
  final int pendingWakeCount;
  final AutomationPendingWake? nextPendingWake;
  final String? reason;

  const AutomationSchedulerStatus({
    required this.supported,
    required this.platform,
    this.pendingWakeCount = 0,
    this.nextPendingWake,
    this.reason,
  });

  factory AutomationSchedulerStatus.fromJson(Map<String, dynamic> json) {
    final next = json['nextPendingWake'] ?? json['next_pending_wake'];
    return AutomationSchedulerStatus(
      supported: json['supported'] as bool? ?? false,
      platform: json['platform'] as String? ?? '',
      pendingWakeCount:
          _int(json['pendingWakeCount'] ?? json['pending_wake_count']) ?? 0,
      nextPendingWake: next is Map
          ? AutomationPendingWake.fromJson(Map<String, dynamic>.from(next))
          : null,
      reason: json['reason'] as String?,
    );
  }
}

/// A platform wake that has fired and is awaiting processing: its id, target
/// job, scheduled and fired times, and the wake source.
class AutomationPendingWake {
  final String wakeId;
  final String jobId;
  final int atMs;
  final int firedAtMs;
  final String source;

  const AutomationPendingWake({
    required this.wakeId,
    required this.jobId,
    required this.atMs,
    required this.firedAtMs,
    required this.source,
  });

  factory AutomationPendingWake.fromJson(Map<String, dynamic> json) {
    return AutomationPendingWake(
      wakeId: json['wakeId'] as String? ??
          json['wake_id'] as String? ??
          '${json['jobId'] ?? json['job_id'] ?? ''}:${json['firedAtMs'] ?? json['fired_at_ms'] ?? 0}',
      jobId: json['jobId'] as String? ?? json['job_id'] as String? ?? '',
      atMs: _int(json['atMs'] ?? json['at_ms']) ?? 0,
      firedAtMs: _int(json['firedAtMs'] ?? json['fired_at_ms']) ?? 0,
      source: json['source'] as String? ?? 'platform_wake',
    );
  }

  Map<String, dynamic> toJson() => {
        'wakeId': wakeId,
        'jobId': jobId,
        'atMs': atMs,
        'firedAtMs': firedAtMs,
        'source': source,
      };
}

/// Result of syncing the scheduler: runs produced, any newly scheduled wake,
/// and whether a platform-level wake was registered.
class AutomationSchedulerSyncResult {
  final List<AutomationRun> runs;
  final AutomationWake? scheduledWake;
  final bool platformWakeScheduled;

  const AutomationSchedulerSyncResult({
    this.runs = const [],
    this.scheduledWake,
    this.platformWakeScheduled = false,
  });
}

/// Decodes a JSON object string, returning null if it is not an object or
/// carries an `error` field.
Map<String, dynamic>? decodeJsonObjectOrNull(String jsonStr) {
  final decoded = jsonDecode(jsonStr);
  if (decoded is Map && decoded['error'] == null) {
    return Map<String, dynamic>.from(decoded);
  }
  return null;
}

/// Decodes a JSON array string into a list of automation jobs.
List<AutomationJob> decodeAutomationJobs(String jsonStr) {
  final decoded = jsonDecode(jsonStr);
  if (decoded is! List) return const [];
  return decoded
      .whereType<Map>()
      .map((item) => AutomationJob.fromJson(Map<String, dynamic>.from(item)))
      .toList(growable: false);
}

/// Decodes a JSON array string into a list of automation runs.
List<AutomationRun> decodeAutomationRuns(String jsonStr) {
  final decoded = jsonDecode(jsonStr);
  if (decoded is! List) return const [];
  return decoded
      .whereType<Map>()
      .map((item) => AutomationRun.fromJson(Map<String, dynamic>.from(item)))
      .toList(growable: false);
}

int? _int(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value);
  return null;
}

List<int>? _intList(Object? value) {
  if (value is! List) return null;
  return value.map(_int).whereType<int>().toList(growable: false);
}
