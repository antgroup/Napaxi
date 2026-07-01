import 'dart:convert';
import 'dart:typed_data';

/// Skill 信息（从 SkillRegistry 返回）
class SkillInfo {
  final String name;
  final String version;
  final String description;
  final bool always;
  final List<String> allowedAgents;
  final String trust;
  final String source;
  final List<String> keywords;
  final List<String> tags;
  final String? promptContent;
  final String? contentHash;
  final SkillLifecycleSummary lifecycle;
  final List<String> supportFiles;

  const SkillInfo({
    required this.name,
    this.version = '',
    this.description = '',
    this.always = false,
    this.allowedAgents = const [],
    this.trust = 'Trusted',
    this.source = '',
    this.keywords = const [],
    this.tags = const [],
    this.promptContent,
    this.contentHash,
    this.lifecycle = const SkillLifecycleSummary(),
    this.supportFiles = const [],
  });

  factory SkillInfo.fromMap(Map<String, dynamic> map) {
    return SkillInfo(
      name: map['name'] as String? ?? '',
      version: map['version'] as String? ?? '',
      description: map['description'] as String? ?? '',
      always: map['always'] as bool? ?? false,
      allowedAgents: (map['allowed_agents'] as List?)?.cast<String>() ?? [],
      trust: map['trust'] as String? ?? 'Trusted',
      source: map['source'] as String? ?? '',
      keywords: (map['keywords'] as List?)?.cast<String>() ?? [],
      tags: (map['tags'] as List?)?.cast<String>() ?? [],
      promptContent: map['prompt_content'] as String?,
      contentHash: map['content_hash'] as String?,
      lifecycle: SkillLifecycleSummary.fromMap(
        map['lifecycle'] as Map<String, dynamic>?,
      ),
      supportFiles: (map['support_files'] as List?)?.cast<String>() ?? [],
    );
  }

  factory SkillInfo.fromJson(String jsonStr) {
    return SkillInfo.fromMap(jsonDecode(jsonStr) as Map<String, dynamic>);
  }

  @override
  String toString() => 'SkillInfo($name v$version)';
}

/// Lifecycle metadata for a skill: its state, pin/protection flags, and
/// usage/view/patch counters with their associated timestamps.
class SkillLifecycleSummary {
  final String state;
  final bool pinned;
  final bool protected;
  final String? createdBy;
  final int useCount;
  final int viewCount;
  final int patchCount;
  final String? lastUsedAt;
  final String? lastViewedAt;
  final String? lastPatchedAt;
  final String? archivedAt;
  final String? absorbedInto;

  const SkillLifecycleSummary({
    this.state = 'active',
    this.pinned = false,
    this.protected = false,
    this.createdBy,
    this.useCount = 0,
    this.viewCount = 0,
    this.patchCount = 0,
    this.lastUsedAt,
    this.lastViewedAt,
    this.lastPatchedAt,
    this.archivedAt,
    this.absorbedInto,
  });

  factory SkillLifecycleSummary.fromMap(Map<String, dynamic>? map) {
    if (map == null) return const SkillLifecycleSummary();
    return SkillLifecycleSummary(
      state: map['state'] as String? ?? 'active',
      pinned: map['pinned'] as bool? ?? false,
      protected: map['protected'] as bool? ?? false,
      createdBy: map['created_by'] as String?,
      useCount: (map['use_count'] as num?)?.toInt() ?? 0,
      viewCount: (map['view_count'] as num?)?.toInt() ?? 0,
      patchCount: (map['patch_count'] as num?)?.toInt() ?? 0,
      lastUsedAt: map['last_used_at'] as String?,
      lastViewedAt: map['last_viewed_at'] as String?,
      lastPatchedAt: map['last_patched_at'] as String?,
      archivedAt: map['archived_at'] as String?,
      absorbedInto: map['absorbed_into'] as String?,
    );
  }
}

/// Aggregate readiness report for all skills, with per-status counts and
/// the entries plus the top blockers that prevent skills from being ready.
class SkillStatusReport {
  final List<SkillStatusEntry> entries;
  final int ready;
  final int disabled;
  final int blocked;
  final int missingRequirements;
  final int parseError;
  final int securityBlocked;
  final int tooLarge;
  final List<SkillStatusEntry> topBlockers;

  const SkillStatusReport({
    this.entries = const [],
    this.ready = 0,
    this.disabled = 0,
    this.blocked = 0,
    this.missingRequirements = 0,
    this.parseError = 0,
    this.securityBlocked = 0,
    this.tooLarge = 0,
    this.topBlockers = const [],
  });

  factory SkillStatusReport.fromJson(String jsonStr) {
    final map = jsonDecode(jsonStr) as Map<String, dynamic>;
    return SkillStatusReport.fromMap(map);
  }

