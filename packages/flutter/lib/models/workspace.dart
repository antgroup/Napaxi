import 'dart:convert';

import 'json_model.dart';

/// Workspace 文件内容
class WorkspaceFile {
  final String path;
  final String content;
  final DateTime? updatedAt;
  final Map<String, dynamic> raw;

  const WorkspaceFile({
    required this.path,
    required this.content,
    this.updatedAt,
    this.raw = const {},
  });

  factory WorkspaceFile.fromMap(Map<String, dynamic> map) {
    return WorkspaceFile(
      path: map['path'] as String? ?? '',
      content: map['content'] as String? ?? '',
      updatedAt: jsonDateTimeField(map, ['updatedAt', 'updated_at']),
      raw: jsonModelRaw(map),
    );
  }

  factory WorkspaceFile.fromJson(String jsonStr) {
    return WorkspaceFile.fromMap(jsonDecode(jsonStr) as Map<String, dynamic>);
  }

  Map<String, dynamic> toMap() => mergePreservedJsonModel(raw, {
    'path': path,
    'content': content,
    if (updatedAt != null) 'updatedAt': updatedAt!.toIso8601String(),
  });

  @override
  String toString() => 'WorkspaceFile($path, ${content.length} chars)';
}

/// Workspace 目录条目
class WorkspaceEntry {
  final String path;
  final bool isDirectory;
  final DateTime? updatedAt;
  final String? preview;
  final Map<String, dynamic> raw;

  const WorkspaceEntry({
    required this.path,
    this.isDirectory = false,
    this.updatedAt,
    this.preview,
    this.raw = const {},
  });

  factory WorkspaceEntry.fromMap(Map<String, dynamic> map) {
    return WorkspaceEntry(
      path: map['path'] as String? ?? '',
      isDirectory: jsonBoolField(map, ['isDirectory', 'is_directory']),
      updatedAt: jsonDateTimeField(map, ['updatedAt', 'updated_at']),
      preview: map['preview'] as String?,
      raw: jsonModelRaw(map),
    );
  }

  Map<String, dynamic> toMap() => mergePreservedJsonModel(raw, {
    'path': path,
    'isDirectory': isDirectory,
    if (updatedAt != null) 'updatedAt': updatedAt!.toIso8601String(),
    if (preview != null) 'preview': preview,
  });

  /// 获取文件名（路径最后一段）
  String get name => path.split('/').last;

  @override
  String toString() => 'WorkspaceEntry($path${isDirectory ? '/' : ''})';
}

/// Memory search result from curated memory, journal, or legacy daily logs.
class MemorySearchResult {
  final String source;
  final String path;
  final String content;
  final double score;
  final bool isHybridMatch;
  final DateTime? updatedAt;
  final String? threadId;
  final String? turnId;
  final DateTime? createdAt;
  final Map<String, dynamic> raw;

  const MemorySearchResult({
    required this.source,
    required this.path,
    required this.content,
    this.score = 0,
    this.isHybridMatch = false,
    this.updatedAt,
    this.threadId,
    this.turnId,
    this.createdAt,
    this.raw = const {},
  });

  factory MemorySearchResult.fromMap(Map<String, dynamic> map) {
    return MemorySearchResult(
      source: map['source'] as String? ?? '',
      path: map['path'] as String? ?? '',
      content: map['content'] as String? ?? '',
      score: (map['score'] as num?)?.toDouble() ?? 0,
      isHybridMatch: jsonBoolField(map, ['isHybridMatch', 'is_hybrid_match']),
      updatedAt: jsonDateTimeField(map, ['updatedAt', 'updated_at']),
      threadId: jsonStringField(map, ['threadId', 'thread_id']),
      turnId: jsonStringField(map, ['turnId', 'turn_id']),
      createdAt: jsonDateTimeField(map, ['createdAt', 'created_at']),
      raw: jsonModelRaw(map),
    );
  }

  Map<String, dynamic> toMap() => mergePreservedJsonModel(raw, {
    'source': source,
    'path': path,
    'content': content,
    'score': score,
    'isHybridMatch': isHybridMatch,
    if (updatedAt != null) 'updatedAt': updatedAt!.toIso8601String(),
    if (threadId != null) 'threadId': threadId,
    if (turnId != null) 'turnId': turnId,
    if (createdAt != null) 'createdAt': createdAt!.toIso8601String(),
  });

  @override
  String toString() => 'MemorySearchResult($source, $path, score: $score)';
}

/// A single scored snippet recalled from memory, with its source, path, and
/// optional originating turn/timestamp.
class MemoryRecallSnippet {
  final String source;
  final String path;
  final String content;
  final double score;
  final String? turnId;
  final DateTime? createdAt;
  final Map<String, dynamic> raw;

  const MemoryRecallSnippet({
    required this.source,
    required this.path,
    required this.content,
    this.score = 0,
    this.turnId,
    this.createdAt,
    this.raw = const {},
  });

