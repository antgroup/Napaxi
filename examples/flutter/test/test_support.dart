import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:napaxi/main.dart';
import 'package:napaxi_flutter/napaxi_flutter.dart' as sdk;
import 'package:napaxi_flutter/advanced.dart' as sdk;

class FakeHistoryPageRequest {
  const FakeHistoryPageRequest({
    required this.threadId,
    required this.agentId,
    required this.before,
    required this.limit,
  });

  final String threadId;
  final String agentId;
  final String? before;
  final int limit;
}

class FakeGitRepositoryChildrenRequest {
  const FakeGitRepositoryChildrenRequest({
    required this.directory,
    required this.subdir,
    required this.query,
    required this.limit,
  });

  final String directory;
  final String subdir;
  final String query;
  final int limit;
}

class FakeNapaxiChatClient implements NapaxiChatClient {
  FakeNapaxiChatClient({
    this.events,
    this.eventStream,
    this.eventStreamsByThreadId = const {},
    this.createdThreadIds = const {},
    this.sessions = const [],
    this.historyByThreadId = const {},
    this.contextStatusByThreadId = const {},
    this.memoryFilesByDirectory = const {},
    this.memoryFilesByPath = const {},
    this.journalDays = const [],
    this.journalRecordsByDate = const {},
    this.workspaceFiles = const [],
    this.gitRepositories = const [],
    this.gitStatuses = const {},
    this.gitBranches = const {},
    this.gitRemotes = const {},
    this.gitRepositoryChildren = const {},
    this.gitChangesSets = const {},
    this.gitFileDiffs = const {},
    this.gitCommitHistory = const {},
    this.gitCommitDiffs = const {},
    this.detectedFiles = const [],
    this.scenarioPacks = const [],
    this.scenarioStatuses = const [],
    this.scenarioResolution,
    this.agents = const [],
    this.skills = const [],
    this.skillStatusReport,
    this.skillUsage = const [],
    this.skillSupportFiles = const {},
    List<Map<String, dynamic>> pendingEvolution = const [],
    this.evolutionRuns = const [],
    this.catalogResults = const [],
    this.catalogPackages = const [],
    this.supportsBackgroundExecution = true,
    this.backgroundPermissionGranted = true,
  }) : pendingEvolution = List<Map<String, dynamic>>.from(pendingEvolution);

  final List<sdk.ChatEvent>? events;
  final Stream<sdk.ChatEvent>? eventStream;
  final Map<String, Stream<sdk.ChatEvent>> eventStreamsByThreadId;
  final Map<String, String> createdThreadIds;
  final List<sdk.SessionInfo> sessions;
  final Map<String, List<sdk.ChatMessage>> historyByThreadId;
  final Map<String, sdk.ContextStatus> contextStatusByThreadId;
  final Map<String, List<sdk.WorkspaceEntry>> memoryFilesByDirectory;
  final Map<String, sdk.WorkspaceFile> memoryFilesByPath;
  final List<sdk.JournalDay> journalDays;
  final Map<String, List<sdk.JournalTurnRecord>> journalRecordsByDate;
  final List<sdk.WorkspaceFileInfo> workspaceFiles;
  final List<DemoRepositoryInfo> gitRepositories;
  final Map<String, DemoGitRepositoryStatus> gitStatuses;
  final Map<String, List<DemoGitBranchInfo>> gitBranches;
  final Map<String, List<DemoGitRemoteInfo>> gitRemotes;
  final Map<String, List<DemoRepositoryFileItem>> gitRepositoryChildren;
  final Map<String, DemoGitChangeSet> gitChangesSets;
  final Map<String, DemoGitFileDiff> gitFileDiffs;
  final Map<String, List<DemoGitCommitInfo>> gitCommitHistory;
  final Map<String, DemoGitCommitDiff> gitCommitDiffs;
  final List<sdk.ResolvedFile> detectedFiles;
  final List<sdk.NapaxiScenarioPack> scenarioPacks;
  final List<sdk.NapaxiScenarioStatus> scenarioStatuses;
  final sdk.NapaxiScenarioResolution? scenarioResolution;
  final List<DemoAgent> agents;
  List<sdk.SkillInfo> skills;
  final sdk.SkillStatusReport? skillStatusReport;
  final List<sdk.SkillUsageRecord> skillUsage;
  final Map<String, String> skillSupportFiles;
  final List<Map<String, dynamic>> pendingEvolution;
  final List<sdk.EvolutionRun> evolutionRuns;
  final List<sdk.CatalogSkillInfo> catalogResults;
  final List<sdk.CatalogSkillInfo> catalogPackages;
  @override
  final bool supportsBackgroundExecution;
  bool backgroundPermissionGranted;
  LlmModelProfile? configuredProfile;
  String configuredResponseLanguage = 'en';
  sdk.NapaxiCapabilitySelection? configuredCapabilitySelection;
  sdk.NapaxiCapabilitySelection? appliedCapabilitySelection;
  sdk.SessionKey? canceledSession;
  String? canceledAgentId;
  sdk.SessionKey? deletedSession;
  String? deletedAgentId;
  sdk.SessionKey? injectedSession;
  String? injectedMessage;
  String? injectedAgentId;
  sdk.SessionKey? retractedSession;
  String? retractedMessage;
  String? answeredHumanRequestId;
  String? answeredHumanResponse;
  int? lastMaxIterations;
  String? lastListSessionsAgentId;
  final sentThreadIds = <String>[];
  final sentMessages = <String>[];
  String? lastSkillAgentId;
  String? viewedSkillName;
  String? readSupportSkillName;
  String? readSupportFilePath;
  String? updatedSkillConfigKey;
  Map<String, dynamic>? updatedSkillConfigPatch;
  String? toggledSkillName;
  bool? toggledSkillEnabled;
  String? requestedRemediationSkillName;
  String? requestedRemediationActionId;
  String? removedSkillName;
  String? removedSkillAgentId;
  String? appliedPendingEvolutionId;
  String? rejectedPendingEvolutionId;
  String? pinnedSkillName;
  bool? pinnedSkillValue;
  String? archivedSkillName;
  String? restoredSkillName;
  bool? lastCuratorDryRun;
  bool? lastConsolidationDryRun;
  String? installedCatalogSlug;
  String? submittedLocalA2AChannelTaskId;
  String? submittedLocalA2AChannelPeerId;
  String? ranLocalA2AChannelTaskId;
  String? ranLocalA2AChannelAgentId;
  String? installedCatalogAgentId;
  String? installedScenarioId;
  String? removedScenarioId;
  String? switchedGitDirectory;
  String? switchedGitBranch;
  bool? switchedGitBranchWasRemote;
  bool? switchedGitBranchAllowedDirty;
  String? setGitRemoteDirectory;
  String? setGitRemoteName;
  String? setGitRemoteUrl;
  String? removedGitRemoteDirectory;
  String? removedGitRemoteName;
  String? fetchedGitDirectory;
  String? fetchedGitRemote;
  String? pushedGitDirectory;
  String? pushedGitRemote;
  String? pulledGitDirectory;
  String? pulledGitRemote;
  final gitChangesRequests = <String>[];
  final stagedGitPaths = <String>[];
  final unstagedGitPaths = <String>[];
  final discardedGitPaths = <String>[];
  final commitMessages = <String>[];
  final detectedFileTexts = <String>[];
  final deletedSandboxWorkspacePaths = <String>[];
  var cancelCount = 0;
  var deleteCount = 0;
  var retractCount = 0;
  var skillReloadCount = 0;
  var backgroundPermissionRequestCount = 0;
  var stopBackgroundServiceCount = 0;
  var ensureConfiguredChannelsCount = 0;
  var contextStatusRequestCount = 0;
  var historyRequestCount = 0;
  final historyPageRequests = <FakeHistoryPageRequest>[];
  final gitRepositoryChildrenRequests = <FakeGitRepositoryChildrenRequest>[];
  final localA2ADeliveries = <sdk.A2ADeliveryRecord>[];
  final localA2AMessages = <sdk.A2APeerMessage>[];
  final StreamController<sdk.BackgroundActionEvent> backgroundActions =
      StreamController<sdk.BackgroundActionEvent>.broadcast();
  final StreamController<DemoChannelBridgeEvent> channelBridgeEvents =
      StreamController<DemoChannelBridgeEvent>.broadcast();
  final StreamController<sdk.A2ALocalTransportEvent> a2aLocalEvents =
      StreamController<sdk.A2ALocalTransportEvent>.broadcast();
  final Map<String, DemoChannelCredentials> channelCredentials = {};
  var managementConfigureCount = 0;