  factory SkillStatusReport.fromMap(Map<String, dynamic> map) {
    final entries = (map['entries'] as List? ?? const [])
        .whereType<Map>()
        .map((entry) =>
            SkillStatusEntry.fromMap(Map<String, dynamic>.from(entry)))
        .toList();
    final topBlockers = (map['top_blockers'] as List? ?? const [])
        .whereType<Map>()
        .map((entry) =>
            SkillStatusEntry.fromMap(Map<String, dynamic>.from(entry)))
        .toList();
    return SkillStatusReport(
      entries: entries,
      ready: _intValue(map['ready']) ?? 0,
      disabled: _intValue(map['disabled']) ?? 0,
      blocked: _intValue(map['blocked']) ?? 0,
      missingRequirements: _intValue(map['missing_requirements']) ?? 0,
      parseError: _intValue(map['parse_error']) ?? 0,
      securityBlocked: _intValue(map['security_blocked']) ?? 0,
      tooLarge: _intValue(map['too_large']) ?? 0,
      topBlockers: topBlockers,
    );
  }
}

/// Per-skill status entry describing its source, trust, eligibility, the
/// requirements it needs (and which are missing), and remediation options.
class SkillStatusEntry {
  final String name;
  final String description;
  final String sourceKind;
  final String source;
  final String trust;
  final bool enabled;
  final bool eligible;
  final String status;
  final SkillRequirementSummary requirements;
  final SkillRequirementSummary missing;
  final List<Map<String, dynamic>> installOptions;
  final List<String> warnings;
  final String? error;
  final SkillLifecycleSummary lifecycle;
  final SkillOpenClawMetadata metadata;
  final SkillProvenance provenance;
  final List<SkillRemediationAction> remediationActions;

  const SkillStatusEntry({
    required this.name,
    this.description = '',
    this.sourceKind = '',
    this.source = '',
    this.trust = '',
    this.enabled = true,
    this.eligible = false,
    this.status = '',
    this.requirements = const SkillRequirementSummary(),
    this.missing = const SkillRequirementSummary(),
    this.installOptions = const [],
    this.warnings = const [],
    this.error,
    this.lifecycle = const SkillLifecycleSummary(),
    this.metadata = const SkillOpenClawMetadata(),
    this.provenance = const SkillProvenance(),
    this.remediationActions = const [],
  });

  /// Whether the skill is ready to use.
  bool get isReady => status == 'ready';

  /// Whether the skill is blocked from use for any reason.
  bool get isBlocked =>
      status == 'missing_requirements' ||
      status == 'parse_error' ||
      status == 'security_blocked' ||
      status == 'too_large' ||
      status == 'blocked';

  factory SkillStatusEntry.fromMap(Map<String, dynamic> map) {
    return SkillStatusEntry(
      name: map['name'] as String? ?? '',
      description: map['description'] as String? ?? '',
      sourceKind: map['source_kind'] as String? ?? '',
      source: map['source'] as String? ?? '',
      trust: map['trust'] as String? ?? '',
      enabled: map['enabled'] as bool? ?? true,
      eligible: map['eligible'] as bool? ?? false,
      status: map['status'] as String? ?? '',
      requirements:
          SkillRequirementSummary.fromMap(_mapValue(map['requirements'])),
      missing: SkillRequirementSummary.fromMap(_mapValue(map['missing'])),
      installOptions: (map['install_options'] as List? ?? const [])
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList(),
      warnings: _stringListValue(map['warnings']),
      error: _stringValue(map['error']),
      lifecycle: SkillLifecycleSummary.fromMap(_mapValue(map['lifecycle'])),
      metadata: SkillOpenClawMetadata.fromMap(_mapValue(map['metadata'])),
      provenance: SkillProvenance.fromMap(_mapValue(map['provenance'])),
      remediationActions:
          _listValue(map['remediation_actions'] ?? map['remediationActions'])
              .whereType<Map>()
              .map((item) => SkillRemediationAction.fromMap(
                    Map<String, dynamic>.from(item),
                  ))
              .toList(),
    );
  }
}

/// Origin and trust provenance of a skill (where it came from, who
/// manages it, and whether it is a legacy entry).
class SkillProvenance {
  final String sourceKind;
  final String trust;
  final String managedBy;
  final bool legacy;

  const SkillProvenance({
    this.sourceKind = '',
    this.trust = '',
    this.managedBy = '',
    this.legacy = false,
  });

  factory SkillProvenance.fromMap(Map<String, dynamic>? map) {
    if (map == null) return const SkillProvenance();
    return SkillProvenance(
      sourceKind: _stringValue(map['source_kind'] ?? map['sourceKind']) ?? '',
      trust: _stringValue(map['trust']) ?? '',
      managedBy: _stringValue(map['managed_by'] ?? map['managedBy']) ?? '',
      legacy: map['legacy'] as bool? ?? false,
    );
  }
}

/// An offered action to resolve a missing skill requirement, including
/// whether the host handles it and its associated danger level.
class SkillRemediationAction {
  final String id;
  final String kind;
  final String label;
  final String requirement;
  final bool hostHandled;
  final String dangerLevel;

  const SkillRemediationAction({
    required this.id,
    this.kind = '',
    this.label = '',
    this.requirement = '',
    this.hostHandled = true,
    this.dangerLevel = 'low',
  });

