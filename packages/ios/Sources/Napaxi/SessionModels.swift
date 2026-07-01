import Foundation

public extension NapaxiSessionKey {
    init(map: [String: NapaxiJSONValue]) {
        self.init(
            channelType: map.sessionString("channel_type", "channelType") ?? "app",
            accountId: map.sessionString("account_id", "accountId") ?? "",
            threadId: map.sessionString("thread_id", "threadId") ?? ""
        )
    }

    static func fromMap(_ map: [String: NapaxiJSONValue]) -> Self {
        Self(map: map)
    }

    static func fromJson(_ jsonString: String) throws -> Self {
        try fromJsonString(jsonString)
    }

    static func fromJsonString(_ jsonString: String) throws -> Self {
        Self(map: try sessionObjectMap(from: jsonString))
    }

    func toJson() throws -> String {
        try jsonString()
    }

    func toMap() -> [String: NapaxiJSONValue] {
        [
            "channel_type": .string(channelType),
            "account_id": .string(accountId),
            "thread_id": .string(threadId),
        ]
    }
}

public struct NapaxiSessionInfo: Codable, Equatable, Sendable {
    public var key: NapaxiSessionKey
    public var title: String
    public var preview: String
    public var messageCount: Int
    public var createdAt: String
    public var updatedAt: String

    public init(
        key: NapaxiSessionKey,
        title: String = "",
        preview: String = "",
        messageCount: Int = 0,
        createdAt: String = "",
        updatedAt: String = ""
    ) {
        self.key = key
        self.title = title
        self.preview = preview
        self.messageCount = messageCount
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    public init(from decoder: Decoder) throws {
        let object = try NapaxiSessionJSONObject(decoder: decoder)
        self.key = try object.decode(NapaxiSessionKey.self, "key")
            ?? NapaxiSessionKey(channelType: "app", accountId: "", threadId: object.string("thread_id", "threadId") ?? "")
        self.title = object.string("title") ?? ""
        self.preview = object.string("preview") ?? ""
        self.messageCount = object.strictInt("message_count", "messageCount") ?? 0
        self.createdAt = object.string("created_at", "createdAt") ?? ""
        self.updatedAt = object.string("updated_at", "updatedAt") ?? ""
    }

    public init(map: [String: NapaxiJSONValue]) throws {
        self = try Self.fromMap(map)
    }

    public static func fromMap(_ map: [String: NapaxiJSONValue]) throws -> Self {
        try sessionDecode(Self.self, from: map)
    }

    public static func fromJson(_ jsonString: String) throws -> Self {
        try fromJsonString(jsonString)
    }

    public static func fromJsonString(_ jsonString: String) throws -> Self {
        try fromMap(sessionObjectMap(from: jsonString))
    }
}

func validateSessionInfoObject(_ object: [String: NapaxiJSONValue]) throws {
    if case .object(let key)? = object["key"] {
        try validateSessionKeyObject(key)
    } else if let key = object["key"], key != .null {
        throw NapaxiError.invalidJSON("Expected session field 'key' to be an object")
    }
    try object.validateSessionOptionalString("title")
    try object.validateSessionOptionalString("preview")
    try object.validateSessionOptionalStrictInt("message_count")
    try object.validateSessionOptionalString("created_at")
    try object.validateSessionOptionalString("updated_at")
}

func validateSessionKeyObject(_ object: [String: NapaxiJSONValue]) throws {
    try object.validateSessionOptionalString("channel_type")
    try object.validateSessionOptionalString("account_id")
    try object.validateSessionOptionalString("thread_id")
}

public struct NapaxiHistoryPage: Codable, Equatable, Sendable {
    public var messages: [NapaxiChatMessage]
    public var hasMore: Bool
    public var nextBefore: String?

    public init(messages: [NapaxiChatMessage], hasMore: Bool, nextBefore: String? = nil) {
        self.messages = messages
        self.hasMore = hasMore
        self.nextBefore = nextBefore
    }

    enum CodingKeys: String, CodingKey {
        case messages
        case hasMore = "has_more"
        case nextBefore = "next_before"
    }

    public init(from decoder: Decoder) throws {
        let object = try NapaxiSessionJSONObject(decoder: decoder)
        self.messages = (try object.decodeArray(NapaxiChatMessage.self, "messages")) ?? []
        self.hasMore = object.bool("has_more", "hasMore") ?? false
        self.nextBefore = object.string("next_before", "nextBefore")
    }

    public init(map: [String: NapaxiJSONValue]) throws {
        self = try Self.fromMap(map)
    }

    public static func fromMap(_ map: [String: NapaxiJSONValue]) throws -> Self {
        try sessionDecode(Self.self, from: map)
    }

    public static func fromJson(_ jsonString: String) throws -> Self {
        try fromJsonString(jsonString)
    }