  @override
  sdk.NapaxiBrowserController? get browserController => null;

  @override
  Future<void> configureForManagement({
    sdk.NapaxiCapabilitySelection? capabilitySelection,
  }) async {
    managementConfigureCount += 1;
    configuredCapabilitySelection = capabilitySelection;
  }

  @override
  Future<void> configure(
    LlmModelProfile profile, {
    String responseLanguage = 'en',
    sdk.NapaxiCapabilitySelection? capabilitySelection,
  }) async {
    configuredProfile = profile;
    configuredResponseLanguage = responseLanguage;
    configuredCapabilitySelection = capabilitySelection;
  }

  @override
  void resetCliBridge(String engineId) {}

  @override
  Future<void> clearCliNativeId(String engineId) async {}

  @override
  Future<void> applyCapabilitySelection(
    sdk.NapaxiCapabilitySelection capabilitySelection,
  ) async {
    appliedCapabilitySelection = capabilitySelection;
  }

  @override
  Future<List<DemoAgent>> listAgents() async {
    return agents.isEmpty
        ? const [
            DemoAgent(
              id: sdk.NapaxiEngine.defaultAgentId,
              name: 'napaxi',
              icon: Icons.auto_awesome_rounded,
            ),
          ]
        : agents;
  }

  @override
  Future<DemoAgent> createAgent({
    required String name,
    String systemPrompt = '',
    String? modelProfileId,
  }) async {
    return DemoAgent(id: name.toLowerCase(), name: name, icon: Icons.person);
  }

  @override
  Future<DemoAgent> updateAgent({
    required String agentId,
    required String name,
    String systemPrompt = '',
    String? modelProfileId,
  }) async {
    return DemoAgent(id: agentId, name: name, icon: Icons.person);
  }

  @override
  Future<bool> deleteAgent(String agentId) async {
    return agentId != sdk.NapaxiEngine.defaultAgentId;
  }

  @override
  Future<List<sdk.AgentProviderDescriptor>> discoverAgentProviders() async {
    return const [];
  }

  @override
  Future<List<sdk.NapaxiChannelProviderManifest>> listChannelProviders() async {
    final qqCredentials =
        channelCredentials[sdk.QqBotChannelProvider.channelName];
    final headsetCredentials =
        channelCredentials[sdk.BluetoothHeadsetChannelProvider.channelName];
    return [
      sdk.QqBotChannelProvider.manifestFor(
        qqCredentials == null
            ? null
            : DemoQqChannelCredentials.fromChannelCredentials(qqCredentials),
      ),
      sdk.BluetoothHeadsetChannelProvider.manifestFor(
        headsetCredentials == null
            ? null
            : DemoBluetoothHeadsetChannelCredentials.fromChannelCredentials(
                headsetCredentials,
              ),
      ),
    ];
  }

  @override
  Future<List<DemoChannelStatus>> listChannelStatuses() async {
    return [
      await channelStatus(sdk.QqBotChannelProvider.channelName),
      await channelStatus(sdk.BluetoothHeadsetChannelProvider.channelName),
    ];
  }

  @override
  Future<List<DemoChannelInputSource>> listChannelInputSources({
    required String agentId,
  }) async {
    final status = await channelStatus(
      sdk.BluetoothHeadsetChannelProvider.channelName,
    );
    if (!status.configured ||
        !status.connected ||
        !_fakeChannelStatusBelongsToAgent(status, agentId)) {
      return const [];
    }
    return [DemoChannelInputSource.fromBluetoothHeadset(status)];
  }

  @override
  Future<DemoChannelCredentials?> loadChannelCredentials(
    String channelName, {
    String? accountId,
  }) async {
    return channelCredentials[_normalizeFakeChannelName(channelName)];
  }

  @override
  Future<void> saveChannelCredentials(
    DemoChannelCredentials credentials,
  ) async {
    channelCredentials[_normalizeFakeChannelName(credentials.channelName)] =
        credentials;
  }

  @override
  Future<void> clearChannelCredentials(
    String channelName, {
    String? accountId,
  }) async {
    channelCredentials.remove(_normalizeFakeChannelName(channelName));
  }

  @override
  Future<DemoChannelStatus> channelStatus(
    String channelName, {
    String? accountId,
  }) async {
    final normalized = _normalizeFakeChannelName(channelName);
    final credentials = channelCredentials[normalized];
    if (normalized == sdk.BluetoothHeadsetChannelProvider.channelName) {
      final headsetCredentials = credentials == null
          ? null
          : DemoBluetoothHeadsetChannelCredentials.fromChannelCredentials(
              credentials,
            );
      return DemoChannelStatus(
        connected: headsetCredentials?.isConfigured ?? false,
        configured: headsetCredentials?.isConfigured ?? false,
        manifest: sdk.BluetoothHeadsetChannelProvider.manifestFor(
          headsetCredentials,
        ),
        mode: 'bluetooth_headset_host_audio',
        deviceId: headsetCredentials?.deviceId,
        deviceName: headsetCredentials?.deviceName,
      );
    }
    final qqCredentials = credentials == null
        ? null
        : DemoQqChannelCredentials.fromChannelCredentials(credentials);
    return DemoChannelStatus(
      connected: false,
      configured: qqCredentials?.isConfigured ?? false,
      manifest: sdk.QqBotChannelProvider.manifestFor(qqCredentials),
      mode: 'qqbot_gateway_openapi',
    );
  }

  @override
  Future<DemoChannelStatus> connectChannel(
    String channelName, {
    String? accountId,
  }) async {
    return channelStatus(channelName, accountId: accountId);
  }

  @override
  Future<DemoHeadsetTranscriptResult> submitHeadsetTranscript({
    required String text,
  }) async {
    final status = await channelStatus(
      sdk.BluetoothHeadsetChannelProvider.channelName,
    );
    return DemoHeadsetTranscriptResult(
      accepted: text.trim().isNotEmpty && status.configured,
      status: status.copyWith(lastTranscript: text.trim()),
      inboundId: 'fake-headset-inbound',
      transcript: text.trim(),
      error: text.trim().isEmpty ? 'empty transcript' : null,
    );
  }

  @override
  Future<DemoHeadsetTranscriptResult> captureHeadsetTranscript({
    String? accountId,
    String? agentId,
  }) async {
    final status = await channelStatus(
      sdk.BluetoothHeadsetChannelProvider.channelName,
      accountId: accountId,
    );
    if (agentId != null && !_fakeChannelStatusBelongsToAgent(status, agentId)) {
      return DemoHeadsetTranscriptResult(
        accepted: false,
        status: status,
        error: 'Bluetooth device channel is bound to another agent.',
      );
    }
    const transcript = 'fake headset transcript';
    return DemoHeadsetTranscriptResult(
      accepted: status.connected,
      status: status.copyWith(lastTranscript: transcript),
      inboundId: status.connected ? 'fake-headset-inbound' : null,
      transcript: status.connected ? transcript : null,
      error: status.connected ? null : 'Bluetooth device channel is offline.',
    );
  }

