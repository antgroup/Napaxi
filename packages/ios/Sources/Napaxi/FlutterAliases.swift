import Foundation

// Flutter SDK migration aliases. These keep the Swift-native Napaxi-prefixed
// names as the canonical API while exposing familiar Flutter public symbols.


public typealias ToolApi = NapaxiToolAPI
public typealias ChatApi = NapaxiChatAPI
public typealias CapabilityApi = NapaxiCapabilityAPI
public typealias AutomationApi = NapaxiAutomationAPI
public typealias A2AApi = NapaxiA2AAPI
public typealias A2APairing = NapaxiA2APairing
public typealias SessionRunApi = NapaxiSessionRunAPI
public typealias AgentAppApi = NapaxiAgentAppAPI
public typealias AgentApi = NapaxiAgentAPI
public typealias SessionApi = NapaxiSessionAPI
public typealias SkillApi = NapaxiSkillAPI
public typealias EvolutionApi = NapaxiEvolutionAPI
public typealias GroupApi = NapaxiGroupAPI
public typealias WorkspaceApi = NapaxiWorkspaceAPI
public typealias BackgroundApi = NapaxiBackgroundAPI
public typealias McpApi = NapaxiMcpAPI


public typealias McAttachment = NapaxiAttachment
public typealias SessionKey = NapaxiSessionKey
public typealias SessionRunStatus = NapaxiSessionRunStatus
public typealias SessionRunInfo = NapaxiSessionRunInfo
public typealias ChatEvent = NapaxiChatEvent
public typealias RunStartedEvent = NapaxiChatEvent
public typealias RunProgressEvent = NapaxiChatEvent
public typealias RunCompletedEvent = NapaxiChatEvent
public typealias ToolCallEvent = NapaxiChatEvent
public typealias ToolCallDeltaEvent = NapaxiChatEvent
public typealias ToolResultEvent = NapaxiChatEvent
public typealias ResponseEvent = NapaxiChatEvent
public typealias ResponseDeltaEvent = NapaxiChatEvent
public typealias ReasoningDeltaEvent = NapaxiChatEvent
public typealias ThinkingEvent = NapaxiChatEvent
public typealias ErrorEvent = NapaxiChatEvent
public typealias AgentDelegationEvent = NapaxiChatEvent
public typealias AgentDelegationResultEvent = NapaxiChatEvent
public typealias AgentToolCallEvent = NapaxiChatEvent
public typealias AgentToolCallDeltaEvent = NapaxiChatEvent
public typealias AgentToolResultEvent = NapaxiChatEvent
public typealias GroupDelegationEvent = NapaxiChatEvent
public typealias GroupDelegationResultEvent = NapaxiChatEvent
public typealias ImageGeneratedEvent = NapaxiChatEvent
public typealias ToolOutputChunkEvent = NapaxiChatEvent
public typealias MessageInjectedEvent = NapaxiChatEvent
public typealias AskingHumanEvent = NapaxiChatEvent
public typealias HumanResponseEvent = NapaxiChatEvent
public typealias ContextCompactingEvent = NapaxiChatEvent
public typealias ContextCompactedEvent = NapaxiChatEvent
public typealias MemoryEvolvedEvent = NapaxiChatEvent
public typealias SkillEvolvedEvent = NapaxiChatEvent
public typealias EvolutionQueuedEvent = NapaxiChatEvent
public typealias SkillActivatedEvent = NapaxiChatEvent
public typealias ActionProposalCreatedEvent = NapaxiChatEvent
public typealias ActionHandoffStartedEvent = NapaxiChatEvent
public typealias ActionWaitingForProviderEvent = NapaxiChatEvent
public typealias ActionResultReceivedEvent = NapaxiChatEvent
public typealias ActionExpiredEvent = NapaxiChatEvent
public typealias ActionFailedEvent = NapaxiChatEvent
public typealias InterruptedEvent = NapaxiChatEvent
public typealias StreamResetEvent = NapaxiChatEvent
public typealias EvolutionQueuedRun = NapaxiEvolutionQueuedRun
public typealias ActivatedSkillInfo = NapaxiActivatedSkillInfo