  factory SkillRemediationAction.fromMap(Map<String, dynamic> map) {
    return SkillRemediationAction(
      id: _stringValue(map['id']) ?? '',
      kind: _stringValue(map['kind']) ?? '',
      label: _stringValue(map['label']) ?? '',
      requirement: _stringValue(map['requirement']) ?? '',
      hostHandled:
          map['host_handled'] as bool? ?? map['hostHandled'] as bool? ?? true,
      dangerLevel:
          _stringValue(map['danger_level'] ?? map['dangerLevel']) ?? 'low',
    );
  }
}

/// The requirements a skill declares: binaries, env vars, config keys,
/// supported OSes, capabilities, and dependent skills.
class SkillRequirementSummary {
  final List<String> bins;
  final List<String> anyBins;
  final List<String> env;
  final List<String> config;
  final List<String> os;
  final List<String> capabilities;
  final List<String> skills;

  const SkillRequirementSummary({
    this.bins = const [],
    this.anyBins = const [],
    this.env = const [],
    this.config = const [],
    this.os = const [],
    this.capabilities = const [],
    this.skills = const [],
  });

  /// Whether no requirements of any kind are declared.
  bool get isEmpty =>
      bins.isEmpty &&
      anyBins.isEmpty &&
      env.isEmpty &&
      config.isEmpty &&
      os.isEmpty &&
      capabilities.isEmpty &&
      skills.isEmpty;

  factory SkillRequirementSummary.fromMap(Map<String, dynamic>? map) {
    if (map == null) return const SkillRequirementSummary();
    return SkillRequirementSummary(
      bins: _stringListValue(map['bins']),
      anyBins: _stringListValue(map['any_bins'] ?? map['anyBins']),
      env: _stringListValue(map['env']),
      config: _stringListValue(map['config']),
      os: _stringListValue(map['os']),
      capabilities: _stringListValue(map['capabilities']),
      skills: _stringListValue(map['skills']),
    );
  }
}

/// OpenClaw-specific skill metadata controlling invocation behavior,
/// command dispatch wiring, and presentation hints (homepage, emoji).
class SkillOpenClawMetadata {
  final bool userInvocable;
  final bool disableModelInvocation;
  final String? commandDispatch;
  final String? commandTool;
  final String? commandArgMode;
  final String? primaryEnv;
  final String? skillKey;
  final String? homepage;
  final String? emoji;

  const SkillOpenClawMetadata({
    this.userInvocable = true,
    this.disableModelInvocation = false,
    this.commandDispatch,
    this.commandTool,
    this.commandArgMode,
    this.primaryEnv,
    this.skillKey,
    this.homepage,
    this.emoji,
  });

  factory SkillOpenClawMetadata.fromMap(Map<String, dynamic>? map) {
    if (map == null) return const SkillOpenClawMetadata();
    return SkillOpenClawMetadata(
      userInvocable: map['user_invocable'] as bool? ?? true,
      disableModelInvocation: map['disable_model_invocation'] as bool? ?? false,
      commandDispatch: _stringValue(map['command_dispatch']),
      commandTool: _stringValue(map['command_tool']),
      commandArgMode: _stringValue(map['command_arg_mode']),
      primaryEnv: _stringValue(map['primary_env']),
      skillKey: _stringValue(map['skill_key']),
      homepage: _stringValue(map['homepage']),
      emoji: _stringValue(map['emoji']),
    );
  }
}

/// The set of slash-commands exposed by installed skills, with the total
/// count and an optional snapshot id the listing was derived from.
class SkillCommandReport {
  final List<SkillCommand> commands;
  final int total;
  final String? snapshotId;

  const SkillCommandReport({
    this.commands = const [],
    this.total = 0,
    this.snapshotId,
  });

  factory SkillCommandReport.fromJson(String jsonStr) {
    return SkillCommandReport.fromMap(
      jsonDecode(jsonStr) as Map<String, dynamic>,
    );
  }

  factory SkillCommandReport.fromMap(Map<String, dynamic> map) {
    final commands = _listValue(map['commands'])
        .whereType<Map>()
        .map((item) => SkillCommand.fromMap(Map<String, dynamic>.from(item)))
        .toList();
    return SkillCommandReport(
      commands: commands,
      total: _intValue(map['total']) ?? commands.length,
      snapshotId: _stringValue(map['snapshot_id'] ?? map['snapshotId']),
    );
  }
}

/// The configured skill sources for an agent and their resolution order.
class SkillSourceReport {
  final String agentId;
  final List<SkillSourceEntry> sources;

  const SkillSourceReport({this.agentId = '', this.sources = const []});

  factory SkillSourceReport.fromJson(String jsonStr) {
    return SkillSourceReport.fromMap(
        jsonDecode(jsonStr) as Map<String, dynamic>);
  }

  factory SkillSourceReport.fromMap(Map<String, dynamic> map) {
    return SkillSourceReport(
      agentId: _stringValue(map['agent_id'] ?? map['agentId']) ?? '',
      sources: _listValue(map['sources'])
          .whereType<Map>()
          .map((item) =>
              SkillSourceEntry.fromMap(Map<String, dynamic>.from(item)))
          .toList(),
    );
  }
}

/// A single skill source (root location, kind, trust, priority) and its
/// current existence/version state.
class SkillSourceEntry {
  final String id;
  final String kind;
  final String root;
  final int priority;
  final String trust;
  final bool exists;
  final int version;
  final String? updatedAt;