  @override
  Future<List<DemoChannelStatus>> ensureConfiguredChannelsConnected() async {
    ensureConfiguredChannelsCount += 1;
    final status = await channelStatus(sdk.QqBotChannelProvider.channelName);
    final headsetStatus = await channelStatus(
      sdk.BluetoothHeadsetChannelProvider.channelName,
    );
    return [
      if (status.configured) status,
      if (headsetStatus.configured) headsetStatus,
    ];
  }

  String _normalizeFakeChannelName(String channelName) {
    final normalized = channelName.trim().toLowerCase();
    if (normalized == 'qq' || normalized == 'qqbot') {
      return sdk.QqBotChannelProvider.channelName;
    }
    if (normalized == 'headset' ||
        normalized == 'bluetooth' ||
        normalized == 'bluetooth_headset' ||
        normalized == 'bt_headset') {
      return sdk.BluetoothHeadsetChannelProvider.channelName;
    }
    return normalized;
  }

  bool _fakeChannelStatusBelongsToAgent(
    DemoChannelStatus status,
    String agentId,
  ) {
    final expected = agentId.trim().isEmpty
        ? sdk.NapaxiEngine.defaultAgentId
        : agentId.trim();
    final actual =
        status.manifest.config['agent_id']?.toString().trim() ??
        sdk.NapaxiEngine.defaultAgentId;
    return (actual.isEmpty ? sdk.NapaxiEngine.defaultAgentId : actual) ==
        expected;
  }

  @override
  Future<DemoAgent> installAgentProvider(
    sdk.AgentProviderDescriptor provider,
  ) async {
    return DemoAgent(
      id: provider.packageName,
      name: provider.label.isEmpty ? provider.packageName : provider.label,
      icon: Icons.sensors_rounded,
    );
  }

  @override
  Future<DemoAgent?> installPendingAgentProvider() async {
    return null;
  }

  @override
  Future<sdk.AcceptedAgentTrigger?> consumePendingAgentTrigger() async {
    return null;
  }

  @override
  Future<sdk.SessionKey> createSession({
    required String threadId,
    required String agentId,
  }) async {
    return sdk.SessionKey(
      channelType: 'app',
      accountId: 'test_user',
      threadId: createdThreadIds[threadId] ?? threadId,
    );
  }

  @override
  Stream<sdk.ChatEvent> sendToSession(
    sdk.SessionKey session,
    String message, {
    required String agentId,
    List<sdk.McAttachment>? attachments,
    int maxIterations = 0,
    void Function(String nativeThreadId)? onNativeThreadId,
  }) {
    lastMaxIterations = maxIterations;
    sentThreadIds.add(session.threadId);
    sentMessages.add(message);
    final threadStream = eventStreamsByThreadId[session.threadId];
    if (threadStream != null) {
      return threadStream;
    }
    final configuredStream = eventStream;
    if (configuredStream != null) {
      return configuredStream;
    }
    final configuredEvents = events;
    if (configuredEvents != null) {
      return Stream.fromIterable(configuredEvents);
    }
    return Stream.value(
      sdk.ResponseEvent(
        content: 'Fake SDK reply from ${configuredProfile?.model}: $message',
      ),
    );
  }

  Future<String?> importAttachmentToWorkspace(
    ChatAttachment attachment, {
    String? name,
    bool temporary = false,
  }) async {
    return null;
  }

  @override
  Future<bool> cancelSession(
    sdk.SessionKey session, {
    required String agentId,
  }) async {
    canceledSession = session;
    canceledAgentId = agentId;
    cancelCount += 1;
    return true;
  }

  @override
  Future<bool> deleteSession(
    sdk.SessionKey session, {
    required String agentId,
  }) async {
    deletedSession = session;
    deletedAgentId = agentId;
    deleteCount += 1;
    return true;
  }

  @override
  Future<bool> injectMessage(
    sdk.SessionKey session,
    String message, {
    required String agentId,
    List<sdk.McAttachment>? attachments,
  }) async {
    injectedSession = session;
    injectedMessage = message;
    injectedAgentId = agentId;
    return true;
  }

  @override
  Future<bool> retractInjectedMessage(
    sdk.SessionKey session,
    String message,
  ) async {
    retractedSession = session;
    retractedMessage = message;
    retractCount += 1;
    return true;
  }

  @override
  Future<bool> answerHumanRequest(String requestId, String response) async {
    answeredHumanRequestId = requestId;
    answeredHumanResponse = response;
    return true;
  }

  @override
  Future<List<Map<String, dynamic>>> listPendingEvolution() async {
    return pendingEvolution;
  }

  @override
  Future<Map<String, dynamic>> applyPendingEvolution(String pendingId) async {
    appliedPendingEvolutionId = pendingId;
    pendingEvolution.removeWhere((item) => item['id'] == pendingId);
    return {'success': true};
  }

  @override
  Future<Map<String, dynamic>> rejectPendingEvolution(String pendingId) async {
    rejectedPendingEvolutionId = pendingId;
    pendingEvolution.removeWhere((item) => item['id'] == pendingId);
    return {'success': true, 'status': 'rejected'};
  }

  @override
  Future<List<sdk.EvolutionRun>> listEvolutionRuns({
    List<String>? runIds,
  }) async {
    if (runIds == null || runIds.isEmpty) return evolutionRuns;
    final ids = runIds.toSet();
    return evolutionRuns.where((run) => ids.contains(run.id)).toList();
  }

  @override
  Future<bool> requestBackgroundPermission() async {
    backgroundPermissionRequestCount += 1;
    return backgroundPermissionGranted;
  }

  @override
  Stream<sdk.BackgroundActionEvent> get onBackgroundAction =>
      backgroundActions.stream;

  @override
  Stream<DemoChannelBridgeEvent> get onChannelBridgeEvent =>
      channelBridgeEvents.stream;

  @override
  Future<void> stopBackgroundService() async {
    stopBackgroundServiceCount += 1;
  }

  @override
  Future<List<sdk.SessionInfo>> listSessions({required String agentId}) async {
    lastListSessionsAgentId = agentId;
    return sessions;
  }

  @override
  Future<List<sdk.ChatMessage>> getHistory(
    String threadId, {
    required String agentId,
  }) async {
    historyRequestCount += 1;
    return historyByThreadId[threadId] ?? const [];
  }

  @override
  Future<sdk.HistoryPage> getHistoryPage(
    String threadId, {
    required String agentId,
    String? before,
    int limit = 80,
  }) async {
    historyPageRequests.add(
      FakeHistoryPageRequest(
        threadId: threadId,
        agentId: agentId,
        before: before,
        limit: limit,
      ),
    );
    final history = historyByThreadId[threadId] ?? const [];
    final beforeDate = before == null ? null : DateTime.tryParse(before);
    final eligible = beforeDate == null
        ? [...history]
        : history.where((message) {
            final createdAt = message.createdAt;
            if (createdAt == null) return false;
            final date = DateTime.tryParse(createdAt);
            return date != null && date.isBefore(beforeDate);
          }).toList();
    eligible.sort((a, b) => (a.createdAt ?? '').compareTo(b.createdAt ?? ''));
    final boundedLimit = limit.clamp(1, 200);
    final hasMore = eligible.length > boundedLimit;
    final start = eligible.length - boundedLimit;
    final messages = eligible.sublist(start < 0 ? 0 : start);
    return sdk.HistoryPage(
      messages: messages,
      hasMore: hasMore,
      nextBefore: hasMore ? messages.first.createdAt : null,
    );
  }