    public static func fromJsonString(_ jsonString: String) throws -> Self {
        try fromMap(sessionObjectMap(from: jsonString))
    }
}

func normalizedHistoryPageObject(_ object: [String: NapaxiJSONValue]) throws -> [String: NapaxiJSONValue] {
    var normalized = object
    try normalized.normalizeSessionRequiredObjectListOrEmpty("messages") { message in
        try validateChatMessageObject(message)
        return message
    }
    try normalized.validateSessionOptionalBool("has_more")
    try normalized.validateSessionOptionalString("next_before")
    return normalized
}

func validateChatMessageObject(_ object: [String: NapaxiJSONValue]) throws {
    try object.validateSessionOptionalString("role")
    try object.validateSessionOptionalString("content")
    try object.validateSessionOptionalString("id")
    try object.validateSessionOptionalString("created_at")
    try object.validateSessionOptionalArray("attachments")
    if case .array(let attachments)? = object["attachments"] {
        for attachment in attachments {
            guard case .object(let attachmentObject) = attachment else {
                throw NapaxiError.invalidJSON("Expected session field 'attachments' to contain objects")
            }
            try validateChatAttachmentObject(attachmentObject)
        }
    }
}

func validateChatAttachmentObject(_ object: [String: NapaxiJSONValue]) throws {
    try object.validateSessionOptionalString("kind")
    try object.validateSessionOptionalString("mime_type")
    try object.validateSessionOptionalString("filename")
    try object.validateSessionOptionalString("name")
    try object.validateSessionOptionalString("sandbox_path")
    try object.validateSessionOptionalString("local_path")
    try object.validateSessionOptionalString("localPath")
    try object.validateSessionOptionalString("host_path")
    try object.validateSessionOptionalString("hostPath")
    try object.validateSessionOptionalString("path")
}

public struct NapaxiContextStatus: Codable, Equatable, Sendable {
    public var threadId: String
    public var engine: String
    public var summaryPresent: Bool
    public var compactionCount: Int
    public var tokensBefore: Int
    public var tokensAfter: Int
    public var estimatedTokens: Int
    public var contextWindowTokens: Int
    public var triggerTokens: Int
    public var targetTokens: Int
    public var responseReserveTokens: Int
    public var responseReserveSource: String
    public var usagePercent: Double
    public var triggerRatio: Double
    public var targetRatio: Double
    public var lastCompactedAt: String?
    public var displayUsedTokens: Int
    public var displaySource: String
    public var lastPromptTokens: Int?
    public var preflightEstimatedTokens: Int?
    public var cacheReadTokens: Int
    public var cacheWriteTokens: Int
    public var contextWindowSource: String
    public var nativeContextWindowTokens: Int
    public var nativeContextWindowSource: String
    public var effectiveContextWindowTokens: Int
    public var effectiveContextWindowSource: String
    public var contextGuardStatus: String
    public var contextGuardReason: String
    public var contextRoute: String
    public var overflowTokens: Int
    public var breakdown: NapaxiContextTokenBreakdown?
    public var contextBudgetStatus: NapaxiContextBudgetStatus?
    public var updatedAt: String?
    public var fresh: Bool
    public var currentWindowTokens: Int
    public var transcriptEstimatedTokens: Int
    public var lastContextDeltaTokens: Int
    public var lastContextDeltaReason: String
    public var toolResultPrunedTokens: Int
    public var toolResultPrunedChars: Int
    public var contextDisplayLabel: String
    public var compactionStrategy: String
    public var lastCompactionDurationMs: Int?
    public var providerMetadataFetchedAt: String?
    public var providerMetadataStale: Bool
    public var providerMetadataError: String?
    public var adaptiveChunkCount: Int
    public var oversizedMessageCount: Int
    public var protectedTailTokens: Int
    public var overflowRetryAttemptedAt: String?
    public var overflowRetrySucceeded: Bool?
    public var overflowRetryReason: String?
    public var overflowRetryError: String?
    public var preCompactionMemoryFlushEnabled: Bool
    public var preCompactionMemoryFlushStatus: String?
    public var error: String?

    public var hasError: Bool { error?.isEmpty == false }
    public var isNearTrigger: Bool { triggerTokens > 0 && displayUsedTokens >= triggerTokens }
    public var usageFraction: Double { contextWindowTokens <= 0 ? 0 : Double(displayUsedTokens) / Double(contextWindowTokens) }
    public var isProviderBacked: Bool { displaySource == "provider" }
    public var isPreflightEstimate: Bool { displaySource == "preflight" }
    public var isLegacyEstimate: Bool { displaySource == "legacy" }
    public var isBudgetBlocked: Bool { contextGuardStatus == "blocked" }
    public var isBudgetWarning: Bool { contextGuardStatus == "warning" }

