import Foundation

public struct NapaxiStableModel<Tag>: Codable, Equatable, Sendable {
    public var raw: [String: NapaxiJSONValue]

    public init(raw: [String: NapaxiJSONValue] = [:]) {
        self.raw = raw
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        raw = try container.decode([String: NapaxiJSONValue].self)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(raw)
    }

    public subscript(key: String) -> NapaxiJSONValue? {
        get { raw[key] }
        set { raw[key] = newValue }
    }

    public func string(_ key: String) -> String? {
        raw[key]?.stringValue
    }

    public func bool(_ key: String) -> Bool? {
        raw[key]?.boolValue
    }

    public func number(_ key: String) -> Double? {
        raw[key]?.numberValue
    }
}

public struct NapaxiStableString<Tag>: Codable, Equatable, Hashable, Sendable, RawRepresentable, ExpressibleByStringLiteral {
    public var rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(stringLiteral value: String) {
        self.rawValue = value
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        rawValue = try container.decode(String.self)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

public enum NapaxiAgentHandleTag {}
public enum NapaxiAgentDefinitionTag {}
public enum NapaxiSessionInfoTag {}
public enum NapaxiHistoryPageTag {}
public enum NapaxiContextStatusTag {}
public enum NapaxiContextTokenBreakdownTag {}
public enum NapaxiContextBudgetStatusTag {}
public enum NapaxiToolCallInfoTag {}
public enum NapaxiChatMessageTag {}
public enum NapaxiSessionRunRecordTag {}
public enum NapaxiRunEvidenceTag {}
public enum NapaxiAutomationTriggerTag {}
public enum NapaxiAutomationPayloadTag {}
public enum NapaxiAutomationPolicyTag {}
public enum NapaxiAutomationJobStateTag {}
public enum NapaxiAutomationJobTag {}
public enum NapaxiAutomationRunTag {}
public enum NapaxiAutomationWakeTag {}
public enum NapaxiCustomToolDefTag {}
public enum NapaxiToolApprovalRequestTag {}
public enum NapaxiToolApprovalResponseTag {}
public enum NapaxiEvolutionRunTag {}
public enum NapaxiEvolutionDiagnosticTag {}
public enum NapaxiSkillConsolidationReviewResultTag {}
public enum NapaxiBackgroundConfigTag {}
public enum NapaxiNotificationConfigTag {}
public enum NapaxiBackgroundActionEventTag {}
public enum NapaxiWorkspaceFileTag {}
public enum NapaxiWorkspaceEntryTag {}
public enum NapaxiMemorySearchResultTag {}
public enum NapaxiMemoryRecallSnippetTag {}
public enum NapaxiMemoryRecallSessionTag {}
public enum NapaxiRecallIndexStatsTag {}
public enum NapaxiJournalDayTag {}
public enum NapaxiJournalTurnRecordTag {}
public enum NapaxiWorkspacePathsTag {}
public enum NapaxiGroupInfoTag {}
public enum NapaxiGroupMessageTag {}
public enum NapaxiAgentAppActionManifestTag {}
public enum NapaxiAgentAppPackageTag {}
public enum NapaxiAgentAppInstallBindingTag {}
public enum NapaxiAgentAppActionProposalTag {}
public enum NapaxiAgentAppActionResultTag {}
public enum NapaxiAgentAppActionRecordTag {}
public enum NapaxiAgentAppActionRequestTag {}
public enum NapaxiAgentInstallResultTag {}
public enum NapaxiSkillInfoTag {}
public enum NapaxiSkillLifecycleSummaryTag {}
public enum NapaxiSkillStatusReportTag {}
public enum NapaxiSkillStatusEntryTag {}
public enum NapaxiSkillRequirementSummaryTag {}
public enum NapaxiSkillOpenClawMetadataTag {}
public enum NapaxiSkillProvenanceTag {}
public enum NapaxiSkillRemediationActionTag {}
public enum NapaxiSkillCommandReportTag {}
public enum NapaxiSkillSourceReportTag {}
public enum NapaxiSkillSourceEntryTag {}
public enum NapaxiSkillRefreshResultTag {}
public enum NapaxiSkillCommandTag {}
public enum NapaxiSkillCommandDispatchTag {}
public enum NapaxiSkillCommandResolutionTag {}
public enum NapaxiSkillCommandRunTag {}
public enum NapaxiSkillSnapshotListTag {}
public enum NapaxiSkillSnapshotIndexEntryTag {}
public enum NapaxiSkillSnapshotTag {}
public enum NapaxiSkillSnapshotCatalogEntryTag {}
public enum NapaxiSkillSecretRequirementReportTag {}
public enum NapaxiSkillSecretRequirementTag {}
public enum NapaxiSkillRemediationRunListTag {}
public enum NapaxiSkillRemediationRunTag {}
public enum NapaxiSkillUsageRecordTag {}
public enum NapaxiCuratorRunSummaryTag {}
public enum NapaxiSkillSupportFileReadResultTag {}
public enum NapaxiSkillInstallInputTag {}
public enum NapaxiSkillInstallExtraFileTag {}
public enum NapaxiSkillInstallResultTag {}
public enum NapaxiCatalogSearchResultTag {}
public enum NapaxiCatalogPackagePageTag {}
public enum NapaxiCatalogSkillInfoTag {}
public enum NapaxiToolInfoTag {}
public enum NapaxiMcpServerInfoTag {}
public enum NapaxiMcpToolInfoTag {}
public enum NapaxiMcpServerActionResultTag {}
public enum NapaxiMcpOAuthStartResultTag {}
public enum NapaxiApkInstallResultTag {}
public enum NapaxiScenePromptConfigTag {}
public enum NapaxiContextEngineConfigTag {}
public enum NapaxiShellSecurityConfigTag {}
public enum NapaxiLlmCapabilityConfigTag {}

public typealias NapaxiAgentHandle = NapaxiStableModel<NapaxiAgentHandleTag>
public typealias NapaxiAgentDefinition = NapaxiStableModel<NapaxiAgentDefinitionTag>
public typealias NapaxiSessionRunRecord = NapaxiStableModel<NapaxiSessionRunRecordTag>
public typealias NapaxiRunEvidence = NapaxiStableModel<NapaxiRunEvidenceTag>
public typealias NapaxiCustomToolDef = NapaxiStableModel<NapaxiCustomToolDefTag>
public typealias NapaxiToolApprovalRequest = NapaxiStableModel<NapaxiToolApprovalRequestTag>
public typealias NapaxiToolApprovalResponse = NapaxiStableModel<NapaxiToolApprovalResponseTag>
public typealias NapaxiEvolutionRun = NapaxiStableModel<NapaxiEvolutionRunTag>
public typealias NapaxiEvolutionDiagnostic = NapaxiStableModel<NapaxiEvolutionDiagnosticTag>
public typealias NapaxiSkillConsolidationReviewResult = NapaxiStableModel<NapaxiSkillConsolidationReviewResultTag>
public typealias NapaxiWorkspaceFile = NapaxiStableModel<NapaxiWorkspaceFileTag>
public typealias NapaxiWorkspaceEntry = NapaxiStableModel<NapaxiWorkspaceEntryTag>
public typealias NapaxiMemorySearchResult = NapaxiStableModel<NapaxiMemorySearchResultTag>
public typealias NapaxiMemoryRecallSnippet = NapaxiStableModel<NapaxiMemoryRecallSnippetTag>
public typealias NapaxiMemoryRecallSession = NapaxiStableModel<NapaxiMemoryRecallSessionTag>
public typealias NapaxiRecallIndexStats = NapaxiStableModel<NapaxiRecallIndexStatsTag>
public typealias NapaxiJournalDay = NapaxiStableModel<NapaxiJournalDayTag>
public typealias NapaxiJournalTurnRecord = NapaxiStableModel<NapaxiJournalTurnRecordTag>
public typealias NapaxiWorkspacePaths = NapaxiStableModel<NapaxiWorkspacePathsTag>
public typealias NapaxiGroupInfo = NapaxiStableModel<NapaxiGroupInfoTag>
public typealias NapaxiGroupMessage = NapaxiStableModel<NapaxiGroupMessageTag>
public typealias NapaxiAgentAppActionManifest = NapaxiStableModel<NapaxiAgentAppActionManifestTag>
public typealias NapaxiAgentAppPackage = NapaxiStableModel<NapaxiAgentAppPackageTag>
public typealias NapaxiAgentAppInstallBinding = NapaxiStableModel<NapaxiAgentAppInstallBindingTag>
public typealias NapaxiAgentAppActionProposal = NapaxiStableModel<NapaxiAgentAppActionProposalTag>
public typealias NapaxiAgentAppActionResult = NapaxiStableModel<NapaxiAgentAppActionResultTag>
public typealias NapaxiAgentAppActionRecord = NapaxiStableModel<NapaxiAgentAppActionRecordTag>
public typealias NapaxiAgentAppActionRequest = NapaxiStableModel<NapaxiAgentAppActionRequestTag>
public typealias NapaxiAgentInstallResult = NapaxiStableModel<NapaxiAgentInstallResultTag>
public typealias NapaxiSkillInfo = NapaxiStableModel<NapaxiSkillInfoTag>
public typealias NapaxiSkillLifecycleSummary = NapaxiStableModel<NapaxiSkillLifecycleSummaryTag>
public typealias NapaxiSkillStatusReport = NapaxiStableModel<NapaxiSkillStatusReportTag>
public typealias NapaxiSkillStatusEntry = NapaxiStableModel<NapaxiSkillStatusEntryTag>
public typealias NapaxiSkillRequirementSummary = NapaxiStableModel<NapaxiSkillRequirementSummaryTag>
public typealias NapaxiSkillOpenClawMetadata = NapaxiStableModel<NapaxiSkillOpenClawMetadataTag>
public typealias NapaxiSkillProvenance = NapaxiStableModel<NapaxiSkillProvenanceTag>
public typealias NapaxiSkillRemediationAction = NapaxiStableModel<NapaxiSkillRemediationActionTag>
public typealias NapaxiSkillCommandReport = NapaxiStableModel<NapaxiSkillCommandReportTag>
public typealias NapaxiSkillSourceReport = NapaxiStableModel<NapaxiSkillSourceReportTag>
public typealias NapaxiSkillSourceEntry = NapaxiStableModel<NapaxiSkillSourceEntryTag>
public typealias NapaxiSkillRefreshResult = NapaxiStableModel<NapaxiSkillRefreshResultTag>
public typealias NapaxiSkillCommand = NapaxiStableModel<NapaxiSkillCommandTag>
public typealias NapaxiSkillCommandDispatch = NapaxiStableModel<NapaxiSkillCommandDispatchTag>
public typealias NapaxiSkillCommandResolution = NapaxiStableModel<NapaxiSkillCommandResolutionTag>
public typealias NapaxiSkillCommandRun = NapaxiStableModel<NapaxiSkillCommandRunTag>
public typealias NapaxiSkillSnapshotList = NapaxiStableModel<NapaxiSkillSnapshotListTag>
public typealias NapaxiSkillSnapshotIndexEntry = NapaxiStableModel<NapaxiSkillSnapshotIndexEntryTag>
public typealias NapaxiSkillSnapshot = NapaxiStableModel<NapaxiSkillSnapshotTag>
public typealias NapaxiSkillSnapshotCatalogEntry = NapaxiStableModel<NapaxiSkillSnapshotCatalogEntryTag>
public typealias NapaxiSkillSecretRequirementReport = NapaxiStableModel<NapaxiSkillSecretRequirementReportTag>
public typealias NapaxiSkillSecretRequirement = NapaxiStableModel<NapaxiSkillSecretRequirementTag>
public typealias NapaxiSkillRemediationRunList = NapaxiStableModel<NapaxiSkillRemediationRunListTag>
public typealias NapaxiSkillRemediationRun = NapaxiStableModel<NapaxiSkillRemediationRunTag>
public typealias NapaxiSkillUsageRecord = NapaxiStableModel<NapaxiSkillUsageRecordTag>
public typealias NapaxiCuratorRunSummary = NapaxiStableModel<NapaxiCuratorRunSummaryTag>
public typealias NapaxiSkillSupportFileReadResult = NapaxiStableModel<NapaxiSkillSupportFileReadResultTag>
public typealias NapaxiSkillInstallInput = NapaxiStableModel<NapaxiSkillInstallInputTag>
public typealias NapaxiSkillInstallExtraFile = NapaxiStableModel<NapaxiSkillInstallExtraFileTag>
public typealias NapaxiSkillInstallResult = NapaxiStableModel<NapaxiSkillInstallResultTag>
public typealias NapaxiCatalogSearchResult = NapaxiStableModel<NapaxiCatalogSearchResultTag>
public typealias NapaxiCatalogPackagePage = NapaxiStableModel<NapaxiCatalogPackagePageTag>
public typealias NapaxiCatalogSkillInfo = NapaxiStableModel<NapaxiCatalogSkillInfoTag>
public typealias NapaxiToolInfo = NapaxiStableModel<NapaxiToolInfoTag>
public typealias NapaxiMcpServerInfo = NapaxiStableModel<NapaxiMcpServerInfoTag>
public typealias NapaxiMcpToolInfo = NapaxiStableModel<NapaxiMcpToolInfoTag>
public typealias NapaxiMcpServerActionResult = NapaxiStableModel<NapaxiMcpServerActionResultTag>
public typealias NapaxiMcpOAuthStartResult = NapaxiStableModel<NapaxiMcpOAuthStartResultTag>
public typealias NapaxiScenePromptConfig = NapaxiStableModel<NapaxiScenePromptConfigTag>
public typealias NapaxiContextEngineConfig = NapaxiStableModel<NapaxiContextEngineConfigTag>
public typealias NapaxiShellSecurityConfig = NapaxiStableModel<NapaxiShellSecurityConfigTag>
public typealias NapaxiLlmCapabilityConfig = NapaxiStableModel<NapaxiLlmCapabilityConfigTag>

public enum NapaxiSessionRunRecordStatusTag {}
public enum NapaxiRunEvidenceKindTag {}
public enum NapaxiRunVerificationTag {}
public enum NapaxiEvolutionRunStatusTag {}
public enum NapaxiBackgroundActionTag {}
public enum NapaxiGroupMessageTypeTag {}
public enum NapaxiToolFilterTag {}
public enum NapaxiMcpConnectionStateTag {}

public typealias NapaxiSessionRunRecordStatus = NapaxiStableString<NapaxiSessionRunRecordStatusTag>
public typealias NapaxiRunEvidenceKind = NapaxiStableString<NapaxiRunEvidenceKindTag>
public typealias NapaxiRunVerification = NapaxiStableString<NapaxiRunVerificationTag>
public typealias NapaxiEvolutionRunStatus = NapaxiStableString<NapaxiEvolutionRunStatusTag>
public typealias NapaxiGroupMessageType = NapaxiStableString<NapaxiGroupMessageTypeTag>
public typealias NapaxiToolFilter = NapaxiStableString<NapaxiToolFilterTag>
public typealias NapaxiMcpConnectionState = NapaxiStableString<NapaxiMcpConnectionStateTag>