  @override
  Future<sdk.ContextStatus> contextStatus(
    String threadId, {
    required String agentId,
  }) async {
    contextStatusRequestCount += 1;
    return contextStatusByThreadId[threadId] ?? _emptyContextStatus(threadId);
  }

  @override
  Future<sdk.ContextStatus> compactContext(
    sdk.SessionKey session, {
    required String agentId,
    String? focus,
  }) async {
    return contextStatusByThreadId[session.threadId] ??
        _emptyContextStatus(session.threadId);
  }

  sdk.ContextStatus _emptyContextStatus(String threadId) {
    return sdk.ContextStatus(
      threadId: threadId,
      engine: 'compressor',
      summaryPresent: false,
      compactionCount: 0,
      tokensBefore: 0,
      tokensAfter: 0,
      estimatedTokens: 0,
      contextWindowTokens: 128000,
      triggerTokens: 108800,
      targetTokens: 57600,
      responseReserveTokens: 4096,
      usagePercent: 0,
      triggerRatio: 0.85,
      targetRatio: 0.45,
    );
  }

  @override
  Future<List<sdk.WorkspaceEntry>> listMemoryFiles(
    String directory, {
    required String agentId,
  }) async {
    return memoryFilesByDirectory[directory] ?? const [];
  }

  @override
  Future<sdk.WorkspaceFile?> readMemoryFile(
    String path, {
    required String agentId,
  }) async {
    return memoryFilesByPath[path];
  }

  @override
  Future<List<sdk.JournalDay>> listJournalDays({
    required String agentId,
  }) async {
    return journalDays;
  }

  @override
  Future<List<sdk.JournalTurnRecord>> readJournalDay(
    String date, {
    required String agentId,
  }) async {
    return journalRecordsByDate[date] ?? const [];
  }

  @override
  Future<List<sdk.MemoryRecallSession>> recallSessions(
    String query, {
    required String agentId,
  }) async {
    return const [];
  }

  @override
  Future<sdk.RecallIndexStats> rebuildRecallIndex({
    required String agentId,
  }) async {
    return const sdk.RecallIndexStats(status: 'ready', dbPath: '');
  }

  @override
  Future<sdk.RecallIndexStats> recallIndexStats({
    required String agentId,
  }) async {
    return const sdk.RecallIndexStats(status: 'ready', dbPath: '');
  }

  @override
  Future<bool> deleteMemoryFile(String path, {required String agentId}) async {
    return true;
  }

  @override
  Future<List<sdk.WorkspaceFileInfo>> listSandboxWorkspaceFiles({
    required String agentId,
    String? subdir,
    bool recursive = true,
  }) async {
    return workspaceFiles;
  }

  @override
  Future<void> deleteSandboxWorkspaceFile(
    String sandboxPath, {
    required String agentId,
  }) async {
    deletedSandboxWorkspacePaths.add(sandboxPath);
  }

  @override
  Future<List<DemoRepositoryInfo>> listGitRepositories() async {
    return gitRepositories;
  }

  void setGitRepositories(List<DemoRepositoryInfo> repositories) {
    gitRepositories
      ..clear()
      ..addAll(repositories);
  }

  @override
  Future<DemoGitRepositoryStatus> gitRepositoryStatus(String directory) async {
    return gitStatuses[directory] ??
        const DemoGitRepositoryStatus(
          success: true,
          branch: '',
          changedFiles: [],
        );
  }

  @override
  Future<List<DemoGitBranchInfo>> listGitBranches(String directory) async {
    return gitBranches[directory] ?? const [];
  }

  @override
  Future<DemoGitOperationResult> switchGitBranch(
    String directory,
    String branch, {
    bool remote = false,
    bool allowDirty = false,
  }) async {
    switchedGitDirectory = directory;
    switchedGitBranch = branch;
    switchedGitBranchWasRemote = remote;
    switchedGitBranchAllowedDirty = allowDirty;
    return DemoGitOperationResult(
      success: true,
      message: 'Switched to $branch',
      branch: branch,
    );
  }

  @override
  Future<List<DemoGitRemoteInfo>> listGitRemotes(String directory) async {
    return gitRemotes[directory] ?? const [];
  }

  @override
  Future<DemoGitOperationResult> setGitRemote(
    String directory, {
    required String name,
    required String url,
  }) async {
    setGitRemoteDirectory = directory;
    setGitRemoteName = name;
    setGitRemoteUrl = url;
    return DemoGitOperationResult(
      success: true,
      message: 'Updated remote $name',
    );
  }

  @override
  Future<DemoGitOperationResult> removeGitRemote(
    String directory, {
    required String name,
  }) async {
    removedGitRemoteDirectory = directory;
    removedGitRemoteName = name;
    return DemoGitOperationResult(
      success: true,
      message: 'Removed remote $name',
    );
  }

  @override
  Future<DemoGitOperationResult> fetchGitRemote(
    String directory, {
    String? remote,
  }) async {
    fetchedGitDirectory = directory;
    fetchedGitRemote = remote;
    return const DemoGitOperationResult(
      success: true,
      message: 'Fetched remotes',
    );
  }

  @override
  Future<DemoGitOperationResult> pushGitRemote(
    String directory, {
    String? remote,
  }) async {
    pushedGitDirectory = directory;
    pushedGitRemote = remote;
    return const DemoGitOperationResult(
      success: true,
      message: 'Pushed to upstream',
    );
  }

  @override
  Future<DemoGitOperationResult> pullGitRemote(
    String directory, {
    String? remote,
  }) async {
    pulledGitDirectory = directory;
    pulledGitRemote = remote;
    return const DemoGitOperationResult(
      success: true,
      message: 'Pulled from upstream',
    );
  }

  @override
  Future<DemoGitChangeSet> gitChanges(String directory) async {
    gitChangesRequests.add(directory);
    return gitChangesSets[directory] ??
        const DemoGitChangeSet(success: true, branch: '');
  }

  @override
  Future<DemoGitFileDiff> gitFileDiff(
    String directory,
    String path, {
    bool cached = false,
  }) async {
    return gitFileDiffs['$directory:$path:${cached ? 1 : 0}'] ??
        gitFileDiffs['$directory:$path'] ??
        const DemoGitFileDiff(success: true, empty: true);
  }

  @override
  Future<List<DemoGitCommitInfo>> listGitCommitHistory(String directory) async {
    return gitCommitHistory[directory] ?? const [];
  }

  @override
  Future<DemoGitCommitDiff> gitCommitDiff(String directory, String hash) async {
    return gitCommitDiffs['$directory:$hash'] ??
        const DemoGitCommitDiff(success: true);
  }

  @override
  Future<DemoGitOperationResult> stageGitPaths(
    String directory,
    List<String> paths,
  ) async {
    stagedGitPaths.addAll(paths);
    return DemoGitOperationResult(
      success: true,
      message: paths.isEmpty ? 'staged all changes' : 'changes staged',
    );
  }

  @override
  Future<DemoGitOperationResult> unstageGitPaths(
    String directory,
    List<String> paths,
  ) async {
    unstagedGitPaths.addAll(paths);
    return DemoGitOperationResult(
      success: true,
      message: paths.isEmpty ? 'unstaged all changes' : 'changes unstaged',
    );
  }

  @override
  Future<DemoGitOperationResult> discardGitPaths(
    String directory,
    List<String> paths,
  ) async {
    discardedGitPaths.addAll(paths);
    return const DemoGitOperationResult(
      success: true,
      message: 'changes discarded',
    );
  }

  @override
  Future<DemoGitOperationResult> commitGit(
    String directory,
    String message,
  ) async {
    commitMessages.add(message);
    return const DemoGitOperationResult(
      success: true,
      message: 'commit created',
      branch: 'main',
    );
  }