    public init(
        threadId: String,
        engine: String,
        summaryPresent: Bool,
        compactionCount: Int,
        tokensBefore: Int,
        tokensAfter: Int,
        estimatedTokens: Int,
        contextWindowTokens: Int,
        triggerTokens: Int,
        targetTokens: Int,
        responseReserveTokens: Int,
        responseReserveSource: String = "unknown",
        usagePercent: Double,
        triggerRatio: Double,
        targetRatio: Double,
        lastCompactedAt: String? = nil,
        displayUsedTokens: Int? = nil,
        displaySource: String = "legacy",
        lastPromptTokens: Int? = nil,
        preflightEstimatedTokens: Int? = nil,
        cacheReadTokens: Int = 0,
        cacheWriteTokens: Int = 0,
        contextWindowSource: String = "unknown",
        nativeContextWindowTokens: Int? = nil,
        nativeContextWindowSource: String = "unknown",
        effectiveContextWindowTokens: Int? = nil,
        effectiveContextWindowSource: String = "unknown",
        contextGuardStatus: String = "unknown",
        contextGuardReason: String = "",
        contextRoute: String = "fits",
        overflowTokens: Int = 0,
        breakdown: NapaxiContextTokenBreakdown? = nil,
        contextBudgetStatus: NapaxiContextBudgetStatus? = nil,
        updatedAt: String? = nil,
        fresh: Bool = false,
        currentWindowTokens: Int? = nil,
        transcriptEstimatedTokens: Int? = nil,
        lastContextDeltaTokens: Int = 0,
        lastContextDeltaReason: String = "stable",
        toolResultPrunedTokens: Int = 0,
        toolResultPrunedChars: Int = 0,
        contextDisplayLabel: String = "current_window",
        compactionStrategy: String = "llm_summary",
        lastCompactionDurationMs: Int? = nil,
        providerMetadataFetchedAt: String? = nil,
        providerMetadataStale: Bool = false,
        providerMetadataError: String? = nil,
        adaptiveChunkCount: Int = 0,
        oversizedMessageCount: Int = 0,
        protectedTailTokens: Int = 0,
        overflowRetryAttemptedAt: String? = nil,
        overflowRetrySucceeded: Bool? = nil,
        overflowRetryReason: String? = nil,
        overflowRetryError: String? = nil,
        preCompactionMemoryFlushEnabled: Bool = false,
        preCompactionMemoryFlushStatus: String? = nil,
        error: String? = nil
    ) {
        let display = displayUsedTokens ?? estimatedTokens
        self.threadId = threadId
        self.engine = engine
        self.summaryPresent = summaryPresent
        self.compactionCount = compactionCount
        self.tokensBefore = tokensBefore
        self.tokensAfter = tokensAfter
        self.estimatedTokens = estimatedTokens
        self.contextWindowTokens = contextWindowTokens
        self.triggerTokens = triggerTokens
        self.targetTokens = targetTokens
        self.responseReserveTokens = responseReserveTokens
        self.responseReserveSource = responseReserveSource
        self.usagePercent = usagePercent
        self.triggerRatio = triggerRatio
        self.targetRatio = targetRatio
        self.lastCompactedAt = lastCompactedAt
        self.displayUsedTokens = display
        self.displaySource = displaySource
        self.lastPromptTokens = lastPromptTokens
        self.preflightEstimatedTokens = preflightEstimatedTokens
        self.cacheReadTokens = cacheReadTokens
        self.cacheWriteTokens = cacheWriteTokens
        self.contextWindowSource = contextWindowSource
        self.nativeContextWindowTokens = nativeContextWindowTokens ?? contextWindowTokens
        self.nativeContextWindowSource = nativeContextWindowSource
        self.effectiveContextWindowTokens = effectiveContextWindowTokens ?? contextWindowTokens
        self.effectiveContextWindowSource = effectiveContextWindowSource
        self.contextGuardStatus = contextGuardStatus
        self.contextGuardReason = contextGuardReason
        self.contextRoute = contextRoute
        self.overflowTokens = overflowTokens
        self.breakdown = breakdown
        self.contextBudgetStatus = contextBudgetStatus
        self.updatedAt = updatedAt
        self.fresh = fresh
        self.currentWindowTokens = currentWindowTokens ?? display
        self.transcriptEstimatedTokens = transcriptEstimatedTokens ?? estimatedTokens
        self.lastContextDeltaTokens = lastContextDeltaTokens
        self.lastContextDeltaReason = lastContextDeltaReason
        self.toolResultPrunedTokens = toolResultPrunedTokens
        self.toolResultPrunedChars = toolResultPrunedChars
        self.contextDisplayLabel = contextDisplayLabel
        self.compactionStrategy = compactionStrategy
        self.lastCompactionDurationMs = lastCompactionDurationMs
        self.providerMetadataFetchedAt = providerMetadataFetchedAt
        self.providerMetadataStale = providerMetadataStale
        self.providerMetadataError = providerMetadataError
        self.adaptiveChunkCount = adaptiveChunkCount
        self.oversizedMessageCount = oversizedMessageCount
        self.protectedTailTokens = protectedTailTokens
        self.overflowRetryAttemptedAt = overflowRetryAttemptedAt
        self.overflowRetrySucceeded = overflowRetrySucceeded
        self.overflowRetryReason = overflowRetryReason
        self.overflowRetryError = overflowRetryError
        self.preCompactionMemoryFlushEnabled = preCompactionMemoryFlushEnabled
        self.preCompactionMemoryFlushStatus = preCompactionMemoryFlushStatus
        self.error = error
    }

    public init(from decoder: Decoder) throws {
        let object = try NapaxiSessionJSONObject(decoder: decoder)
        let estimated = object.int("estimated_tokens", "estimatedTokens") ?? 0
        let display = object.int("display_used_tokens", "displayUsedTokens") ?? estimated
        self.threadId = object.string("thread_id", "threadId") ?? ""
        self.engine = object.string("engine") ?? "compressor"
        self.summaryPresent = object.bool("summary_present", "summaryPresent") ?? false
        self.compactionCount = object.int("compaction_count", "compactionCount") ?? 0
        self.tokensBefore = object.int("tokens_before", "tokensBefore") ?? 0
        self.tokensAfter = object.int("tokens_after", "tokensAfter") ?? 0
        self.estimatedTokens = estimated
        self.contextWindowTokens = object.int("context_window_tokens", "contextWindowTokens") ?? 0
        self.triggerTokens = object.int("trigger_tokens", "triggerTokens") ?? 0
        self.targetTokens = object.int("target_tokens", "targetTokens") ?? 0
        self.responseReserveTokens = object.int("response_reserve_tokens", "responseReserveTokens") ?? 0
        self.responseReserveSource = object.string("response_reserve_source", "responseReserveSource") ?? "unknown"
        self.usagePercent = object.double("usage_percent", "usagePercent") ?? 0
        self.triggerRatio = object.double("trigger_ratio", "triggerRatio") ?? 0
        self.targetRatio = object.double("target_ratio", "targetRatio") ?? 0
        self.lastCompactedAt = object.string("last_compacted_at", "lastCompactedAt")
        self.displayUsedTokens = display
        self.displaySource = object.string("display_source", "displaySource") ?? "legacy"
        self.lastPromptTokens = object.int("last_prompt_tokens", "lastPromptTokens")
        self.preflightEstimatedTokens = object.int("preflight_estimated_tokens", "preflightEstimatedTokens")
        self.cacheReadTokens = object.int("cache_read_tokens", "cacheReadTokens") ?? 0
        self.cacheWriteTokens = object.int("cache_write_tokens", "cacheWriteTokens") ?? 0
        self.contextWindowSource = object.string("context_window_source", "contextWindowSource") ?? "unknown"
        self.nativeContextWindowTokens = object.int("native_context_window_tokens", "nativeContextWindowTokens") ?? self.contextWindowTokens
        self.nativeContextWindowSource = object.string("native_context_window_source", "nativeContextWindowSource") ?? "unknown"
        self.effectiveContextWindowTokens = object.int("effective_context_window_tokens", "effectiveContextWindowTokens") ?? self.contextWindowTokens
        self.effectiveContextWindowSource = object.string("effective_context_window_source", "effectiveContextWindowSource") ?? self.contextWindowSource
        self.providerMetadataFetchedAt = object.string("provider_metadata_fetched_at", "providerMetadataFetchedAt")
        self.providerMetadataStale = object.bool("provider_metadata_stale", "providerMetadataStale") ?? false
        self.providerMetadataError = object.string("provider_metadata_error", "providerMetadataError")
        self.contextGuardStatus = object.string("context_guard_status", "contextGuardStatus") ?? "unknown"
        self.contextGuardReason = object.string("context_guard_reason", "contextGuardReason") ?? ""
        self.contextRoute = object.string("context_route", "contextRoute")
            ?? object.object("context_budget_status", "contextBudgetStatus")?["route"]?.stringValue
            ?? "fits"
        self.overflowTokens = object.int("overflow_tokens", "overflowTokens") ?? 0
        self.breakdown = try object.decode(NapaxiContextTokenBreakdown.self, "breakdown")
        self.contextBudgetStatus = try object.decode(NapaxiContextBudgetStatus.self, "context_budget_status", "contextBudgetStatus")
        self.updatedAt = object.string("updated_at", "updatedAt")
        self.fresh = object.bool("fresh") ?? false
        self.currentWindowTokens = object.int("current_window_tokens", "currentWindowTokens") ?? display
        self.transcriptEstimatedTokens = object.int("transcript_estimated_tokens", "transcriptEstimatedTokens") ?? estimated
        self.lastContextDeltaTokens = object.int("last_context_delta_tokens", "lastContextDeltaTokens") ?? 0
        self.lastContextDeltaReason = object.string("last_context_delta_reason", "lastContextDeltaReason") ?? "stable"
        self.toolResultPrunedTokens = object.int("tool_result_pruned_tokens", "toolResultPrunedTokens") ?? 0
        self.toolResultPrunedChars = object.int("tool_result_pruned_chars", "toolResultPrunedChars") ?? 0
        self.contextDisplayLabel = object.string("context_display_label", "contextDisplayLabel") ?? "current_window"
        self.compactionStrategy = object.string("compaction_strategy", "compactionStrategy") ?? "llm_summary"
        self.lastCompactionDurationMs = object.int("last_compaction_duration_ms", "lastCompactionDurationMs")
        self.adaptiveChunkCount = object.int("adaptive_chunk_count", "adaptiveChunkCount") ?? 0
        self.oversizedMessageCount = object.int("oversized_message_count", "oversizedMessageCount") ?? 0
        self.protectedTailTokens = object.int("protected_tail_tokens", "protectedTailTokens") ?? 0
        self.overflowRetryAttemptedAt = object.string("overflow_retry_attempted_at", "overflowRetryAttemptedAt")
        self.overflowRetrySucceeded = object.bool("overflow_retry_succeeded", "overflowRetrySucceeded")
        self.overflowRetryReason = object.string("overflow_retry_reason", "overflowRetryReason")
        self.overflowRetryError = object.string("overflow_retry_error", "overflowRetryError")
        self.preCompactionMemoryFlushEnabled = object.bool("pre_compaction_memory_flush_enabled", "preCompactionMemoryFlushEnabled") ?? false
        self.preCompactionMemoryFlushStatus = object.string("pre_compaction_memory_flush_status", "preCompactionMemoryFlushStatus")
        self.error = object.string("error")
    }