  factory MemoryRecallSnippet.fromMap(Map<String, dynamic> map) {
    return MemoryRecallSnippet(
      source: map['source'] as String? ?? '',
      path: map['path'] as String? ?? '',
      content: map['content'] as String? ?? '',
      score: (map['score'] as num?)?.toDouble() ?? 0,
      turnId: jsonStringField(map, ['turnId', 'turn_id']),
      createdAt: jsonDateTimeField(map, ['createdAt', 'created_at']),
      raw: jsonModelRaw(map),
    );
  }

  Map<String, dynamic> toMap() => mergePreservedJsonModel(raw, {
    'source': source,
    'path': path,
    'content': content,
    'score': score,
    if (turnId != null) 'turnId': turnId,
    if (createdAt != null) 'createdAt': createdAt!.toIso8601String(),
  });
}

/// A recalled past session: its title/summary, scored matching snippets, and
/// provenance metadata (cache/fallback flags, source hash and doc ids).
class MemoryRecallSession {
  final String threadId;
  final String title;
  final String summary;
  final List<MemoryRecallSnippet> snippets;
  final double score;
  final String source;
  final DateTime? startedAt;
  final DateTime? lastActiveAt;
  final bool cached;
  final bool fallback;
  final String sourceHash;
  final List<String> sourceDocIds;
  final String systemNote;
  final Map<String, dynamic> raw;

  const MemoryRecallSession({
    required this.threadId,
    required this.title,
    required this.summary,
    this.snippets = const [],
    this.score = 0,
    this.source = '',
    this.startedAt,
    this.lastActiveAt,
    this.cached = false,
    this.fallback = false,
    this.sourceHash = '',
    this.sourceDocIds = const [],
    this.systemNote = '',
    this.raw = const {},
  });

  factory MemoryRecallSession.fromMap(Map<String, dynamic> map) {
    final snippets = map['snippets'];
    return MemoryRecallSession(
      threadId: jsonStringField(map, ['threadId', 'thread_id']) ?? '',
      title: map['title'] as String? ?? '',
      summary: map['summary'] as String? ?? '',
      snippets: jsonObjectListField(snippets, MemoryRecallSnippet.fromMap),
      score: (map['score'] as num?)?.toDouble() ?? 0,
      source: map['source'] as String? ?? '',
      startedAt: jsonDateTimeField(map, ['startedAt', 'started_at']),
      lastActiveAt: jsonDateTimeField(map, ['lastActiveAt', 'last_active_at']),
      cached: map['cached'] as bool? ?? false,
      fallback: map['fallback'] as bool? ?? false,
      sourceHash: jsonStringField(map, ['sourceHash', 'source_hash']) ?? '',
      sourceDocIds: jsonStringListField(map, [
        'sourceDocIds',
        'source_doc_ids',
      ]),
      systemNote: jsonStringField(map, ['systemNote', 'system_note']) ?? '',
      raw: jsonModelRaw(map),
    );
  }

  Map<String, dynamic> toMap() => mergePreservedJsonModel(raw, {
    'threadId': threadId,
    'title': title,
    'summary': summary,
    'snippets': snippets.map((snippet) => snippet.toMap()).toList(),
    'score': score,
    'source': source,
    if (startedAt != null) 'startedAt': startedAt!.toIso8601String(),
    if (lastActiveAt != null) 'lastActiveAt': lastActiveAt!.toIso8601String(),
    'cached': cached,
    'fallback': fallback,
    'sourceHash': sourceHash,
    'sourceDocIds': sourceDocIds,
    'systemNote': systemNote,
  });
}

/// Statistics for the recall index: status, database path, schema version,
/// per-source document counts, cached summaries, and last rebuild time.
class RecallIndexStats {
  final String status;
  final String dbPath;
  final int schemaVersion;
  final int indexedDocs;
  final int memoryDocs;
  final int journalDocs;
  final int legacyDailyDocs;
  final int cachedSummaries;
  final DateTime? lastRebuildAt;
  final Map<String, dynamic> raw;

  const RecallIndexStats({
    required this.status,
    required this.dbPath,
    this.schemaVersion = 0,
    this.indexedDocs = 0,
    this.memoryDocs = 0,
    this.journalDocs = 0,
    this.legacyDailyDocs = 0,
    this.cachedSummaries = 0,
    this.lastRebuildAt,
    this.raw = const {},
  });