  const SkillSourceEntry({
    this.id = '',
    this.kind = '',
    this.root = '',
    this.priority = 0,
    this.trust = '',
    this.exists = false,
    this.version = 0,
    this.updatedAt,
  });

  factory SkillSourceEntry.fromMap(Map<String, dynamic> map) {
    return SkillSourceEntry(
      id: _stringValue(map['id']) ?? '',
      kind: _stringValue(map['kind']) ?? '',
      root: _stringValue(map['root']) ?? '',
      priority: _intValue(map['priority']) ?? 0,
      trust: _stringValue(map['trust']) ?? '',
      exists: map['exists'] as bool? ?? false,
      version: _intValue(map['version']) ?? 0,
      updatedAt: _stringValue(map['updated_at'] ?? map['updatedAt']),
    );
  }
}

/// Result of refreshing a skill source, reporting the new version and
/// when it was recorded, or an error on failure.
class SkillRefreshResult {
  final bool success;
  final String agentId;
  final String sourceId;
  final int version;
  final String recordedAt;
  final String? error;

  const SkillRefreshResult({
    this.success = false,
    this.agentId = '',
    this.sourceId = '',
    this.version = 0,
    this.recordedAt = '',
    this.error,
  });

  factory SkillRefreshResult.fromJson(String jsonStr) {
    return SkillRefreshResult.fromMap(
        jsonDecode(jsonStr) as Map<String, dynamic>);
  }

  factory SkillRefreshResult.fromMap(Map<String, dynamic> map) {
    return SkillRefreshResult(
      success: map['success'] as bool? ?? false,
      agentId: _stringValue(map['agent_id'] ?? map['agentId']) ?? '',
      sourceId: _stringValue(map['source_id'] ?? map['sourceId']) ?? '',
      version: _intValue(map['version']) ?? 0,
      recordedAt: _stringValue(map['recorded_at'] ?? map['recordedAt']) ?? '',
      error: _stringValue(map['error']),
    );
  }
}

/// A user-invocable command contributed by a skill, including its dispatch
/// configuration, argument mode, and current eligibility.
class SkillCommand {
  final String name;
  final String skillName;
  final String description;
  final SkillCommandDispatch? dispatch;
  final String? argMode;
  final bool eligible;
  final String? disabledReason;

  const SkillCommand({
    required this.name,
    required this.skillName,
    this.description = '',
    this.dispatch,
    this.argMode,
    this.eligible = false,
    this.disabledReason,
  });

  factory SkillCommand.fromMap(Map<String, dynamic> map) {
    return SkillCommand(
      name: _stringValue(map['name']) ?? '',
      skillName: _stringValue(map['skill_name'] ?? map['skillName']) ?? '',
      description: _stringValue(map['description']) ?? '',
      dispatch: SkillCommandDispatch.fromMapOrNull(_mapValue(map['dispatch'])),
      argMode: _stringValue(map['arg_mode'] ?? map['argMode']),
      eligible: map['eligible'] as bool? ?? false,
      disabledReason:
          _stringValue(map['disabled_reason'] ?? map['disabledReason']),
    );
  }
}

/// How a skill command is dispatched (its kind and optional target tool).
class SkillCommandDispatch {
  final String kind;
  final String? toolName;

  const SkillCommandDispatch({this.kind = '', this.toolName});

  /// Parses [map] into a dispatch, or returns null if [map] is null.
  static SkillCommandDispatch? fromMapOrNull(Map<String, dynamic>? map) {
    if (map == null) return null;
    return SkillCommandDispatch.fromMap(map);
  }

  factory SkillCommandDispatch.fromMap(Map<String, dynamic> map) {
    return SkillCommandDispatch(
      kind: _stringValue(map['kind']) ?? '',
      toolName: _stringValue(map['tool_name'] ?? map['toolName']),
    );
  }
}

/// Result of resolving raw input to a skill command: whether it matched,
/// the resolved command and parsed args, or an error.
class SkillCommandResolution {
  final bool matched;
  final SkillCommand? command;
  final String? args;
  final String? error;

  const SkillCommandResolution({
    this.matched = false,
    this.command,
    this.args,
    this.error,
  });

  factory SkillCommandResolution.fromJson(String jsonStr) {
    return SkillCommandResolution.fromMap(
      jsonDecode(jsonStr) as Map<String, dynamic>,
    );
  }

  factory SkillCommandResolution.fromMap(Map<String, dynamic> map) {
    return SkillCommandResolution(
      matched: map['matched'] as bool? ?? false,
      command: _mapValue(map['command']) == null
          ? null
          : SkillCommand.fromMap(_mapValue(map['command'])!),
      args: _stringValue(map['args']),
      error: _stringValue(map['error']),
    );
  }
}

/// Outcome of executing a skill command, including its status, the session
/// it ran in, a user-facing message, and dispatch details.
class SkillCommandRun {
  final bool success;
  final String status;
  final String commandName;
  final String? skillName;
  final String? args;
  final String? sessionKey;
  final String? message;
  final SkillCommandDispatch? dispatch;
  final String? error;