    public init(map: [String: NapaxiJSONValue]) throws {
        self = try Self.fromMap(map)
    }

    public static func fromMap(_ map: [String: NapaxiJSONValue]) throws -> Self {
        try sessionDecode(Self.self, from: map)
    }

    public static func fromJson(_ jsonString: String) throws -> Self {
        try fromJsonString(jsonString)
    }

    public static func fromJsonString(_ jsonString: String) throws -> Self {
        try fromMap(sessionObjectMap(from: jsonString))
    }
}

public struct NapaxiContextTokenBreakdown: Codable, Equatable, Sendable {
    public var systemPromptTokens: Int
    public var summaryTokens: Int
    public var historyTokens: Int
    public var toolDescriptorTokens: Int
    public var toolResultTokens: Int
    public var toolCallTokens: Int
    public var attachmentTokens: Int
    public var imageTokens: Int
    public var responseReserveTokens: Int
    public var totalTokens: Int

    public init(
        systemPromptTokens: Int,
        summaryTokens: Int,
        historyTokens: Int,
        toolDescriptorTokens: Int,
        toolResultTokens: Int,
        toolCallTokens: Int,
        attachmentTokens: Int,
        imageTokens: Int,
        responseReserveTokens: Int,
        totalTokens: Int
    ) {
        self.systemPromptTokens = systemPromptTokens
        self.summaryTokens = summaryTokens
        self.historyTokens = historyTokens
        self.toolDescriptorTokens = toolDescriptorTokens
        self.toolResultTokens = toolResultTokens
        self.toolCallTokens = toolCallTokens
        self.attachmentTokens = attachmentTokens
        self.imageTokens = imageTokens
        self.responseReserveTokens = responseReserveTokens
        self.totalTokens = totalTokens
    }

    public init(from decoder: Decoder) throws {
        let object = try NapaxiSessionJSONObject(decoder: decoder)
        self.systemPromptTokens = object.int("system_prompt_tokens", "systemPromptTokens") ?? 0
        self.summaryTokens = object.int("summary_tokens", "summaryTokens") ?? 0
        self.historyTokens = object.int("history_tokens", "historyTokens") ?? 0
        self.toolDescriptorTokens = object.int("tool_descriptor_tokens", "toolDescriptorTokens") ?? 0
        self.toolResultTokens = object.int("tool_result_tokens", "toolResultTokens") ?? 0
        self.toolCallTokens = object.int("tool_call_tokens", "toolCallTokens") ?? 0
        self.attachmentTokens = object.int("attachment_tokens", "attachmentTokens") ?? 0
        self.imageTokens = object.int("image_tokens", "imageTokens") ?? 0
        self.responseReserveTokens = object.int("response_reserve_tokens", "responseReserveTokens") ?? 0
        self.totalTokens = object.int("total_tokens", "totalTokens") ?? 0
    }

    public init(map: [String: NapaxiJSONValue]) throws {
        self = try Self.fromMap(map)
    }

    public static func fromMap(_ map: [String: NapaxiJSONValue]) throws -> Self {
        try sessionDecode(Self.self, from: map)
    }