public typealias BackgroundConfig = NapaxiBackgroundConfig
public typealias NotificationConfig = NapaxiNotificationConfig
public typealias BackgroundAction = NapaxiBackgroundAction
public typealias BackgroundActionEvent = NapaxiBackgroundActionEvent

public typealias AgentHandle = NapaxiAgentHandle
public typealias AgentDefinition = NapaxiAgentDefinition
public typealias ToolFilter = NapaxiToolFilter
public typealias ToolInfo = NapaxiToolInfo

public typealias SessionInfo = NapaxiSessionInfo
public typealias HistoryPage = NapaxiHistoryPage
public typealias ContextStatus = NapaxiContextStatus
public typealias ContextTokenBreakdown = NapaxiContextTokenBreakdown
public typealias ContextBudgetStatus = NapaxiContextBudgetStatus
public typealias ChatAttachment = NapaxiChatAttachment
public typealias ToolCallInfo = NapaxiToolCallInfo
public typealias ChatMessage = NapaxiChatMessage

public typealias AutomationTrigger = NapaxiAutomationTrigger
public typealias AutomationPayload = NapaxiAutomationPayload
public typealias AutomationPolicy = NapaxiAutomationPolicy
public typealias AutomationJobState = NapaxiAutomationJobState
public typealias AutomationJob = NapaxiAutomationJob
public typealias AutomationRun = NapaxiAutomationRun
public typealias AutomationWake = NapaxiAutomationWake

public typealias A2AAgentCard = NapaxiA2AAgentCard
public typealias A2AParty = NapaxiA2AParty
public typealias A2ADeepLinkEnvelope = NapaxiA2ADeepLinkEnvelope
public typealias A2ATaskRequest = NapaxiA2ATaskRequest
public typealias A2AArtifact = NapaxiA2AArtifact
public typealias A2ACallback = NapaxiA2ACallback
public typealias A2ATaskResult = NapaxiA2ATaskResult
public typealias A2APeer = NapaxiA2APeer
public typealias A2ATaskRecord = NapaxiA2ATaskRecord
public typealias A2APeerInvite = NapaxiA2APeerInvite
public typealias A2AResultLink = NapaxiA2AResultLink
public typealias A2APeerEndpoint = NapaxiA2APeerEndpoint
public typealias A2APeerSession = NapaxiA2APeerSession
public typealias A2APeerMessage = NapaxiA2APeerMessage
public typealias A2ADeliveryRecord = NapaxiA2ADeliveryRecord
public typealias A2ALocalTransportStatus = NapaxiA2ALocalTransportStatus
public typealias A2ALocalPeerAdvertisement = NapaxiA2ALocalPeerAdvertisement
public typealias A2ALocalTransportEvent = NapaxiA2ALocalTransportEvent

public typealias CustomToolDef = NapaxiCustomToolDefinition
public typealias McToolApprovalRequest = NapaxiHostToolApprovalRequest
public typealias McToolApprovalResponse = NapaxiHostToolApprovalResponse
public typealias McToolApprovalHandler = @Sendable (McToolApprovalRequest) async -> McToolApprovalResponse

public typealias EvolutionRunStatus = NapaxiEvolutionRunStatus
public typealias EvolutionRun = NapaxiEvolutionRun
public typealias EvolutionDiagnostic = NapaxiEvolutionDiagnostic
public typealias SkillConsolidationReviewResult = NapaxiSkillConsolidationReviewResult

public typealias ResolvedFile = NapaxiResolvedFile
public typealias WorkspaceFileInfo = NapaxiWorkspaceFileInfo
public typealias WorkspaceFile = NapaxiWorkspaceFile
public typealias WorkspaceEntry = NapaxiWorkspaceEntry
public typealias MemorySearchResult = NapaxiMemorySearchResult
public typealias MemoryRecallSnippet = NapaxiMemoryRecallSnippet
public typealias MemoryRecallSession = NapaxiMemoryRecallSession
public typealias RecallIndexStats = NapaxiRecallIndexStats
public typealias JournalDay = NapaxiJournalDay
public typealias JournalTurnRecord = NapaxiJournalTurnRecord
public typealias WorkspacePaths = NapaxiWorkspacePaths
public typealias NapaxiFileBridge = NapaxiFileBridgeAPI

public typealias GroupInfo = NapaxiGroupInfo
public typealias GroupMessage = NapaxiGroupMessage
public typealias GroupMessageType = NapaxiGroupMessageType

