/// Project metadata persisted by Napaxi Core.
class NapaxiProject {
  const NapaxiProject({
    required this.id,
    required this.accountId,
    required this.agentId,
    required this.name,
    required this.defaultWorkspaceId,
    required this.state,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String accountId;
  final String agentId;
  final String name;
  final String defaultWorkspaceId;
  final String state;
  final DateTime createdAt;
  final DateTime updatedAt;

  factory NapaxiProject.fromMap(Map<String, dynamic> map) => NapaxiProject(
    id: map['id'] as String? ?? '',
    accountId: map['account_id'] as String? ?? '',
    agentId: map['agent_id'] as String? ?? '',
    name: map['name'] as String? ?? '',
    defaultWorkspaceId: map['default_workspace_id'] as String? ?? '',
    state: map['state'] as String? ?? 'active',
    createdAt:
        DateTime.tryParse(map['created_at'] as String? ?? '') ?? DateTime(0),
    updatedAt:
        DateTime.tryParse(map['updated_at'] as String? ?? '') ?? DateTime(0),
  );
}

/// Controls whether a display-project move also changes execution workspace.
enum NapaxiWorkspacePolicy {
  useProjectDefault('use_project_default'),
  keepCurrent('keep_current'),
  usePersonalDefault('use_personal_default');

  const NapaxiWorkspacePolicy(this.wireValue);
  final String wireValue;
}

/// Independent display and execution placement for one immutable session.
class NapaxiSessionPlacement {
  const NapaxiSessionPlacement({
    required this.threadId,
    required this.projectId,
    required this.runtimeWorkspaceId,
    required this.workingDirectory,
    required this.revision,
    required this.projectEnteredAt,
    required this.workspaceUpdatedAt,
  });

  final String threadId;
  final String? projectId;
  final String runtimeWorkspaceId;
  final String? workingDirectory;
  final int revision;
  final DateTime? projectEnteredAt;
  final DateTime workspaceUpdatedAt;

  bool runtimeMatchesProject(NapaxiProject project) =>
      runtimeWorkspaceId == project.defaultWorkspaceId;

  factory NapaxiSessionPlacement.fromMap(Map<String, dynamic> map) {
    final enteredAt = map['project_entered_at'] as String?;
    return NapaxiSessionPlacement(
      threadId: map['thread_id'] as String? ?? '',
      projectId: map['project_id'] as String?,
      runtimeWorkspaceId: map['runtime_workspace_id'] as String? ?? '',
      workingDirectory: map['working_directory'] as String?,
      revision: (map['revision'] as num?)?.toInt() ?? 0,
      projectEnteredAt: enteredAt == null ? null : DateTime.tryParse(enteredAt),
      workspaceUpdatedAt:
          DateTime.tryParse(map['workspace_updated_at'] as String? ?? '') ??
          DateTime(0),
    );
  }
}