    public static func fromMapOrNull(_ map: [String: NapaxiJSONValue]?) throws -> Self? {
        guard let map else { return nil }
        return try fromMap(map)
    }
}

public struct NapaxiContextBudgetStatus: Codable, Equatable, Sendable {
    public var source: String
    public var provider: String
    public var model: String
    public var route: String
    public var shouldCompact: Bool
    public var estimatedPromptTokens: Int
    public var contextTokenBudget: Int
    public var nativeContextWindowTokens: Int
    public var nativeContextWindowSource: String
    public var effectiveContextWindowTokens: Int
    public var effectiveContextWindowSource: String
    public var responseReserveSource: String
    public var providerMetadataFetchedAt: String?
    public var providerMetadataStale: Bool
    public var providerMetadataError: String?
    public var promptBudgetBeforeReserve: Int
    public var reserveTokens: Int
    public var effectiveReserveTokens: Int
    public var remainingPromptBudgetTokens: Int
    public var overflowTokens: Int
    public var toolResultReducibleChars: Int
    public var toolResultReducibleTokens: Int
    public var contextGuardStatus: String
    public var contextGuardReason: String
    public var messageCount: Int
    public var unwindowedMessageCount: Int
    public var updatedAt: String

    public init(
        source: String,
        provider: String,
        model: String,
        route: String,
        shouldCompact: Bool,
        estimatedPromptTokens: Int,
        contextTokenBudget: Int,
        nativeContextWindowTokens: Int = 0,
        nativeContextWindowSource: String = "unknown",
        effectiveContextWindowTokens: Int = 0,
        effectiveContextWindowSource: String = "unknown",
        responseReserveSource: String = "unknown",
        providerMetadataFetchedAt: String? = nil,
        providerMetadataStale: Bool = false,
        providerMetadataError: String? = nil,
        promptBudgetBeforeReserve: Int,
        reserveTokens: Int,
        effectiveReserveTokens: Int,
        remainingPromptBudgetTokens: Int,
        overflowTokens: Int,
        toolResultReducibleChars: Int,
        toolResultReducibleTokens: Int = 0,
        contextGuardStatus: String = "unknown",
        contextGuardReason: String = "",
        messageCount: Int,
        unwindowedMessageCount: Int,
        updatedAt: String
    ) {
        self.source = source
        self.provider = provider
        self.model = model
        self.route = route
        self.shouldCompact = shouldCompact
        self.estimatedPromptTokens = estimatedPromptTokens
        self.contextTokenBudget = contextTokenBudget
        self.nativeContextWindowTokens = nativeContextWindowTokens
        self.nativeContextWindowSource = nativeContextWindowSource
        self.effectiveContextWindowTokens = effectiveContextWindowTokens
        self.effectiveContextWindowSource = effectiveContextWindowSource
        self.responseReserveSource = responseReserveSource
        self.providerMetadataFetchedAt = providerMetadataFetchedAt
        self.providerMetadataStale = providerMetadataStale
        self.providerMetadataError = providerMetadataError
        self.promptBudgetBeforeReserve = promptBudgetBeforeReserve
        self.reserveTokens = reserveTokens
        self.effectiveReserveTokens = effectiveReserveTokens
        self.remainingPromptBudgetTokens = remainingPromptBudgetTokens
        self.overflowTokens = overflowTokens
        self.toolResultReducibleChars = toolResultReducibleChars
        self.toolResultReducibleTokens = toolResultReducibleTokens
        self.contextGuardStatus = contextGuardStatus
        self.contextGuardReason = contextGuardReason
        self.messageCount = messageCount
        self.unwindowedMessageCount = unwindowedMessageCount
        self.updatedAt = updatedAt
    }

    public init(from decoder: Decoder) throws {
        let object = try NapaxiSessionJSONObject(decoder: decoder)
        self.source = object.string("source") ?? ""
        self.provider = object.string("provider") ?? ""
        self.model = object.string("model") ?? ""
        self.route = object.string("route") ?? "fits"
        self.shouldCompact = object.bool("should_compact", "shouldCompact") ?? false
        self.estimatedPromptTokens = object.int("estimated_prompt_tokens", "estimatedPromptTokens") ?? 0
        self.contextTokenBudget = object.int("context_token_budget", "contextTokenBudget") ?? 0
        self.nativeContextWindowTokens = object.int("native_context_window_tokens", "nativeContextWindowTokens") ?? self.contextTokenBudget
        self.nativeContextWindowSource = object.string("native_context_window_source", "nativeContextWindowSource") ?? "unknown"
        self.effectiveContextWindowTokens = object.int("effective_context_window_tokens", "effectiveContextWindowTokens") ?? self.contextTokenBudget
        self.effectiveContextWindowSource = object.string("effective_context_window_source", "effectiveContextWindowSource") ?? "unknown"
        self.responseReserveSource = object.string("response_reserve_source", "responseReserveSource") ?? "unknown"
        self.providerMetadataFetchedAt = object.string("provider_metadata_fetched_at", "providerMetadataFetchedAt")
        self.providerMetadataStale = object.bool("provider_metadata_stale", "providerMetadataStale") ?? false
        self.providerMetadataError = object.string("provider_metadata_error", "providerMetadataError")
        self.promptBudgetBeforeReserve = object.int("prompt_budget_before_reserve", "promptBudgetBeforeReserve") ?? 0
        self.reserveTokens = object.int("reserve_tokens", "reserveTokens") ?? 0
        self.effectiveReserveTokens = object.int("effective_reserve_tokens", "effectiveReserveTokens") ?? 0
        self.remainingPromptBudgetTokens = object.int("remaining_prompt_budget_tokens", "remainingPromptBudgetTokens") ?? 0
        self.overflowTokens = object.int("overflow_tokens", "overflowTokens") ?? 0
        self.toolResultReducibleChars = object.int("tool_result_reducible_chars", "toolResultReducibleChars") ?? 0
        self.toolResultReducibleTokens = object.int("tool_result_reducible_tokens", "toolResultReducibleTokens") ?? 0
        self.contextGuardStatus = object.string("context_guard_status", "contextGuardStatus") ?? "unknown"
        self.contextGuardReason = object.string("context_guard_reason", "contextGuardReason") ?? ""
        self.messageCount = object.int("message_count", "messageCount") ?? 0
        self.unwindowedMessageCount = object.int("unwindowed_message_count", "unwindowedMessageCount") ?? 0
        self.updatedAt = object.string("updated_at", "updatedAt") ?? ""
    }