  @override
  Future<List<DemoRepositoryFileItem>> listGitRepositoryChildren(
    String directory, {
    String subdir = '',
    String query = '',
    int limit = 200,
  }) async {
    gitRepositoryChildrenRequests.add(
      FakeGitRepositoryChildrenRequest(
        directory: directory,
        subdir: subdir,
        query: query,
        limit: limit,
      ),
    );
    return gitRepositoryChildren['$directory:$subdir:$query'] ??
        gitRepositoryChildren['$directory:$subdir'] ??
        gitRepositoryChildren[directory] ??
        const [];
  }

  @override
  List<sdk.ResolvedFile> detectProducedFiles(
    String text, {
    required String agentId,
  }) {
    detectedFileTexts.add(text);
    return [
      for (final file in detectedFiles)
        if (text.contains(file.sandboxPath)) file,
    ];
  }

  @override
  Future<List<sdk.NapaxiScenarioPack>> listScenarioPacks() async {
    return scenarioPacks;
  }

  @override
  Future<List<sdk.NapaxiScenarioStatus>> listScenarioStatuses() async {
    return scenarioStatuses;
  }

  @override
  Future<sdk.NapaxiScenarioResolution?> resolveScenario(
    String scenarioId,
  ) async {
    return scenarioResolution;
  }

  @override
  Future<sdk.NapaxiScenarioPackInstallResult?> installScenarioPack(
    sdk.NapaxiScenarioPack pack,
  ) async {
    installedScenarioId = pack.id;
    return sdk.NapaxiScenarioPackInstallResult(
      definition: pack,
      installed: true,
      replaced: false,
    );
  }

  @override
  Future<sdk.NapaxiScenarioPackRemovalResult?> removeScenarioPack(
    String scenarioId,
  ) async {
    removedScenarioId = scenarioId;
    return sdk.NapaxiScenarioPackRemovalResult(
      scenarioId: scenarioId,
      removed: true,
    );
  }

  @override
  Future<List<sdk.SkillInfo>> listSkills({required String agentId}) async {
    lastSkillAgentId = agentId;
    return skills;
  }

  @override
  Future<sdk.SkillInfo?> getSkill(
    String skillName, {
    required String agentId,
  }) async {
    lastSkillAgentId = agentId;
    viewedSkillName = skillName;
    return skills
        .where((skill) => skill.name == skillName)
        .cast<sdk.SkillInfo?>()
        .firstWhere((skill) => skill != null, orElse: () => null);
  }

  @override
  Future<sdk.SkillStatusReport> listSkillStatus({
    required String agentId,
  }) async {
    lastSkillAgentId = agentId;
    if (skillStatusReport != null) return skillStatusReport!;
    return sdk.SkillStatusReport(
      entries: [
        for (final skill in skills)
          sdk.SkillStatusEntry(
            name: skill.name,
            description: skill.description,
            trust: skill.trust,
            status: 'ready',
            eligible: true,
            lifecycle: skill.lifecycle,
          ),
      ],
      ready: skills.length,
    );
  }

  @override
  Future<sdk.SkillSourceReport> listSkillSources({
    required String agentId,
  }) async {
    lastSkillAgentId = agentId;
    return const sdk.SkillSourceReport();
  }

  @override
  Future<sdk.SkillSnapshotList> listSkillSnapshots({
    required String agentId,
  }) async {
    lastSkillAgentId = agentId;
    return const sdk.SkillSnapshotList();
  }

  @override
  Future<sdk.SkillSecretRequirementReport> listSkillSecretRequirements({
    required String agentId,
    String? skillName,
  }) async {
    lastSkillAgentId = agentId;
    return const sdk.SkillSecretRequirementReport();
  }

  @override
  Future<sdk.SkillRemediationRunList> listSkillRemediationRuns({
    required String agentId,
    String? skillName,
  }) async {
    lastSkillAgentId = agentId;
    return const sdk.SkillRemediationRunList();
  }

  @override
  Future<sdk.SkillStatusReport> checkSkills({required String agentId}) {
    return listSkillStatus(agentId: agentId);
  }

  @override
  Future<sdk.SkillCommandReport> listSkillCommands({
    required String agentId,
  }) async {
    lastSkillAgentId = agentId;
    return sdk.SkillCommandReport(
      commands: [
        for (final skill in skills)
          sdk.SkillCommand(
            name: skill.name.replaceAll('-', '_'),
            skillName: skill.name,
            description: skill.description,
            eligible: true,
          ),
      ],
      total: skills.length,
    );
  }

  @override
  Future<sdk.SkillCommandResolution> resolveSkillCommand(
    String text, {
    required String agentId,
  }) async {
    final commands = await listSkillCommands(agentId: agentId);
    final commandName = text
        .trim()
        .split(RegExp(r'\s+'))
        .first
        .replaceFirst('/', '');
    final command = commands.commands
        .where(
          (candidate) =>
              candidate.name == commandName ||
              candidate.skillName == commandName,
        )
        .cast<sdk.SkillCommand?>()
        .firstWhere((candidate) => candidate != null, orElse: () => null);
    return sdk.SkillCommandResolution(
      matched: command != null,
      command: command,
      args: text.trim().contains(' ')
          ? text.trim().substring(text.trim().indexOf(' ') + 1)
          : null,
    );
  }

  @override
  Future<sdk.SkillCommandRun> runSkillCommand(
    String commandName, {
    required String agentId,
    String? args,
    sdk.SessionKey? sessionKey,
  }) async {
    final resolution = await resolveSkillCommand(
      '/$commandName ${args ?? ''}',
      agentId: agentId,
    );
    return sdk.SkillCommandRun(
      success: resolution.matched,
      status: resolution.matched ? 'agent_turn_required' : 'not_found',
      commandName: commandName,
      skillName: resolution.command?.skillName,
      args: resolution.args,
      message: resolution.command == null
          ? null
          : '/${resolution.command!.skillName}${resolution.args == null ? '' : ' ${resolution.args}'}',
    );
  }

  @override
  Future<String> setSkillEnabled(
    String skillName, {
    required String agentId,
    required bool enabled,
  }) async {
    lastSkillAgentId = agentId;
    toggledSkillName = skillName;
    toggledSkillEnabled = enabled;
    return '{"success":true}';
  }

  @override
  Future<String> updateSkillConfig(
    String skillKey,
    Map<String, dynamic> patch, {
    required String agentId,
  }) async {
    lastSkillAgentId = agentId;
    updatedSkillConfigKey = skillKey;
    updatedSkillConfigPatch = patch;
    return '{"success":true}';
  }

  @override
  Future<String> recordSkillRequirementResolution(
    String skillName,
    String actionId,
    Map<String, dynamic> result, {
    required String agentId,
  }) async {
    lastSkillAgentId = agentId;
    return '{"success":true}';
  }

  @override
  Future<sdk.SkillRemediationRun> requestSkillRemediation(
    String skillName,
    String actionId, {
    required String agentId,
  }) async {
    lastSkillAgentId = agentId;
    requestedRemediationSkillName = skillName;
    requestedRemediationActionId = actionId;
    return sdk.SkillRemediationRun(
      runId: 'run-1',
      agentId: agentId,
      skillName: skillName,
      actionId: actionId,
      status: 'requested',
    );
  }

  @override
  Future<List<sdk.SkillUsageRecord>> listSkillUsage({
    required String agentId,
  }) async {
    lastSkillAgentId = agentId;
    return skillUsage;
  }

  @override
  Future<List<String>> reloadSkills({required String agentId}) async {
    lastSkillAgentId = agentId;
    skillReloadCount += 1;
    return skills.map((skill) => skill.name).toList();
  }