  const SkillCommandRun({
    this.success = false,
    this.status = '',
    this.commandName = '',
    this.skillName,
    this.args,
    this.sessionKey,
    this.message,
    this.dispatch,
    this.error,
  });

  factory SkillCommandRun.fromJson(String jsonStr) {
    return SkillCommandRun.fromMap(
      jsonDecode(jsonStr) as Map<String, dynamic>,
    );
  }

  factory SkillCommandRun.fromMap(Map<String, dynamic> map) {
    return SkillCommandRun(
      success: map['success'] as bool? ?? false,
      status: _stringValue(map['status']) ?? '',
      commandName:
          _stringValue(map['command_name'] ?? map['commandName']) ?? '',
      skillName: _stringValue(map['skill_name'] ?? map['skillName']),
      args: _stringValue(map['args']),
      sessionKey: _stringValue(map['session_key'] ?? map['sessionKey']),
      message: _stringValue(map['message']),
      dispatch: SkillCommandDispatch.fromMapOrNull(_mapValue(map['dispatch'])),
      error: _stringValue(map['error']),
    );
  }
}

/// A list of skill snapshot index entries with the total count.
class SkillSnapshotList {
  final List<SkillSnapshotIndexEntry> snapshots;
  final int total;

  const SkillSnapshotList({this.snapshots = const [], this.total = 0});

  factory SkillSnapshotList.fromJson(String jsonStr) {
    return SkillSnapshotList.fromMap(
        jsonDecode(jsonStr) as Map<String, dynamic>);
  }

  factory SkillSnapshotList.fromMap(Map<String, dynamic> map) {
    final snapshots = _listValue(map['snapshots'])
        .whereType<Map>()
        .map((item) =>
            SkillSnapshotIndexEntry.fromMap(Map<String, dynamic>.from(item)))
        .toList();
    return SkillSnapshotList(
      snapshots: snapshots,
      total: _intValue(map['total']) ?? snapshots.length,
    );
  }
}

/// Lightweight index entry identifying a skill snapshot (id, agent,
/// purpose, and creation time).
class SkillSnapshotIndexEntry {
  final String snapshotId;
  final String agentId;
  final String purpose;
  final String createdAt;

  const SkillSnapshotIndexEntry({
    this.snapshotId = '',
    this.agentId = '',
    this.purpose = '',
    this.createdAt = '',
  });

  factory SkillSnapshotIndexEntry.fromMap(Map<String, dynamic> map) {
    return SkillSnapshotIndexEntry(
      snapshotId: _stringValue(map['snapshot_id'] ?? map['snapshotId']) ?? '',
      agentId: _stringValue(map['agent_id'] ?? map['agentId']) ?? '',
      purpose: _stringValue(map['purpose']) ?? '',
      createdAt: _stringValue(map['created_at'] ?? map['createdAt']) ?? '',
    );
  }
}

/// A full skill snapshot, extending [SkillSnapshotIndexEntry] with the
/// captured source versions, catalog/command entries, and status counts.
class SkillSnapshot extends SkillSnapshotIndexEntry {
  final Map<String, int> sourceVersions;
  final List<SkillSnapshotCatalogEntry> catalogEntries;
  final List<SkillCommand> commandEntries;
  final Map<String, dynamic> statusCounts;
  final Map<String, dynamic> catalogPlan;

  const SkillSnapshot({
    super.snapshotId,
    super.agentId,
    super.purpose,
    super.createdAt,
    this.sourceVersions = const {},
    this.catalogEntries = const [],
    this.commandEntries = const [],
    this.statusCounts = const {},
    this.catalogPlan = const {},
  });

  factory SkillSnapshot.fromJson(String jsonStr) {
    return SkillSnapshot.fromMap(jsonDecode(jsonStr) as Map<String, dynamic>);
  }

  factory SkillSnapshot.fromMap(Map<String, dynamic> map) {
    return SkillSnapshot(
      snapshotId: _stringValue(map['snapshot_id'] ?? map['snapshotId']) ?? '',
      agentId: _stringValue(map['agent_id'] ?? map['agentId']) ?? '',
      purpose: _stringValue(map['purpose']) ?? '',
      createdAt: _stringValue(map['created_at'] ?? map['createdAt']) ?? '',
      sourceVersions: _mapValue(map['source_versions'] ?? map['sourceVersions'])
              ?.map((key, value) => MapEntry(key, _intValue(value) ?? 0)) ??
          const {},
      catalogEntries:
          _listValue(map['catalog_entries'] ?? map['catalogEntries'])
              .whereType<Map>()
              .map((item) => SkillSnapshotCatalogEntry.fromMap(
                  Map<String, dynamic>.from(item)))
              .toList(),
      commandEntries: _listValue(
              map['command_entries'] ?? map['commandEntries'])
          .whereType<Map>()
          .map((item) => SkillCommand.fromMap(Map<String, dynamic>.from(item)))
          .toList(),
      statusCounts:
          _mapValue(map['status_counts'] ?? map['statusCounts']) ?? const {},
      catalogPlan:
          _mapValue(map['catalog_plan'] ?? map['catalogPlan']) ?? const {},
    );
  }
}