    public init(map: [String: NapaxiJSONValue]) throws {
        self = try Self.fromMap(map)
    }

    public static func fromMap(_ map: [String: NapaxiJSONValue]) throws -> Self {
        try sessionDecode(Self.self, from: map)
    }

    public static func fromMapOrNull(_ map: [String: NapaxiJSONValue]?) throws -> Self? {
        guard let map else { return nil }
        return try fromMap(map)
    }
}

func validateContextStatusObject(_ object: [String: NapaxiJSONValue]) throws {
    try object.validateSessionOptionalString("thread_id")
    try object.validateSessionOptionalString("engine")
    try object.validateSessionOptionalBool("summary_present")
    try object.validateSessionOptionalString("response_reserve_source")
    try object.validateSessionOptionalString("last_compacted_at")
    try object.validateSessionOptionalString("display_source")
    try object.validateSessionOptionalString("context_window_source")
    try object.validateSessionOptionalString("native_context_window_source")
    try object.validateSessionOptionalString("effective_context_window_source")
    try object.validateSessionOptionalString("provider_metadata_fetched_at")
    try object.validateSessionOptionalBool("provider_metadata_stale")
    try object.validateSessionOptionalString("provider_metadata_error")
    try object.validateSessionOptionalString("context_guard_status")
    try object.validateSessionOptionalString("context_guard_reason")
    try object.validateSessionOptionalString("context_route")
    try object.validateSessionOptionalString("updated_at")
    try object.validateSessionOptionalBool("fresh")
    try object.validateSessionOptionalString("last_context_delta_reason")
    try object.validateSessionOptionalString("context_display_label")
    try object.validateSessionOptionalString("compaction_strategy")
    try object.validateSessionOptionalString("overflow_retry_attempted_at")
    try object.validateSessionOptionalBool("overflow_retry_succeeded")
    try object.validateSessionOptionalString("overflow_retry_reason")
    try object.validateSessionOptionalString("overflow_retry_error")
    try object.validateSessionOptionalBool("pre_compaction_memory_flush_enabled")
    try object.validateSessionOptionalString("pre_compaction_memory_flush_status")
    try object.validateSessionOptionalString("error")
    if case .object(let budget)? = object["context_budget_status"] {
        try validateContextBudgetStatusObject(budget)
    }
}

func validateContextBudgetStatusObject(_ object: [String: NapaxiJSONValue]) throws {
    try object.validateSessionOptionalString("source")
    try object.validateSessionOptionalString("provider")
    try object.validateSessionOptionalString("model")
    try object.validateSessionOptionalString("route")
    try object.validateSessionOptionalBool("should_compact")
    try object.validateSessionOptionalString("native_context_window_source")
    try object.validateSessionOptionalString("effective_context_window_source")
    try object.validateSessionOptionalString("response_reserve_source")
    try object.validateSessionOptionalString("provider_metadata_fetched_at")
    try object.validateSessionOptionalBool("provider_metadata_stale")
    try object.validateSessionOptionalString("provider_metadata_error")
    try object.validateSessionOptionalString("context_guard_status")
    try object.validateSessionOptionalString("context_guard_reason")
    try object.validateSessionOptionalString("updated_at")
}

public struct NapaxiChatAttachment: Codable, Equatable, Sendable {
    public var kind: String
    public var mimeType: String
    public var filename: String?
    public var sandboxPath: String?
    public var localPath: String?

    public init(
        kind: String,
        mimeType: String,
        filename: String? = nil,
        sandboxPath: String? = nil,
        localPath: String? = nil
    ) {
        self.kind = kind
        self.mimeType = mimeType
        self.filename = filename
        self.sandboxPath = sandboxPath
        self.localPath = localPath
    }

    public init(from decoder: Decoder) throws {
        let object = try NapaxiSessionJSONObject(decoder: decoder)
        let rawPath = object.string("path")
        self.kind = object.string("kind") ?? ""
        self.mimeType = object.string("mime_type", "mimeType") ?? ""
        self.filename = object.string("filename", "name")
        self.sandboxPath = object.string("sandbox_path", "sandboxPath")
            ?? (rawPath?.napaxiIsSandboxPath == true ? rawPath : nil)
        self.localPath = object.string("local_path", "localPath", "host_path", "hostPath")
            ?? (rawPath?.napaxiIsSandboxPath == false ? rawPath : nil)
    }

    public func encode(to encoder: Encoder) throws {
        try jsonValue().encode(to: encoder)
    }

    public func jsonValue() -> NapaxiJSONValue {
        var object: [String: NapaxiJSONValue] = [
            "kind": .string(kind),
            "mime_type": .string(mimeType),
        ]
        if let filename {
            object["filename"] = .string(filename)
        }
        if let sandboxPath {
            object["sandbox_path"] = .string(sandboxPath)
        }
        if let localPath {
            object["path"] = .string(localPath)
        }
        return .object(object)
    }

    public init(map: [String: NapaxiJSONValue]) throws {
        self = try Self.fromMap(map)
    }

    public static func fromMap(_ map: [String: NapaxiJSONValue]) throws -> Self {
        try sessionDecode(Self.self, from: map)
    }

    public func toMap() -> [String: NapaxiJSONValue] {
        guard case .object(let object) = jsonValue() else { return [:] }
        return object
    }

    public static func jsonString(for attachments: [NapaxiChatAttachment]) throws -> String {
        try NapaxiRawJSON(.array(attachments.map { $0.jsonValue() })).jsonString()
    }
}

public struct NapaxiToolCallInfo: Codable, Equatable, Sendable {
    public var name: String
    public var callId: String
    public var arguments: [String: NapaxiJSONValue]?
    public var result: String?
    public var error: String?
    public var rationale: String?
    public var interrupted: Bool
    public var resultTruncated: Bool
    public var errorTruncated: Bool
    public var argumentsTruncated: Bool