  @override
  Future<bool> removeSkill(String skillName, {required String agentId}) async {
    removedSkillName = skillName;
    removedSkillAgentId = agentId;
    return true;
  }

  @override
  Future<String> pinSkill(
    String skillName, {
    required String agentId,
    required bool pinned,
  }) async {
    pinnedSkillName = skillName;
    pinnedSkillValue = pinned;
    return '{"success":true}';
  }

  @override
  Future<String> archiveSkill(
    String skillName, {
    required String agentId,
  }) async {
    archivedSkillName = skillName;
    return '{"success":true}';
  }

  @override
  Future<String> restoreSkill(
    String skillName, {
    required String agentId,
  }) async {
    restoredSkillName = skillName;
    return '{"success":true}';
  }

  @override
  Future<sdk.CuratorRunSummary> runSkillCurator({
    required String agentId,
    bool dryRun = true,
  }) async {
    lastCuratorDryRun = dryRun;
    return sdk.CuratorRunSummary(
      dryRun: dryRun,
      checked: skillUsage.length,
      actions: dryRun ? const ['mark stale demo-skill'] : const [],
    );
  }

  @override
  Future<sdk.SkillConsolidationReviewResult> runSkillConsolidationReview({
    required String agentId,
    bool dryRun = true,
  }) async {
    lastConsolidationDryRun = dryRun;
    return sdk.SkillConsolidationReviewResult(
      reviewed: true,
      dryRun: dryRun,
      suggestionsCount: dryRun ? 0 : 1,
      pendingCount: dryRun ? 0 : 1,
      pendingId: dryRun ? null : 'pending-1',
    );
  }

  @override
  Future<sdk.SkillSupportFileReadResult> readSkillSupportFile(
    String skillName,
    String filePath, {
    required String agentId,
  }) async {
    lastSkillAgentId = agentId;
    readSupportSkillName = skillName;
    readSupportFilePath = filePath;
    final key = '$skillName/$filePath';
    final content = skillSupportFiles[key] ?? skillSupportFiles[filePath];
    if (content == null) {
      return sdk.SkillSupportFileReadResult(
        success: false,
        skillName: skillName,
        filePath: filePath,
        error: 'not found',
      );
    }
    return sdk.SkillSupportFileReadResult(
      success: true,
      skillName: skillName,
      filePath: filePath,
      content: content,
    );
  }

  @override
  Future<sdk.CatalogSearchResult> listCatalogPackages({
    int limit = 50,
    String? cursor,
  }) async {
    return sdk.CatalogSearchResult(results: catalogPackages);
  }

  @override
  Future<sdk.CatalogSearchResult> searchCatalog(String query) async {
    return sdk.CatalogSearchResult(results: catalogResults);
  }

  @override
  Future<sdk.SkillInstallResult> installFromCatalog(
    String slug, {
    required String agentId,
  }) async {
    installedCatalogSlug = slug;
    installedCatalogAgentId = agentId;
    final installedName = _resolveCatalogSkillName(slug);
    final alreadyInstalled = skills.any(
      (skill) => skill.name.toLowerCase() == installedName.toLowerCase(),
    );
    if (!alreadyInstalled) {
      skills = [...skills, sdk.SkillInfo(name: installedName)];
    }
    return sdk.SkillInstallResult(name: installedName, success: true);
  }

  String _resolveCatalogSkillName(String slug) {
    for (final entry in [...catalogPackages, ...catalogResults]) {
      if (entry.slug == slug) {
        return entry.name.isNotEmpty ? entry.name : entry.slug;
      }
    }
    return 'research';
  }

  @override
  Stream<sdk.A2ALocalTransportEvent> get localA2AEvents =>
      a2aLocalEvents.stream;

  @override
  Future<bool> handleLocalA2ABlobFrame(sdk.A2ALocalTransportEvent event) async {
    return false;
  }

  @override
  Future<sdk.A2ALocalTransportStatus> localA2AStatus() async {
    return const sdk.A2ALocalTransportStatus(
      supported: false,
      running: false,
      transport: 'lan_tcp_jsonl',
      reason: 'fake_client',
    );
  }

  @override
  Future<bool> checkLocalA2APermission() async {
    return true;
  }

  @override
  Future<bool> requestLocalA2APermission() async {
    return true;
  }

  sdk.A2AApi get _fakeA2AApi => sdk.A2AApi(() => 0);

  @override
  String generateLocalA2APairingSecret() {
    return _fakeA2AApi.generateLocalPairingSecret();
  }

  @override
  String normalizeLocalA2APairingSecret(String value) {
    return _fakeA2AApi.normalizePairingSecret(value);
  }

  @override
  String formatLocalA2APairingSecret(String value) {
    return _fakeA2AApi.formatPairingSecret(value);
  }

  @override
  String localA2APairingKey(sdk.A2ALocalPeerAdvertisement peer) {
    return _fakeA2AApi.pairingKey(peer);
  }

  @override
  String localA2APairingCode(String peerId, String publicKey) {
    return _fakeA2AApi.pairingCodeFromIdentity(peerId, publicKey);
  }

  @override
  String deriveLocalA2ASharedSecret({
    required String localPeerId,
    required String localPublicKey,
    required String localPairingSecret,
    required sdk.A2ALocalPeerAdvertisement peer,
    required String remotePairingSecret,
  }) {
    return _fakeA2AApi.deriveLocalSharedSecret(
      localPeerId: localPeerId,
      localPublicKey: localPublicKey,
      localPairingSecret: localPairingSecret,
      peer: peer,
      remotePairingSecret: remotePairingSecret,
    );
  }

  @override
  Future<sdk.A2ALocalTransportStatus> startLocalA2A({
    required String agentId,
    required String displayName,
    String publicKey = '',
  }) async {
    return const sdk.A2ALocalTransportStatus(
      supported: false,
      running: false,
      transport: 'lan_tcp_jsonl',
      reason: 'fake_client',
    );
  }

  @override
  Future<sdk.A2ALocalTransportStatus> stopLocalA2A() async {
    return const sdk.A2ALocalTransportStatus(
      supported: false,
      running: false,
      transport: 'lan_tcp_jsonl',
      reason: 'fake_client',
    );
  }

  @override
  Future<List<sdk.A2ALocalPeerAdvertisement>> discoverLocalA2APeers({
    int timeoutMs = 5000,
  }) async {
    return const [];
  }

  @override
  Future<sdk.A2APeerSession> openLocalA2ASession(
    sdk.A2ALocalPeerAdvertisement peer, {
    String sharedSecret = '',
  }) async {
    return sdk.A2APeerSession(
      sessionId: 'fake-a2a-session',
      localPeerId: 'local',
      remotePeerId: peer.peerId,
      status: 'active',
      transport: peer.transport,
      endpoint: peer.endpoint,
      createdAt: '2026-06-03T00:00:00Z',
      updatedAt: '2026-06-03T00:00:00Z',
    );
  }

  @override
  Future<List<sdk.A2APeer>> listLocalA2APeers({String agentId = ''}) async {
    return const [];
  }

  @override
  Future<bool> deleteLocalA2APeer(String peerId) async {
    return true;
  }

  @override
  Future<sdk.A2APeerMessage> createLocalA2ATaskMessage(
    String sessionId,
    String message, {
    Map<String, dynamic> options = const {},
  }) async {
    return sdk.A2APeerMessage(
      messageId: 'fake-a2a-message',
      sessionId: sessionId,
      fromPeerId: 'local',
      toPeerId: 'remote',
      kind: 'task_request',
      createdAt: '2026-06-03T00:00:00Z',
      expiresAt: '2026-06-03T00:30:00Z',
      nonce: 'nonce',
      idempotencyKey: 'idem',
      payload: {
        'task': {'message': message},
      },
    );
  }