  factory RecallIndexStats.fromMap(Map<String, dynamic> map) {
    return RecallIndexStats(
      status: map['status'] as String? ?? '',
      dbPath: jsonStringField(map, ['dbPath', 'db_path']) ?? '',
      schemaVersion: jsonIntField(map, ['schemaVersion', 'schema_version']),
      indexedDocs: jsonIntField(map, ['indexedDocs', 'indexed_docs']),
      memoryDocs: jsonIntField(map, ['memoryDocs', 'memory_docs']),
      journalDocs: jsonIntField(map, ['journalDocs', 'journal_docs']),
      legacyDailyDocs: jsonIntField(map, [
        'legacyDailyDocs',
        'legacy_daily_docs',
      ]),
      cachedSummaries: jsonIntField(map, [
        'cachedSummaries',
        'cached_summaries',
      ]),
      lastRebuildAt: jsonDateTimeField(map, [
        'lastRebuildAt',
        'last_rebuild_at',
      ]),
      raw: jsonModelRaw(map),
    );
  }

  Map<String, dynamic> toMap() => mergePreservedJsonModel(raw, {
    'status': status,
    'dbPath': dbPath,
    'schemaVersion': schemaVersion,
    'indexedDocs': indexedDocs,
    'memoryDocs': memoryDocs,
    'journalDocs': journalDocs,
    'legacyDailyDocs': legacyDailyDocs,
    'cachedSummaries': cachedSummaries,
    if (lastRebuildAt != null)
      'lastRebuildAt': lastRebuildAt!.toIso8601String(),
  });
}

/// A day available in the core-owned journal.
class JournalDay {
  final String date;
  final String path;
  final int turnCount;
  final DateTime? updatedAt;
  final bool legacy;
  final Map<String, dynamic> raw;

  const JournalDay({
    required this.date,
    required this.path,
    this.turnCount = 0,
    this.updatedAt,
    this.legacy = false,
    this.raw = const {},
  });

  factory JournalDay.fromMap(Map<String, dynamic> map) {
    return JournalDay(
      date: map['date'] as String? ?? '',
      path: map['path'] as String? ?? '',
      turnCount: jsonIntField(map, ['turnCount', 'turn_count']),
      updatedAt: jsonDateTimeField(map, ['updatedAt', 'updated_at']),
      legacy: map['legacy'] as bool? ?? false,
      raw: jsonModelRaw(map),
    );
  }

  Map<String, dynamic> toMap() => mergePreservedJsonModel(raw, {
    'date': date,
    'path': path,
    'turnCount': turnCount,
    if (updatedAt != null) 'updatedAt': updatedAt!.toIso8601String(),
    'legacy': legacy,
  });

  @override
  String toString() => 'JournalDay($date, $turnCount turns)';
}

/// One turn or note inside a journal day.
class JournalTurnRecord {
  final String turnId;
  final DateTime? createdAt;
  final String agentId;
  final String threadId;
  final String user;
  final String assistant;
  final String kind;
  final Map<String, dynamic> raw;

  const JournalTurnRecord({
    required this.turnId,
    this.createdAt,
    this.agentId = '',
    this.threadId = '',
    this.user = '',
    this.assistant = '',
    this.kind = 'turn',
    this.raw = const {},
  });

  factory JournalTurnRecord.fromMap(Map<String, dynamic> map) {
    return JournalTurnRecord(
      turnId: map['turnId'] as String? ?? map['turn_id'] as String? ?? '',
      createdAt: jsonDateTimeField(map, ['createdAt', 'created_at']),
      agentId: map['agentId'] as String? ?? map['agent_id'] as String? ?? '',
      threadId: map['threadId'] as String? ?? map['thread_id'] as String? ?? '',
      user: map['user'] as String? ?? '',
      assistant: map['assistant'] as String? ?? '',
      kind: map['kind'] as String? ?? 'turn',
      raw: jsonModelRaw(map),
    );
  }

  Map<String, dynamic> toMap() => mergePreservedJsonModel(raw, {
    'turnId': turnId,
    if (createdAt != null) 'createdAt': createdAt!.toIso8601String(),
    'agentId': agentId,
    'threadId': threadId,
    'user': user,
    'assistant': assistant,
    'kind': kind,
  });

  @override
  String toString() => 'JournalTurnRecord($kind, $turnId)';
}

/// Workspace 已知路径常量
class WorkspacePaths {
  WorkspacePaths._();

  /// 核心价值观与行为边界
  static const soul = 'SOUL.md';

  /// Agent 名字、性格、风格
  static const identity = 'IDENTITY.md';

  /// 会话启动指令、行为准则
  static const agents = 'AGENTS.md';

  /// 用户画像（名字、偏好等）
  static const user = 'USER.md';

  /// 跨会话长期记忆
  static const memory = 'MEMORY.md';

  /// 项目级长期记忆
  static const project = 'PROJECT.md';

  /// 定期后台任务清单
  static const heartbeat = 'HEARTBEAT.md';

  /// 环境特定工具备注
  static const tools = 'TOOLS.md';

  /// 首次运行引导对话
  static const bootstrap = 'BOOTSTRAP.md';

  /// 用户心理画像（JSON）
  static const profile = 'context/profile.json';

  /// Legacy daily log directory retained for migration/search only.
  static const dailyDir = 'daily/';
}