    public init(
        name: String,
        callId: String,
        arguments: [String: NapaxiJSONValue]? = nil,
        result: String? = nil,
        error: String? = nil,
        rationale: String? = nil,
        interrupted: Bool = false,
        resultTruncated: Bool = false,
        errorTruncated: Bool = false,
        argumentsTruncated: Bool = false
    ) {
        self.name = name
        self.callId = callId
        self.arguments = arguments
        self.result = result
        self.error = error
        self.rationale = rationale
        self.interrupted = interrupted
        self.resultTruncated = resultTruncated
        self.errorTruncated = errorTruncated
        self.argumentsTruncated = argumentsTruncated
    }

    public init(from decoder: Decoder) throws {
        let object = try NapaxiSessionJSONObject(decoder: decoder)
        self.name = object.string("name") ?? "unknown"
        self.callId = object.string("call_id", "tool_call_id", "callId") ?? ""
        self.arguments = object.object("arguments", "parameters")
        self.result = object.displayString("result", "result_preview", "resultPreview")
        self.error = object.displayString("error", "error_preview", "errorPreview")
        self.rationale = object.string("rationale")
        self.interrupted = object.bool("interrupted") ?? false
        self.resultTruncated = object.bool("result_truncated", "resultTruncated") == true
            || object.hasValue("result_preview", "resultPreview")
        self.errorTruncated = object.bool("error_truncated", "errorTruncated") == true
            || object.hasValue("error_preview", "errorPreview")
        self.argumentsTruncated = object.bool("arguments_truncated", "argumentsTruncated") == true
            || object.bool("parameters_truncated", "parametersTruncated") == true
    }

    public func encode(to encoder: Encoder) throws {
        var object: [String: NapaxiJSONValue] = [
            "name": .string(name),
            "call_id": .string(callId),
            "interrupted": .bool(interrupted),
            "result_truncated": .bool(resultTruncated),
            "error_truncated": .bool(errorTruncated),
            "arguments_truncated": .bool(argumentsTruncated),
        ]
        if let arguments {
            object["arguments"] = .object(arguments)
        }
        if let result {
            object["result"] = .string(result)
        }
        if let error {
            object["error"] = .string(error)
        }
        if let rationale {
            object["rationale"] = .string(rationale)
        }
        var container = encoder.singleValueContainer()
        try container.encode(NapaxiJSONValue.object(object))
    }

    public init(map: [String: NapaxiJSONValue]) throws {
        self = try Self.fromMap(map)
    }

    public static func fromMap(_ map: [String: NapaxiJSONValue]) throws -> Self {
        try sessionDecode(Self.self, from: map)
    }

    public func toMap() -> [String: NapaxiJSONValue] {
        var object: [String: NapaxiJSONValue] = [
            "name": .string(name),
            "call_id": .string(callId),
            "interrupted": .bool(interrupted),
            "result_truncated": .bool(resultTruncated),
            "error_truncated": .bool(errorTruncated),
            "arguments_truncated": .bool(argumentsTruncated),
        ]
        if let arguments {
            object["arguments"] = .object(arguments)
        }
        if let result {
            object["result"] = .string(result)
        }
        if let error {
            object["error"] = .string(error)
        }
        if let rationale {
            object["rationale"] = .string(rationale)
        }
        return object
    }
}

public struct NapaxiChatMessage: Codable, Equatable, Sendable {
    public var role: String
    public var content: String
    public var attachments: [NapaxiChatAttachment]
    public var id: String?
    public var createdAt: String?
    public var thinkingContent: String?
    public var reasoningContent: String?
    public var toolCalls: [NapaxiToolCallInfo]?
    public var humanRequestId: String?
    public var humanQuestion: String?
    public var humanOptions: [String]
    public var humanContext: String?
    public var interrupted: Bool

    public var isUser: Bool { role == "user" }
    public var isAssistant: Bool { role == "assistant" }
    public var isThinking: Bool { role == "thinking" }
    public var isReasoning: Bool { role == "reasoning" }
    public var isToolCalls: Bool { role == "tool_calls" }
    public var isAskingHuman: Bool { role == "asking_human" }

    public init(
        role: String,
        content: String,
        attachments: [NapaxiChatAttachment] = [],
        id: String? = nil,
        createdAt: String? = nil,
        thinkingContent: String? = nil,
        reasoningContent: String? = nil,
        toolCalls: [NapaxiToolCallInfo]? = nil,
        humanRequestId: String? = nil,
        humanQuestion: String? = nil,
        humanOptions: [String] = [],
        humanContext: String? = nil,
        interrupted: Bool = false
    ) {
        self.role = role
        self.content = content
        self.attachments = attachments
        self.id = id
        self.createdAt = createdAt
        self.thinkingContent = thinkingContent
        self.reasoningContent = reasoningContent
        self.toolCalls = toolCalls
        self.humanRequestId = humanRequestId
        self.humanQuestion = humanQuestion
        self.humanOptions = humanOptions
        self.humanContext = humanContext
        self.interrupted = interrupted
    }

    public init(from decoder: Decoder) throws {
        let object = try NapaxiSessionJSONObject(decoder: decoder)
        self.role = object.string("role") ?? ""
        self.content = object.string("content") ?? ""
        self.attachments = (try object.decodeArray(NapaxiChatAttachment.self, "attachments")) ?? []
        self.id = object.string("id")
        self.createdAt = object.string("created_at", "createdAt")
        self.interrupted = object.bool("interrupted") ?? false
        self.humanOptions = []
        if role == "thinking" {
            self.thinkingContent = content
        }
        if role == "reasoning" {
            self.reasoningContent = content
        }
        if role == "tool_calls",
           let data = content.data(using: .utf8),
           let decoded = try? JSONDecoder().decode(NapaxiJSONValue.self, from: data),
           case .object(let callObject) = decoded {
            self.thinkingContent = callObject["narrative"]?.stringValue
            if case .array(let calls)? = callObject["calls"] {
                do {
                    self.toolCalls = try calls.map { value in
                        let data = try JSONEncoder().encode(value)
                        return try JSONDecoder().decode(NapaxiToolCallInfo.self, from: data)
                    }
                } catch {
                    self.toolCalls = nil
                }
            }
        }
        if role == "asking_human",
           let data = content.data(using: .utf8),
           let decoded = try? JSONDecoder().decode(NapaxiJSONValue.self, from: data),
           case .object(let humanObject) = decoded {
            self.humanRequestId = humanObject["request_id"]?.stringValue
            self.humanQuestion = humanObject["question"]?.stringValue
            if case .array(let options)? = humanObject["options"] {
                self.humanOptions = options.compactMap(\.stringValue)
            }
            self.humanContext = humanObject["context"]?.stringValue
        } else if role == "asking_human" {
            self.humanQuestion = content
        }
    }