  @override
  Future<sdk.A2APeerMessage> createLocalA2AProgressMessage(
    String sessionId,
    String taskId,
    String message, {
    String? status,
  }) async {
    return sdk.A2APeerMessage(
      messageId: 'fake-a2a-progress',
      sessionId: sessionId,
      fromPeerId: 'local',
      toPeerId: 'remote',
      kind: 'task_progress',
      createdAt: '2026-06-03T00:00:00Z',
      expiresAt: '2026-06-03T00:30:00Z',
      nonce: 'nonce-progress',
      idempotencyKey: 'idem-progress',
      payload: {
        'progress': status == null
            ? {'taskId': taskId, 'message': message}
            : {'taskId': taskId, 'message': message, 'status': status},
      },
    );
  }

  @override
  Future<sdk.A2APeerMessage> createLocalA2AResultMessage(
    String sessionId,
    String taskId,
    String message, {
    String? status,
  }) async {
    return sdk.A2APeerMessage(
      messageId: 'fake-a2a-result',
      sessionId: sessionId,
      fromPeerId: 'local',
      toPeerId: 'remote',
      kind: 'task_result',
      createdAt: '2026-06-03T00:00:00Z',
      expiresAt: '2026-06-03T00:30:00Z',
      nonce: 'nonce-result',
      idempotencyKey: 'idem-result',
      payload: {
        'result': {'taskId': taskId, 'message': message, 'status': ?status},
      },
    );
  }

  @override
  Future<sdk.A2APeerMessage> createLocalA2ADiagnosticMessage({
    required String localPeerId,
  }) async {
    return sdk.A2APeerMessage(
      messageId: 'fake-a2a-diagnostic',
      sessionId: 'diagnostic:$localPeerId',
      fromPeerId: localPeerId,
      toPeerId: localPeerId,
      kind: 'ping',
      createdAt: '2026-06-03T00:00:00Z',
      expiresAt: '2026-06-03T00:05:00Z',
      nonce: 'nonce-diagnostic',
      idempotencyKey: 'idem-diagnostic',
      payload: const {'purpose': 'local_a2a_loopback'},
    );
  }

  @override
  Future<bool> sendLocalA2AMessage(
    sdk.A2APeerMessage message, {
    required String endpoint,
  }) async {
    localA2AMessages.add(message);
    localA2ADeliveries.add(
      sdk.A2ADeliveryRecord(
        messageId: message.messageId,
        sessionId: message.sessionId,
        direction: 'outbound',
        kind: message.kind,
        status: 'sent',
        createdAt: '2026-06-03T00:00:00Z',
        updatedAt: '2026-06-03T00:00:00Z',
      ),
    );
    if (message.payload['purpose'] == 'local_a2a_loopback') {
      a2aLocalEvents.add(
        sdk.A2ALocalTransportEvent(
          action: 'a2aLocalPeerMessage',
          message: message,
          messageJson: message.toJsonString(),
          payload: {'endpoint': endpoint, 'source': 'fake_loopback'},
        ),
      );
    }
    return true;
  }

  @override
  Future<bool> sendLocalA2ADiagnosticMessage(
    sdk.A2APeerMessage message, {
    required String endpoint,
  }) async {
    a2aLocalEvents.add(
      sdk.A2ALocalTransportEvent(
        action: 'a2aLocalPeerMessage',
        message: message,
        messageJson: message.toJsonString(),
        payload: {'endpoint': endpoint, 'source': 'fake_loopback'},
      ),
    );
    return true;
  }

  @override
  Future<sdk.A2ADeliveryRecord> recordLocalA2AMessage(
    sdk.A2APeerMessage message, {
    String source = 'local_transport_require_trusted',
  }) async {
    localA2AMessages.add(message);
    final record = sdk.A2ADeliveryRecord(
      messageId: message.messageId,
      sessionId: message.sessionId,
      direction: 'inbound',
      kind: message.kind,
      status: 'delivered',
      createdAt: '2026-06-03T00:00:00Z',
      updatedAt: '2026-06-03T00:00:00Z',
      taskId: _fakeA2ATaskId(message),
    );
    localA2ADeliveries.add(record);
    return record;
  }

  @override
  Future<List<sdk.A2APeerMessage>> listLocalA2APeerMessages(
    String sessionId, {
    int limit = 100,
    int offset = 0,
  }) async {
    return localA2AMessages
        .where((message) => message.sessionId == sessionId)
        .skip(offset)
        .take(limit)
        .toList(growable: false);
  }

  @override
  Future<List<sdk.A2ADeliveryRecord>> listLocalA2ADeliveryRecords(
    String sessionId, {
    int limit = 100,
    int offset = 0,
  }) async {
    return localA2ADeliveries
        .where((delivery) => delivery.sessionId == sessionId)
        .skip(offset)
        .take(limit)
        .toList(growable: false);
  }

  @override
  Future<sdk.A2ATaskRecord> runLocalA2ATask(String taskId) async {
    return _fakeA2ATaskRecord(
      taskId: taskId,
      status: 'succeeded',
      summary: 'fake A2A task summary',
      sessionKey: 'fake-a2a-session-key',
      runId: 'fake-a2a-run-id',
    );
  }

  @override
  Future<sdk.A2ATaskRecord?> getLocalA2ATask(String taskId) async {
    return _fakeA2ATaskRecord(
      taskId: taskId,
      status: 'succeeded',
      summary: 'fake A2A task summary',
      sessionKey: 'fake-a2a-session-key',
      runId: 'fake-a2a-run-id',
    );
  }

  @override
  Future<DemoLocalA2AChannelReceipt> submitLocalA2AChannelTask({
    required sdk.A2ATaskRecord task,
    required sdk.A2ALocalPeerAdvertisement peer,
  }) async {
    submittedLocalA2AChannelTaskId = task.taskId;
    submittedLocalA2AChannelPeerId = peer.peerId;
    return DemoLocalA2AChannelReceipt(
      taskId: task.taskId,
      inboundId: 'fake-local-a2a-inbound-${task.taskId}',
    );
  }

  @override
  Future<DemoLocalA2AChannelRun> runLocalA2AChannelTask({
    required String taskId,
    required String agentId,
  }) async {
    ranLocalA2AChannelTaskId = taskId;
    ranLocalA2AChannelAgentId = agentId;
    return DemoLocalA2AChannelRun(
      taskId: taskId,
      delivered: true,
      phase: 'idle',
      summary: 'fake A2A task summary',
    );
  }

  @override
  bool claimLocalA2AAutoRunTask(String taskId) => true;

  @override
  void releaseLocalA2AAutoRunTask(String taskId, {bool handled = true}) {}

  @override
  Future<List<sdk.A2ATaskRecord>> listLocalA2ATasks({int limit = 50}) async {
    return const [];
  }

  @override
  Future<List<sdk.A2AArtifact>> resolveLocalA2AArtifacts(
    List<sdk.A2AArtifact> artifacts,
  ) async {
    return artifacts;
  }

  sdk.A2ATaskRecord _fakeA2ATaskRecord({
    required String taskId,
    String status = 'pending_user_confirmation',
    String summary = '',
    String? sessionKey,
    String? runId,
  }) {
    return sdk.A2ATaskRecord(
      taskId: taskId,
      envelopeId: 'fake-envelope-$taskId',
      idempotencyKey: 'fake-idem-$taskId',
      agentId: 'default',
      sender: const sdk.A2AParty(agentId: 'remote', peerId: 'remote'),
      request: sdk.A2ATaskRequest(taskId: taskId, message: 'fake task'),
      status: status,
      trust: 'signed_peer',
      source: 'local_transport_require_trusted',
      createdAt: '2026-06-03T00:00:00Z',
      updatedAt: '2026-06-03T00:01:00Z',
      sessionId: 'fake-a2a-session',
      sessionKey: sessionKey,
      runId: runId,
      summary: summary.isEmpty ? null : summary,
    );
  }