/// A catalog entry within a skill snapshot, recording the skill's name,
/// version, trust, activation hint, and content hash at capture time.
class SkillSnapshotCatalogEntry {
  final String name;
  final String version;
  final String description;
  final String trust;
  final String activationHint;
  final String contentHash;

  const SkillSnapshotCatalogEntry({
    this.name = '',
    this.version = '',
    this.description = '',
    this.trust = '',
    this.activationHint = '',
    this.contentHash = '',
  });

  factory SkillSnapshotCatalogEntry.fromMap(Map<String, dynamic> map) {
    return SkillSnapshotCatalogEntry(
      name: _stringValue(map['name']) ?? '',
      version: _stringValue(map['version']) ?? '',
      description: _stringValue(map['description']) ?? '',
      trust: _stringValue(map['trust']) ?? '',
      activationHint:
          _stringValue(map['activation_hint'] ?? map['activationHint']) ?? '',
      contentHash:
          _stringValue(map['content_hash'] ?? map['contentHash']) ?? '',
    );
  }
}

/// The set of secrets required by skills and whether each is available.
class SkillSecretRequirementReport {
  final List<SkillSecretRequirement> requirements;

  const SkillSecretRequirementReport({this.requirements = const []});

  factory SkillSecretRequirementReport.fromJson(String jsonStr) {
    return SkillSecretRequirementReport.fromMap(
        jsonDecode(jsonStr) as Map<String, dynamic>);
  }

  factory SkillSecretRequirementReport.fromMap(Map<String, dynamic> map) {
    return SkillSecretRequirementReport(
      requirements: _listValue(map['requirements'])
          .whereType<Map>()
          .map((item) =>
              SkillSecretRequirement.fromMap(Map<String, dynamic>.from(item)))
          .toList(),
    );
  }
}

/// A single secret a skill needs, identifying the skill, the secret key
/// and its source, and whether the value is currently available.
class SkillSecretRequirement {
  final String skillName;
  final String skillKey;
  final String key;
  final String source;
  final bool available;

  const SkillSecretRequirement({
    this.skillName = '',
    this.skillKey = '',
    this.key = '',
    this.source = '',
    this.available = false,
  });

  factory SkillSecretRequirement.fromMap(Map<String, dynamic> map) {
    return SkillSecretRequirement(
      skillName: _stringValue(map['skill_name'] ?? map['skillName']) ?? '',
      skillKey: _stringValue(map['skill_key'] ?? map['skillKey']) ?? '',
      key: _stringValue(map['key']) ?? '',
      source: _stringValue(map['source']) ?? '',
      available: map['available'] as bool? ?? false,
    );
  }
}

/// A list of skill remediation runs with the total count.
class SkillRemediationRunList {
  final List<SkillRemediationRun> runs;
  final int total;

  const SkillRemediationRunList({this.runs = const [], this.total = 0});

  factory SkillRemediationRunList.fromJson(String jsonStr) {
    return SkillRemediationRunList.fromMap(
        jsonDecode(jsonStr) as Map<String, dynamic>);
  }

  factory SkillRemediationRunList.fromMap(Map<String, dynamic> map) {
    final runs = _listValue(map['runs'])
        .whereType<Map>()
        .map((item) =>
            SkillRemediationRun.fromMap(Map<String, dynamic>.from(item)))
        .toList();
    return SkillRemediationRunList(
      runs: runs,
      total: _intValue(map['total']) ?? runs.length,
    );
  }
}

/// A tracked execution of a skill remediation action, with its status,
/// request/update timestamps, and optional result payload.
class SkillRemediationRun {
  final String runId;
  final String agentId;
  final String skillName;
  final String actionId;
  final String status;
  final String requestedAt;
  final String updatedAt;
  final Map<String, dynamic>? result;

  const SkillRemediationRun({
    this.runId = '',
    this.agentId = '',
    this.skillName = '',
    this.actionId = '',
    this.status = '',
    this.requestedAt = '',
    this.updatedAt = '',
    this.result,
  });

  factory SkillRemediationRun.fromJson(String jsonStr) {
    return SkillRemediationRun.fromMap(
        jsonDecode(jsonStr) as Map<String, dynamic>);
  }

  factory SkillRemediationRun.fromMap(Map<String, dynamic> map) {
    return SkillRemediationRun(
      runId: _stringValue(map['run_id'] ?? map['runId']) ?? '',
      agentId: _stringValue(map['agent_id'] ?? map['agentId']) ?? '',
      skillName: _stringValue(map['skill_name'] ?? map['skillName']) ?? '',
      actionId: _stringValue(map['action_id'] ?? map['actionId']) ?? '',
      status: _stringValue(map['status']) ?? '',
      requestedAt:
          _stringValue(map['requested_at'] ?? map['requestedAt']) ?? '',
      updatedAt: _stringValue(map['updated_at'] ?? map['updatedAt']) ?? '',
      result: _mapValue(map['result']),
    );
  }
}

/// Usage statistics for a single named skill, extending the shared
/// [SkillLifecycleSummary] with the skill name and creation time.
class SkillUsageRecord extends SkillLifecycleSummary {
  final String skillName;
  final String? createdAt;

