part of '../main.dart';

const String _developerScenarioAccountId = 'mobile_development';
const String _defaultDeveloperEngineId = 'napaxi';
const String _defaultDeveloperEngineAgentId = 'engine.napaxi';
const String _activeDeveloperEngineKey = 'scenario.developer.active_engine.v1';
const String _gitSettingsContributionId = 'settings.git';
const String _gitSettingsPreferencesKey = 'scenario.git_settings.v1';
const String _gitProviderConfiguredKey = 'git_provider_configured';
const String _gitProviderHealthyKey = 'git_provider_healthy';
const String _gitCredentialRefKey = 'git_credential_ref';
const String _gitServerKey = 'git_server';
const String _gitUsernameKey = 'git_username';
const String _gitAuthMethodKey = 'git_auth_method';
const String _gitLastTestedAtMsKey = 'git_last_tested_at_ms';
const String _gitCommitNameKey = 'git_commit_name';
const String _gitCommitEmailKey = 'git_commit_email';

enum DemoScenarioRuntimeMode { general, developer }

class DemoScenarioEngineSpec {
  const DemoScenarioEngineSpec({
    required this.id,
    required this.label,
    required this.agentId,
    required this.icon,
    required this.enabled,
    this.description = '',
  });

  final String id;
  final String label;
  final String agentId;
  final IconData icon;
  final bool enabled;
  final String description;

  DemoAgent toAgent() => DemoAgent(id: agentId, name: label, icon: icon);
}

class DemoScenarioRuntimeProfile {
  const DemoScenarioRuntimeProfile({
    required this.scenarioId,
    required this.mode,
    required this.accountId,
    required this.agentId,
    required this.supportsAgents,
    required this.engines,
    required this.activeEngineId,
  });

  final String scenarioId;
  final DemoScenarioRuntimeMode mode;
  final String accountId;
  final String agentId;
  final bool supportsAgents;
  final List<DemoScenarioEngineSpec> engines;
  final String activeEngineId;

  bool get isDeveloper => mode == DemoScenarioRuntimeMode.developer;

  DemoScenarioEngineSpec get activeEngine {
    return engines.firstWhere(
      (engine) => engine.id == activeEngineId,
      orElse: () => engines.isEmpty
          ? _generalAssistantEngine
          : engines.firstWhere(
              (engine) => engine.enabled,
              orElse: () => engines.first,
            ),
    );
  }

  DemoAgent get primaryAgent {
    if (supportsAgents) return _defaultDemoAgent;
    return activeEngine.toAgent();
  }
}

const DemoScenarioEngineSpec _generalAssistantEngine = DemoScenarioEngineSpec(
  id: 'assistant',
  label: 'napaxi',
  agentId: sdk.NapaxiEngine.defaultAgentId,
  icon: Icons.auto_awesome_rounded,
  enabled: true,
);

const List<DemoScenarioEngineSpec> _developerEngineSpecs = [
  DemoScenarioEngineSpec(
    id: _defaultDeveloperEngineId,
    label: 'napaxi',
    agentId: _defaultDeveloperEngineAgentId,
    icon: Icons.terminal_rounded,
    enabled: true,
    description: 'Built-in mobile SDK engine.',
  ),
  DemoScenarioEngineSpec(
    id: 'cc',
    label: 'CC',
    agentId: 'engine.cc',
    icon: Icons.code_rounded,
    enabled: true,
    description: 'Claude Code CLI engine.',
  ),
  DemoScenarioEngineSpec(
    id: 'codex',
    label: 'Codex',
    agentId: 'engine.codex',
    icon: Icons.data_object_rounded,
    enabled: true,
    description: 'OpenAI Codex CLI engine.',
  ),
];