  String? _fakeA2ATaskId(sdk.A2APeerMessage message) {
    final task = message.payload['task'];
    if (task is Map) return task['taskId']?.toString();
    final progress = message.payload['progress'];
    if (progress is Map) return progress['taskId']?.toString();
    final result = message.payload['result'];
    if (result is Map) return result['taskId']?.toString();
    return null;
  }

  @override
  void dispose() {
    backgroundActions.close();
    channelBridgeEvents.close();
    a2aLocalEvents.close();
  }
}

class FakeDemoUpdateService implements DemoUpdateService {
  FakeDemoUpdateService({
    this.version = const DemoAppVersion(version: '0.0.13', buildNumber: '13'),
    this.update,
    this.noUpdateMessage,
    this.supportsUpdateCheck = true,
  });

  DemoAppVersion version;
  DemoUpdateInfo? update;
  String? noUpdateMessage;
  @override
  final bool supportsUpdateCheck;
  String? skippedIdentity;
  var checkCount = 0;
  var skipCount = 0;
  var installCount = 0;
  var openPageCount = 0;
  final respectSkippedValues = <bool>[];

  @override
  Future<DemoAppVersion> currentVersion() async => version;

  @override
  Future<DemoUpdateCheckResult> checkForUpdate({
    required bool respectSkippedVersion,
  }) async {
    checkCount += 1;
    respectSkippedValues.add(respectSkippedVersion);
    final currentUpdate = update;
    if (currentUpdate == null) {
      return DemoUpdateCheckResult(
        currentVersion: version,
        message: noUpdateMessage,
      );
    }
    if (respectSkippedVersion &&
        !currentUpdate.needForceUpdate &&
        skippedIdentity == currentUpdate.identity) {
      return DemoUpdateCheckResult(
        currentVersion: version,
        update: currentUpdate,
        skipped: true,
      );
    }
    return DemoUpdateCheckResult(
      currentVersion: version,
      update: currentUpdate,
    );
  }

  @override
  Future<void> skipUpdate(DemoUpdateInfo update) async {
    skipCount += 1;
    skippedIdentity = update.identity;
  }

  @override
  Future<DemoUpdateInstallResult> downloadAndInstall(
    DemoUpdateInfo update, {
    void Function(int receivedBytes, int? totalBytes)? onProgress,
  }) async {
    installCount += 1;
    onProgress?.call(100, 100);
    return const DemoUpdateInstallResult(success: true, installerOpened: true);
  }

  @override
  Future<bool> openInstallPage(DemoUpdateInfo update) async {
    openPageCount += 1;
    return true;
  }
}

const demoUpdate = DemoUpdateInfo(
  buildKey: 'build-6',
  buildVersion: '0.0.6',
  buildVersionNo: '6',
  buildBuildVersion: 6,
  needForceUpdate: false,
  downloadUrl: 'https://example.com/app.apk',
  appUrl: 'https://www.pgyer.com/demo',
  updateDescription: 'Bug fixes and polish.',
  fileSizeBytes: 12345678,
);

class FakeDemoFeedbackService implements DemoFeedbackService {
  DemoFeedbackRequest? submittedRequest;
  AppStrings? submittedStrings;
  DemoFeedbackResult result = const DemoFeedbackResult(success: true);

  @override
  Future<DemoFeedbackResult> submit(
    DemoFeedbackRequest request,
    AppStrings strings,
  ) async {
    submittedRequest = request;
    submittedStrings = strings;
    return result;
  }
}

Future<Finder> revealByKey(WidgetTester tester, Key key) async {
  final finder = find.byKey(key);
  if (finder.evaluate().isNotEmpty) {
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    return finder;
  }

  final profileForm = find.byKey(const Key('model_profile_form'));
  final configList = find.byKey(const Key('config_page_list'));
  final scrollTarget = profileForm.evaluate().isNotEmpty
      ? profileForm
      : configList.evaluate().isNotEmpty
      ? configList
      : find.byType(ListView).last;

  for (final offset in const [Offset(0, -320), Offset(0, 320)]) {
    for (var i = 0; i < 10 && finder.evaluate().isEmpty; i++) {
      await tester.drag(scrollTarget, offset, warnIfMissed: false);
      await tester.pumpAndSettle();
    }
    if (finder.evaluate().isNotEmpty) break;
  }

  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  return finder;
}

Future<void> enterVisibleText(WidgetTester tester, Key key, String text) async {
  final finder = await revealByKey(tester, key);
  await tester.enterText(finder, text);
}

Future<void> selectCustomProvider(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('provider_preset_field')));
  await tester.pumpAndSettle();
  // The "Custom" provider option is localized ("Custom" / "自定义").
  final custom = find.text('Custom').evaluate().isNotEmpty
      ? find.text('Custom')
      : find.text('自定义');
  await tester.tap(custom.last);
  await tester.pumpAndSettle();
}

Future<void> tapVisible(WidgetTester tester, Key key) async {
  final finder = await revealByKey(tester, key);
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> pumpUntilFound(
  WidgetTester tester,
  Finder finder, {
  int maxPumps = 20,
}) async {
  for (var i = 0; i < maxPumps; i++) {
    if (finder.evaluate().isNotEmpty) return;
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Future<void> configureSingleModel(
  WidgetTester tester, {
  String name = 'Primary',
  String provider = 'openai',
  String model = 'napaxi-model',
  String apiKey = 'sk-napaxi',
}) async {
  await openModelConfiguration(tester);
  await tester.tap(find.byKey(const Key('add_model_button')));
  await tester.pumpAndSettle();
  await enterVisibleText(tester, const Key('model_name_field'), name);
  await selectCustomProvider(tester);
  await enterVisibleText(tester, const Key('provider_field'), provider);
  await enterVisibleText(tester, const Key('model_field'), model);
  await enterVisibleText(tester, const Key('api_key_field'), apiKey);
  await tester.tap(find.byKey(const Key('save_model_button')));
  await tester.pumpAndSettle();
  await closeSettingsSheet(tester);
}

/// Opens the LLM model configuration surface.
///
/// The demo moved LLM configuration from a top-bar `llm_settings_button` into
/// the side-menu Settings page (`settings_menu_button`). This helper performs
/// that navigation so callers reach the same model-editing surface as before.
Future<void> openModelConfiguration(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('session_history_button')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('settings_menu_button')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('settings_basic_item')));
  await tester.pumpAndSettle();
}

/// Closes the side-menu Settings page and the inline side sheet, returning to
/// chat.
Future<void> closeSettingsSheet(WidgetTester tester) async {
  // Settings now nests: an editor/basic page sits under the Settings list page,
  // which itself sits under the side-menu root. Pop pages until the side-menu
  // root (identified by `session_title_header`) is reached.
  final header = find.byKey(const ValueKey('session_title_header'));
  for (var i = 0; i < 4 && header.evaluate().isEmpty; i++) {
    await tester.pageBack();
    await tester.pumpAndSettle();
  }
  // The side-menu root is a full-width inline sheet with no back affordance; the
  // app dismisses it with a left swipe, so fling the header past the threshold.
  await tester.fling(header, const Offset(-400, 0), 1200);
  await tester.pumpAndSettle();
}

/// Opens the About surface.
///
/// About moved from a standalone side-menu item (`about_menu_button`) into the
/// side-menu Settings page. This helper opens the side menu, enters Settings,
/// and selects About from the settings list.
Future<void> openAbout(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('session_history_button')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('settings_menu_button')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('settings_about_item')));
  await tester.pumpAndSettle();
}