public typealias AgentAppActionManifest = NapaxiAgentAppActionManifest
public typealias AgentAppPackage = NapaxiAgentAppPackage
public typealias AgentAppInstallBinding = NapaxiAgentAppInstallBinding
public typealias AgentAppActionProposal = NapaxiAgentAppActionProposal
public typealias AgentAppActionResult = NapaxiAgentAppActionResult
public typealias AgentAppActionRecord = NapaxiAgentAppActionRecord
public typealias AgentAppActionRequest = NapaxiAgentAppActionRequest
public typealias AgentInstallResult = NapaxiAgentInstallResult

public typealias SkillInfo = NapaxiSkillInfo
public typealias SkillLifecycleSummary = NapaxiSkillLifecycleSummary
public typealias SkillStatusReport = NapaxiSkillStatusReport
public typealias SkillStatusEntry = NapaxiSkillStatusEntry
public typealias SkillProvenance = NapaxiSkillProvenance
public typealias SkillRemediationAction = NapaxiSkillRemediationAction
public typealias SkillRequirementSummary = NapaxiSkillRequirementSummary
public typealias SkillOpenClawMetadata = NapaxiSkillOpenClawMetadata
public typealias SkillCommandReport = NapaxiSkillCommandReport
public typealias SkillSourceReport = NapaxiSkillSourceReport
public typealias SkillSourceEntry = NapaxiSkillSourceEntry
public typealias SkillRefreshResult = NapaxiSkillRefreshResult
public typealias SkillCommand = NapaxiSkillCommand
public typealias SkillCommandDispatch = NapaxiSkillCommandDispatch
public typealias SkillCommandResolution = NapaxiSkillCommandResolution
public typealias SkillCommandRun = NapaxiSkillCommandRun
public typealias SkillSnapshotList = NapaxiSkillSnapshotList
public typealias SkillSnapshotIndexEntry = NapaxiSkillSnapshotIndexEntry
public typealias SkillSnapshot = NapaxiSkillSnapshot
public typealias SkillSnapshotCatalogEntry = NapaxiSkillSnapshotCatalogEntry
public typealias SkillSecretRequirementReport = NapaxiSkillSecretRequirementReport
public typealias SkillSecretRequirement = NapaxiSkillSecretRequirement
public typealias SkillRemediationRunList = NapaxiSkillRemediationRunList
public typealias SkillRemediationRun = NapaxiSkillRemediationRun
public typealias SkillUsageRecord = NapaxiSkillUsageRecord
public typealias CuratorRunSummary = NapaxiCuratorRunSummary
public typealias SkillSupportFileReadResult = NapaxiSkillSupportFileReadResult
public typealias SkillInstallInput = NapaxiSkillInstallInput
public typealias SkillInstallExtraFile = NapaxiSkillInstallExtraFile
public typealias SkillInstallResult = NapaxiSkillInstallResult
public typealias CatalogSearchResult = NapaxiCatalogSearchResult
public typealias CatalogPackagePage = NapaxiCatalogPackagePage
public typealias CatalogSkillInfo = NapaxiCatalogSkillInfo

public typealias SessionRunRecordStatus = NapaxiSessionRunRecordStatus
public typealias RunEvidenceKind = NapaxiRunEvidenceKind
public typealias RunVerification = NapaxiRunVerification
public typealias RunEvidence = NapaxiRunEvidence
public typealias SessionRunRecord = NapaxiSessionRunRecord

public typealias McpConnectionState = NapaxiMcpConnectionState
public typealias McpServerInfo = NapaxiMcpServerInfo
public typealias McpToolInfo = NapaxiMcpToolInfo
public typealias McpServerActionResult = NapaxiMcpServerActionResult
public typealias McpOAuthStartResult = NapaxiMcpOAuthStartResult

public typealias AgentProviderDescriptor = NapaxiAgentProviderDescriptor
public typealias AgentInstallRequest = NapaxiAgentInstallRequest
public typealias AgentTriggerRequest = NapaxiAgentTriggerRequest
public typealias AcceptedAgentTrigger = NapaxiAcceptedAgentTrigger
public typealias AndroidAgentProviderActionExecutor = NapaxiAgentProviderActionExecutor