DemoScenarioRuntimeProfile _scenarioRuntimeProfileFor(
  String? scenarioId, {
  String? developerEngineId,
}) {
  final normalizedScenarioId = _normalizeDemoScenarioId(scenarioId);
  if (normalizedScenarioId != _mobileDevelopmentScenarioId) {
    return DemoScenarioRuntimeProfile(
      scenarioId: normalizedScenarioId,
      mode: DemoScenarioRuntimeMode.general,
      accountId: _demoAccountId,
      agentId: sdk.NapaxiEngine.defaultAgentId,
      supportsAgents: true,
      engines: const [_generalAssistantEngine],
      activeEngineId: _generalAssistantEngine.id,
    );
  }

  final requestedEngineId = (developerEngineId ?? _defaultDeveloperEngineId)
      .trim()
      .toLowerCase();
  final activeEngine = _developerEngineSpecs.firstWhere(
    (engine) => engine.enabled && engine.id == requestedEngineId,
    orElse: () => _developerEngineSpecs.first,
  );
  return DemoScenarioRuntimeProfile(
    scenarioId: normalizedScenarioId,
    mode: DemoScenarioRuntimeMode.developer,
    accountId: _developerScenarioAccountId,
    agentId: activeEngine.agentId,
    supportsAgents: false,
    engines: _developerEngineSpecs,
    activeEngineId: activeEngine.id,
  );
}

List<DemoAgent> _visibleAgentsForRuntimeProfile(
  DemoScenarioRuntimeProfile runtimeProfile,
  Iterable<DemoAgent> agents,
) {
  if (!runtimeProfile.supportsAgents) {
    return List.unmodifiable([runtimeProfile.primaryAgent]);
  }

  final visible = <DemoAgent>[];
  final seen = <String>{};

  void addVisible(DemoAgent agent) {
    final id = agent.id.trim();
    if (id.isEmpty || _isScenarioRuntimeAgentId(id) || !seen.add(id)) return;
    visible.add(agent);
  }

  addVisible(_defaultDemoAgent);
  for (final agent in agents) {
    addVisible(agent);
  }
  return List.unmodifiable(visible);
}

bool _isScenarioRuntimeAgentId(String agentId) {
  final normalized = agentId.trim();
  if (normalized.isEmpty) return false;
  if (normalized.startsWith('engine.')) return true;
  return _developerEngineSpecs.any((engine) => engine.agentId == normalized);
}

class DemoGitSettings {
  const DemoGitSettings({
    this.server = '',
    this.authMethod = 'token',
    this.username = '',
    this.credentialRef = '',
    this.configured = false,
    this.healthy = false,
    this.lastTestedAtMs,
    this.commitName = '',
    this.commitEmail = '',
  });

  final String server;
  final String authMethod;
  final String username;
  final String credentialRef;
  final bool configured;
  final bool healthy;
  final int? lastTestedAtMs;
  /// Commit identity (`user.name`) written to the sandbox rootfs `~/.gitconfig`.
  final String commitName;
  /// Commit identity (`user.email`) written to the sandbox rootfs `~/.gitconfig`.
  final String commitEmail;

  /// Both identity fields are present and safe to write into the rootfs.
  bool get hasCommitIdentity =>
      commitName.trim().isNotEmpty && commitEmail.trim().isNotEmpty;

  bool get isReady =>
      configured &&
      healthy &&
      server.trim().isNotEmpty &&
      username.trim().isNotEmpty &&
      credentialRef.trim().isNotEmpty;

  String get normalizedAuthMethod {
    final normalized = authMethod.trim().toLowerCase();
    return normalized == 'ssh' ? 'ssh' : 'token';
  }

  DemoGitSettings copyWith({
    String? server,
    String? authMethod,
    String? username,
    String? credentialRef,
    bool? configured,
    bool? healthy,
    int? lastTestedAtMs,
    String? commitName,
    String? commitEmail,
    bool clearLastTestedAtMs = false,
  }) {
    return DemoGitSettings(
      server: server ?? this.server,
      authMethod: authMethod ?? this.authMethod,
      username: username ?? this.username,
      credentialRef: credentialRef ?? this.credentialRef,
      configured: configured ?? this.configured,
      healthy: healthy ?? this.healthy,
      lastTestedAtMs: clearLastTestedAtMs
          ? null
          : (lastTestedAtMs ?? this.lastTestedAtMs),
      commitName: commitName ?? this.commitName,
      commitEmail: commitEmail ?? this.commitEmail,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      _gitServerKey: server,
      _gitAuthMethodKey: normalizedAuthMethod,
      _gitUsernameKey: username,
      _gitCredentialRefKey: credentialRef,
      _gitProviderConfiguredKey: configured,
      _gitProviderHealthyKey: healthy,
      if (lastTestedAtMs != null) _gitLastTestedAtMsKey: lastTestedAtMs,
      _gitCommitNameKey: commitName,
      _gitCommitEmailKey: commitEmail,
    };
  }

