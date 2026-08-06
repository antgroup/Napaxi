/// A Provider-owned runtime failure report returned through the trusted,
/// model-hidden Agent App diagnostics channel.
class AgentAppDiagnosticReport {
  const AgentAppDiagnosticReport({
    required this.id,
    required this.kind,
    required this.timestamp,
    this.appPackage = '',
    this.versionName = '',
    this.versionCode = 0,
    this.exceptionType = '',
    this.message = '',
    this.stackTrace = '',
    this.description = '',
    this.thread = '',
    this.process = '',
    this.breadcrumbs = const <Map<String, dynamic>>[],
    this.metadata = const <String, dynamic>{},
  });

  final String id;
  final String kind;
  final String timestamp;
  final String appPackage;
  final String versionName;
  final int versionCode;
  final String exceptionType;
  final String message;
  final String stackTrace;
  final String description;
  final String thread;
  final String process;
  final List<Map<String, dynamic>> breadcrumbs;
  final Map<String, dynamic> metadata;

  factory AgentAppDiagnosticReport.fromMap(Map<dynamic, dynamic> map) {
    return AgentAppDiagnosticReport(
      id: map['id'] as String? ?? '',
      kind: map['kind'] as String? ?? 'unknown',
      timestamp: map['timestamp'] as String? ?? '',
      appPackage: map['app_package'] as String? ?? '',
      versionName: map['version_name'] as String? ?? '',
      versionCode: (map['version_code'] as num?)?.toInt() ?? 0,
      exceptionType: map['exception_type'] as String? ?? '',
      message: map['message'] as String? ?? '',
      stackTrace: map['stack_trace'] as String? ?? '',
      description: map['description'] as String? ?? '',
      thread: map['thread'] as String? ?? '',
      process: map['process'] as String? ?? '',
      breadcrumbs: (map['breadcrumbs'] as List? ?? const <Object>[])
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList(growable: false),
      metadata: map['metadata'] is Map
          ? Map<String, dynamic>.from(map['metadata'] as Map)
          : const <String, dynamic>{},
    );
  }

  String get summary {
    if (exceptionType.isNotEmpty && message.isNotEmpty) {
      return '$exceptionType: $message';
    }
    if (exceptionType.isNotEmpty) return exceptionType;
    if (description.isNotEmpty) return description;
    if (message.isNotEmpty) return message;
    return kind;
  }
}

/// One Provider-owned structured runtime event. It is never mounted as a model
/// tool or added to conversation context automatically.
class AgentAppDiagnosticLogEntry {
  const AgentAppDiagnosticLogEntry({
    required this.id,
    required this.timestamp,
    required this.level,
    required this.module,
    required this.event,
    this.message = '',
    this.traceId = '',
    this.thread = '',
    this.metadata = const <String, dynamic>{},
  });

  final String id;
  final String timestamp;
  final String level;
  final String module;
  final String event;
  final String message;
  final String traceId;
  final String thread;
  final Map<String, dynamic> metadata;

  factory AgentAppDiagnosticLogEntry.fromMap(Map<dynamic, dynamic> map) {
    return AgentAppDiagnosticLogEntry(
      id: map['id'] as String? ?? '',
      timestamp: map['timestamp'] as String? ?? '',
      level: map['level'] as String? ?? 'info',
      module: map['module'] as String? ?? '',
      event: map['event'] as String? ?? '',
      message: map['message'] as String? ?? '',
      traceId: map['trace_id'] as String? ?? '',
      thread: map['thread'] as String? ?? '',
      metadata: map['metadata'] is Map
          ? Map<String, dynamic>.from(map['metadata'] as Map)
          : const <String, dynamic>{},
    );
  }

  String get summary => message.isNotEmpty
      ? message
      : event.isNotEmpty
      ? event
      : level;
}

/// One diagnostics query result. Unsupported providers are expected for apps
/// generated before the diagnostics protocol was introduced.
class AgentAppDiagnosticsSnapshot {
  const AgentAppDiagnosticsSnapshot({
    required this.supported,
    this.reports = const <AgentAppDiagnosticReport>[],
    this.logs = const <AgentAppDiagnosticLogEntry>[],
    this.detailedLoggingEnabled = false,
    this.error = '',
  });

  final bool supported;
  final List<AgentAppDiagnosticReport> reports;
  final List<AgentAppDiagnosticLogEntry> logs;
  final bool detailedLoggingEnabled;
  final String error;
}