  const SkillUsageRecord({
    required this.skillName,
    this.createdAt,
    super.state,
    super.pinned,
    super.protected,
    super.createdBy,
    super.useCount,
    super.viewCount,
    super.patchCount,
    super.lastUsedAt,
    super.lastViewedAt,
    super.lastPatchedAt,
    super.archivedAt,
    super.absorbedInto,
  });

  factory SkillUsageRecord.fromMap(Map<String, dynamic> map) {
    return SkillUsageRecord(
      skillName: map['skill_name'] as String? ?? '',
      createdAt: map['created_at'] as String?,
      state: map['state'] as String? ?? 'active',
      pinned: map['pinned'] as bool? ?? false,
      protected: map['protected'] as bool? ?? false,
      createdBy: map['created_by'] as String?,
      useCount: (map['use_count'] as num?)?.toInt() ?? 0,
      viewCount: (map['view_count'] as num?)?.toInt() ?? 0,
      patchCount: (map['patch_count'] as num?)?.toInt() ?? 0,
      lastUsedAt: map['last_used_at'] as String?,
      lastViewedAt: map['last_viewed_at'] as String?,
      lastPatchedAt: map['last_patched_at'] as String?,
      archivedAt: map['archived_at'] as String?,
      absorbedInto: map['absorbed_into'] as String?,
    );
  }
}

/// Summary of a skill-curator pass that ages, archives, or restores skills,
/// reporting how many were checked and what actions were taken (or would be
/// in a dry run).
class CuratorRunSummary {
  final bool dryRun;
  final int checked;
  final int markedStale;
  final int archived;
  final int restoredActive;
  final int protectedSkipped;
  final List<String> actions;

  const CuratorRunSummary({
    this.dryRun = true,
    this.checked = 0,
    this.markedStale = 0,
    this.archived = 0,
    this.restoredActive = 0,
    this.protectedSkipped = 0,
    this.actions = const [],
  });

  factory CuratorRunSummary.fromJson(String jsonStr) {
    final map = jsonDecode(jsonStr) as Map<String, dynamic>;
    return CuratorRunSummary(
      dryRun: map['dry_run'] as bool? ?? true,
      checked: (map['checked'] as num?)?.toInt() ?? 0,
      markedStale: (map['marked_stale'] as num?)?.toInt() ?? 0,
      archived: (map['archived'] as num?)?.toInt() ?? 0,
      restoredActive: (map['restored_active'] as num?)?.toInt() ?? 0,
      protectedSkipped: (map['protected_skipped'] as num?)?.toInt() ?? 0,
      actions: (map['actions'] as List?)?.cast<String>() ?? const [],
    );
  }
}

/// Result of reading a skill's support file, returning its content on
/// success or an error otherwise.
class SkillSupportFileReadResult {
  final bool success;
  final String? skillName;
  final String? filePath;
  final String? content;
  final String? error;

  const SkillSupportFileReadResult({
    this.success = false,
    this.skillName,
    this.filePath,
    this.content,
    this.error,
  });

  factory SkillSupportFileReadResult.fromJson(String jsonStr) {
    final map = jsonDecode(jsonStr) as Map<String, dynamic>;
    return SkillSupportFileReadResult(
      success: map['success'] as bool? ?? false,
      skillName: map['skill_name'] as String?,
      filePath: map['file_path'] as String?,
      content: map['content'] as String?,
      error: map['error'] as String?,
    );
  }
}

/// Payload for installing a skill: its SKILL.md source plus any extra
/// bundled files.
class SkillInstallInput {
  final String skillMd;
  final List<SkillInstallExtraFile> extraFiles;

  const SkillInstallInput({
    required this.skillMd,
    this.extraFiles = const [],
  });

  /// Encodes this input as the JSON payload expected by the install API.
  String toInstallPayloadJson() {
    return jsonEncode({
      'skill_md': skillMd,
      'extra_files': extraFiles.map((file) => file.toMap()).toList(),
    });
  }
}

/// An extra binary file bundled with a skill install, identified by its
/// relative path and raw bytes.
class SkillInstallExtraFile {
  final String path;
  final Uint8List bytes;

  const SkillInstallExtraFile({
    required this.path,
    required this.bytes,
  });

  /// Serializes this file to a map with base64-encoded content.
  Map<String, dynamic> toMap() {
    return {
      'path': path,
      'content_base64': base64Encode(bytes),
    };
  }
}

/// Skill 安装结果
class SkillInstallResult {
  final String? name;
  final bool success;
  final String? error;

  const SkillInstallResult({this.name, this.success = false, this.error});

  factory SkillInstallResult.fromJson(String jsonStr) {
    final map = jsonDecode(jsonStr) as Map<String, dynamic>;
    if (map.containsKey('error')) {
      return SkillInstallResult(error: map['error'] as String);
    }
    return SkillInstallResult(
      name: map['name'] as String?,
      success: map['success'] as bool? ?? false,
    );
  }
}

/// Skill catalog search result.
class CatalogSearchResult {
  final List<CatalogSkillInfo> results;
  final String? error;

  const CatalogSearchResult({this.results = const [], this.error});