  factory DemoGitSettings.fromJson(Map<String, dynamic> json) {
    final authMethod =
        (json[_gitAuthMethodKey] as String? ??
                json['auth_method'] as String? ??
                'token')
            .trim()
            .toLowerCase();
    return DemoGitSettings(
      server: (json[_gitServerKey] as String? ?? '').trim(),
      authMethod: authMethod == 'ssh' ? 'ssh' : 'token',
      username: (json[_gitUsernameKey] as String? ?? '').trim(),
      credentialRef: (json[_gitCredentialRefKey] as String? ?? '').trim(),
      configured: json[_gitProviderConfiguredKey] as bool? ?? false,
      healthy: json[_gitProviderHealthyKey] as bool? ?? false,
      lastTestedAtMs: json[_gitLastTestedAtMsKey] as int?,
      commitName: (json[_gitCommitNameKey] as String? ?? '').trim(),
      commitEmail: (json[_gitCommitEmailKey] as String? ?? '').trim(),
    );
  }

  factory DemoGitSettings.fromForm({
    required String server,
    required String authMethod,
    required String username,
    required String secret,
    required DemoGitSettings previous,
    bool markHealthy = true,
    String commitName = '',
    String commitEmail = '',
  }) {
    final normalizedServer = server.trim();
    final normalizedAuthMethod = authMethod.trim().toLowerCase() == 'ssh'
        ? 'ssh'
        : 'token';
    final normalizedUsername = username.trim();
    final nextCredentialRef = _nextGitCredentialRef(
      server: normalizedServer,
      authMethod: normalizedAuthMethod,
      username: normalizedUsername,
      secret: secret,
      previous: previous,
    );
    final configured =
        normalizedServer.isNotEmpty &&
        normalizedUsername.isNotEmpty &&
        nextCredentialRef.trim().isNotEmpty;
    return DemoGitSettings(
      server: normalizedServer,
      authMethod: normalizedAuthMethod,
      username: normalizedUsername,
      credentialRef: nextCredentialRef,
      configured: configured,
      healthy: configured && markHealthy,
      lastTestedAtMs: configured ? DateTime.now().millisecondsSinceEpoch : null,
      commitName: commitName.trim(),
      commitEmail: commitEmail.trim(),
    );
  }
}

Future<DemoGitSettings> _loadDemoGitSettings() async {
  final preferences = await SharedPreferences.getInstance();
  final raw = preferences.getString(_gitSettingsPreferencesKey);
  if (raw == null || raw.trim().isEmpty) return const DemoGitSettings();
  try {
    final decoded = jsonDecode(raw);
    if (decoded is Map) {
      return DemoGitSettings.fromJson(Map<String, dynamic>.from(decoded));
    }
  } catch (_) {}
  return const DemoGitSettings();
}

Future<void> _saveDemoGitSettings(DemoGitSettings settings) async {
  final preferences = await SharedPreferences.getInstance();
  await preferences.setString(
    _gitSettingsPreferencesKey,
    jsonEncode(settings.toJson()),
  );
}

Future<void> _clearDemoGitSettings() async {
  final preferences = await SharedPreferences.getInstance();
  await preferences.remove(_gitSettingsPreferencesKey);
}

String _nextGitCredentialRef({
  required String server,
  required String authMethod,
  required String username,
  required String secret,
  required DemoGitSettings previous,
}) {
  final hasNewSecret = secret.trim().isNotEmpty;
  final previousMatches =
      previous.server.trim() == server.trim() &&
      previous.normalizedAuthMethod == authMethod.trim().toLowerCase() &&
      previous.username.trim() == username.trim();
  if (!hasNewSecret && previousMatches) {
    return previous.credentialRef.trim();
  }
  if (!hasNewSecret && authMethod != 'ssh') return '';
  final encodedServer = Uri.encodeComponent(server.trim());
  final encodedUser = Uri.encodeComponent(username.trim());
  return 'secret://git/$authMethod/$encodedServer/$encodedUser';
}