    public init(map: [String: NapaxiJSONValue]) throws {
        self = try Self.fromMap(map)
    }

    public static func fromMap(_ map: [String: NapaxiJSONValue]) throws -> Self {
        try sessionDecode(Self.self, from: map)
    }
}

private struct NapaxiSessionJSONObject {
    private let values: [String: NapaxiJSONValue]

    init(decoder: Decoder) throws {
        self.values = try decoder.singleValueContainer().decode([String: NapaxiJSONValue].self)
    }

    func string(_ keys: String...) -> String? {
        for key in keys {
            if let value = values[key]?.stringValue { return value }
        }
        return nil
    }

    func displayString(_ keys: String...) -> String? {
        for key in keys {
            guard let value = values[key], value != .null else { continue }
            return value.jsonCodecDisplayString
        }
        return nil
    }

    func bool(_ keys: String...) -> Bool? {
        for key in keys {
            if let value = values[key]?.boolValue { return value }
        }
        return nil
    }

    func hasValue(_ keys: String...) -> Bool {
        for key in keys {
            if let value = values[key], value != .null { return true }
        }
        return false
    }

    func int(_ keys: String...) -> Int? {
        for key in keys {
            guard let value = values[key] else { continue }
            if let number = value.numberValue { return Int(number) }
            if let string = value.stringValue { return Int(string) }
        }
        return nil
    }

    func strictInt(_ keys: String...) -> Int? {
        for key in keys {
            guard case .number(let value)? = values[key], value.isFinite else { continue }
            let integer = value.rounded(.towardZero)
            guard integer == value else { continue }
            return Int(integer)
        }
        return nil
    }

    func double(_ keys: String...) -> Double? {
        for key in keys {
            guard let value = values[key] else { continue }
            if let number = value.numberValue { return number }
            if let string = value.stringValue { return Double(string) }
        }
        return nil
    }

    func object(_ keys: String...) -> [String: NapaxiJSONValue]? {
        for key in keys {
            guard let value = values[key] else { continue }
            if case .object(let object) = value { return object }
            if let string = value.stringValue,
               let data = string.data(using: .utf8),
               let decoded = try? JSONDecoder().decode(NapaxiJSONValue.self, from: data),
               case .object(let object) = decoded {
                return object
            }
        }
        return nil
    }

    func decode<T: Decodable>(_ type: T.Type, _ keys: String...) throws -> T? {
        for key in keys {
            guard let value = values[key] else { continue }
            let data = try JSONEncoder().encode(value)
            return try JSONDecoder().decode(type, from: data)
        }
        return nil
    }

    func decodeArray<T: Decodable>(_ type: T.Type, _ key: String) throws -> [T]? {
        guard let value = values[key] else { return nil }
        let data = try JSONEncoder().encode(value)
        return try JSONDecoder().decode([T].self, from: data)
    }
}

private func sessionObjectMap(from jsonString: String) throws -> [String: NapaxiJSONValue] {
    let value = try NapaxiRawJSON(jsonString: jsonString).value
    guard case .object(let object) = value else {
        throw NapaxiError.invalidJSON("Session JSON must be an object")
    }
    return object
}

private func sessionDecode<T: Decodable>(_ type: T.Type, from map: [String: NapaxiJSONValue]) throws -> T {
    let data = try JSONEncoder().encode(NapaxiJSONValue.object(map))
    return try JSONDecoder().decode(type, from: data)
}

private extension Dictionary where Key == String, Value == NapaxiJSONValue {
    func sessionString(_ keys: String...) -> String? {
        for key in keys {
            if let value = self[key]?.stringValue { return value }
        }
        return nil
    }

    func validateSessionOptionalString(_ key: String) throws {
        guard let value = self[key], value != .null else { return }
        guard case .string = value else {
            throw NapaxiError.invalidJSON("Expected session field '\(key)' to be a string")
        }
    }

    func validateSessionOptionalBool(_ key: String) throws {
        guard let value = self[key], value != .null else { return }
        guard case .bool = value else {
            throw NapaxiError.invalidJSON("Expected session field '\(key)' to be a bool")
        }
    }

    func validateSessionOptionalStrictInt(_ key: String) throws {
        guard let value = self[key], value != .null else { return }
        guard case .number(let number) = value, number.isFinite, number.rounded(.towardZero) == number else {
            throw NapaxiError.invalidJSON("Expected session field '\(key)' to be an integer")
        }
    }

    func validateSessionOptionalArray(_ key: String) throws {
        guard let value = self[key], value != .null else { return }
        guard case .array = value else {
            throw NapaxiError.invalidJSON("Expected session field '\(key)' to be an array")
        }
    }

    mutating func normalizeSessionRequiredObjectListOrEmpty(
        _ key: String,
        _ normalize: ([String: NapaxiJSONValue]) throws -> [String: NapaxiJSONValue]
    ) throws {
        guard let value = self[key], value != .null else {
            self[key] = .array([])
            return
        }
        guard case .array(let values) = value else {
            throw NapaxiError.invalidJSON("Expected session field '\(key)' to be an array")
        }
        var objects: [NapaxiJSONValue] = []
        for value in values {
            guard case .object(let object) = value else {
                throw NapaxiError.invalidJSON("Expected session field '\(key)' to contain objects")
            }
            objects.append(.object(try normalize(object)))
        }
        self[key] = .array(objects)
    }
}

private extension String {
    var napaxiIsSandboxPath: Bool {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value == "/workspace" ||
            value.hasPrefix("/workspace/") ||
            value == "/skills" ||
            value.hasPrefix("/skills/")
    }
}