  factory CatalogSearchResult.fromJson(String jsonStr) {
    final map = jsonDecode(jsonStr) as Map<String, dynamic>;
    final list = (map['results'] as List?) ?? [];
    return CatalogSearchResult(
      results: list
          .map((e) => CatalogSkillInfo.fromMap(e as Map<String, dynamic>))
          .toList(),
      error: _stringValue(map['error']),
    );
  }

  @override
  String toString() =>
      'CatalogSearchResult(${results.length} results${error != null ? ', error: $error' : ''})';
}

/// Skill catalog package page.
class CatalogPackagePage {
  final List<CatalogSkillInfo> items;
  final String? nextCursor;
  final String? error;

  const CatalogPackagePage({
    this.items = const [],
    this.nextCursor,
    this.error,
  });

  factory CatalogPackagePage.fromJson(String jsonStr) {
    final map = jsonDecode(jsonStr) as Map<String, dynamic>;
    final list = (map['items'] as List?) ?? [];
    return CatalogPackagePage(
      items: list
          .map((e) => CatalogSkillInfo.fromMap(e as Map<String, dynamic>))
          .toList(),
      nextCursor: _stringValue(map['nextCursor'] ?? map['next_cursor']),
      error: _stringValue(map['error']),
    );
  }

  @override
  String toString() =>
      'CatalogPackagePage(${items.length} items${nextCursor != null ? ', nextCursor: $nextCursor' : ''}${error != null ? ', error: $error' : ''})';
}

/// Skill catalog skill information.
class CatalogSkillInfo {
  final String slug;
  final String name;
  final String description;
  final String version;
  final double score;
  final int? stars;
  final int? downloads;
  final int? installsCurrent;
  final int? installsAllTime;
  final String? owner;
  final String? ownerName;
  final String? summary;
  final List<String> tags;
  final DateTime? updatedAt;

  const CatalogSkillInfo({
    required this.slug,
    this.name = '',
    this.description = '',
    this.version = '',
    this.score = 0,
    this.stars,
    this.downloads,
    this.installsCurrent,
    this.installsAllTime,
    this.owner,
    this.ownerName,
    this.summary,
    this.tags = const [],
    this.updatedAt,
  });

  factory CatalogSkillInfo.fromMap(Map<String, dynamic> map) {
    final updatedAtValue = map['updatedAt'];
    final latestVersion = _mapValue(map['latestVersion']);
    final stats = _mapValue(map['stats']);
    final owner = _mapValue(map['owner']);
    final tags = _stringListValue(map['tags']);
    final capabilityTags = _stringListValue(map['capabilityTags']);
    return CatalogSkillInfo(
      slug: _stringValue(map['slug']) ?? _stringValue(map['name']) ?? '',
      name: _stringValue(map['displayName']) ??
          _stringValue(map['name']) ??
          _stringValue(map['slug']) ??
          '',
      description: _stringValue(map['description']) ??
          _stringValue(map['summary']) ??
          '',
      version: _stringValue(map['version']) ??
          _stringValue(latestVersion?['version']) ??
          '',
      score: _doubleValue(map['score']),
      stars: _intValue(map['stars'] ?? stats?['stars']),
      downloads: _intValue(map['downloads'] ?? stats?['downloads']),
      installsCurrent:
          _intValue(map['installsCurrent'] ?? stats?['installsCurrent']),
      installsAllTime:
          _intValue(map['installsAllTime'] ?? stats?['installsAllTime']),
      owner: _stringValue(map['owner']) ??
          _stringValue(map['ownerHandle']) ??
          _stringValue(owner?['handle']),
      ownerName:
          _stringValue(map['ownerName']) ?? _stringValue(owner?['displayName']),
      summary: _stringValue(map['summary']),
      tags: tags.isNotEmpty ? tags : capabilityTags,
      updatedAt: updatedAtValue is num
          ? DateTime.fromMillisecondsSinceEpoch(updatedAtValue.toInt())
          : null,
    );
  }

  factory CatalogSkillInfo.fromJson(String jsonStr) {
    return CatalogSkillInfo.fromMap(
        jsonDecode(jsonStr) as Map<String, dynamic>);
  }

  @override
  String toString() => 'CatalogSkillInfo($slug, $name)';
}

Map<String, dynamic>? _mapValue(Object? value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) return Map<String, dynamic>.from(value);
  return null;
}

String? _stringValue(Object? value) {
  if (value is String) return value;
  if (value is num || value is bool) return '$value';
  return null;
}

int? _intValue(Object? value) {
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

List<String> _stringListValue(Object? value) {
  if (value is List) return value.whereType<String>().toList();
  return const [];
}

List<Object?> _listValue(Object? value) {
  if (value is List) return value;
  return const [];
}

/// 工具信息（用于 listAvailableTools）
class ToolInfo {
  final String name;
  final String description;

  const ToolInfo({required this.name, this.description = ''});

  factory ToolInfo.fromMap(Map<String, dynamic> map) {
    return ToolInfo(
      name: map['name'] as String? ?? '',
      description: map['description'] as String? ?? '',
    );
  }

  @override
  String toString() => 'ToolInfo($name)';
}
