import Foundation

private extension NapaxiJSONValue {
    var skillStringValue: String? {
        switch self {
        case .string(let value):
            return value
        case .number(let value):
            if value.rounded() == value {
                return String(Int(value))
            }
            return String(value)
        case .bool(let value):
            return String(value)
        case .null, .array, .object:
            return nil
        }
    }
}

private extension NapaxiStableModel {
    func skillString(_ keys: String...) -> String? {
        for key in keys {
            if let value = raw[key]?.skillStringValue {
                return value
            }
        }
        return nil
    }
}

public extension NapaxiStableModel where Tag == NapaxiSkillLifecycleSummaryTag {
    var state: String { string("state") ?? "active" }
    var pinned: Bool { bool("pinned") ?? false }
    var createdBy: String? { string("created_by") ?? string("createdBy") }
    var useCount: Int { raw.int("use_count") ?? raw.int("useCount") ?? 0 }
    var viewCount: Int { raw.int("view_count") ?? raw.int("viewCount") ?? 0 }
    var patchCount: Int { raw.int("patch_count") ?? raw.int("patchCount") ?? 0 }
    var lastUsedAt: String? { string("last_used_at") ?? string("lastUsedAt") }
    var lastViewedAt: String? { string("last_viewed_at") ?? string("lastViewedAt") }
    var lastPatchedAt: String? { string("last_patched_at") ?? string("lastPatchedAt") }
    var archivedAt: String? { string("archived_at") ?? string("archivedAt") }
    var absorbedInto: String? { string("absorbed_into") ?? string("absorbedInto") }
    var protected: Bool { bool("protected") ?? false }
}

public extension NapaxiStableModel where Tag == NapaxiSkillInfoTag {
    var name: String { string("name") ?? "" }
    var version: String { string("version") ?? "" }
    var description: String { string("description") ?? "" }
    var always: Bool { bool("always") ?? false }
    var allowedAgents: [String] { raw.stringArray("allowed_agents") ?? raw.stringArray("allowedAgents") ?? [] }
    var trust: String { string("trust") ?? "Trusted" }
    var source: String { string("source") ?? "" }
    var keywords: [String] { raw.stringArray("keywords") ?? [] }
    var tags: [String] { raw.stringArray("tags") ?? [] }
    var promptContent: String? { string("prompt_content") ?? string("promptContent") }
    var contentHash: String? { string("content_hash") ?? string("contentHash") }
    var lifecycle: NapaxiSkillLifecycleSummary { raw.model("lifecycle") ?? NapaxiSkillLifecycleSummary() }
    var supportFiles: [String] { raw.stringArray("support_files") ?? raw.stringArray("supportFiles") ?? [] }
}

func validateSkillInfoObject(_ object: [String: NapaxiJSONValue]) throws {
    try object.validateSkillOptionalString("name")
    try object.validateSkillOptionalString("version")
    try object.validateSkillOptionalString("description")
    try object.validateSkillOptionalBool("always")
    try object.validateSkillOptionalStringArray("allowed_agents")
    try object.validateSkillOptionalStringArray("allowedAgents")
    try object.validateSkillOptionalString("trust")
    try object.validateSkillOptionalString("source")
    try object.validateSkillOptionalStringArray("keywords")
    try object.validateSkillOptionalStringArray("tags")
    try object.validateSkillOptionalString("prompt_content")
    try object.validateSkillOptionalString("promptContent")
    try object.validateSkillOptionalString("content_hash")
    try object.validateSkillOptionalString("contentHash")
    try object.validateSkillOptionalObject("lifecycle", validateSkillLifecycleSummaryObject)
    try object.validateSkillOptionalStringArray("support_files")
    try object.validateSkillOptionalStringArray("supportFiles")
}

func validateSkillLifecycleSummaryObject(_ object: [String: NapaxiJSONValue]) throws {
    try object.validateSkillOptionalString("state")
    try object.validateSkillOptionalBool("pinned")
    try object.validateSkillOptionalString("created_by")
    try object.validateSkillOptionalString("createdBy")
    try object.validateSkillOptionalNumber("use_count")
    try object.validateSkillOptionalNumber("useCount")
    try object.validateSkillOptionalNumber("view_count")
    try object.validateSkillOptionalNumber("viewCount")
    try object.validateSkillOptionalNumber("patch_count")
    try object.validateSkillOptionalNumber("patchCount")
    try object.validateSkillOptionalString("last_used_at")
    try object.validateSkillOptionalString("lastUsedAt")
    try object.validateSkillOptionalString("last_viewed_at")
    try object.validateSkillOptionalString("lastViewedAt")
    try object.validateSkillOptionalString("last_patched_at")
    try object.validateSkillOptionalString("lastPatchedAt")
    try object.validateSkillOptionalString("archived_at")
    try object.validateSkillOptionalString("archivedAt")
    try object.validateSkillOptionalString("absorbed_into")
    try object.validateSkillOptionalString("absorbedInto")
}

public extension NapaxiStableModel where Tag == NapaxiSkillRequirementSummaryTag {
    var bins: [String] { raw.stringArray("bins") ?? [] }
    var anyBins: [String] { raw.stringArray("any_bins") ?? raw.stringArray("anyBins") ?? [] }
    var env: [String] { raw.stringArray("env") ?? [] }
    var config: [String] { raw.stringArray("config") ?? [] }
    var os: [String] { raw.stringArray("os") ?? [] }
    var capabilities: [String] { raw.stringArray("capabilities") ?? [] }
    var skills: [String] { raw.stringArray("skills") ?? [] }
    var isEmpty: Bool { bins.isEmpty && anyBins.isEmpty && env.isEmpty && config.isEmpty && os.isEmpty && capabilities.isEmpty && skills.isEmpty }
}

public extension NapaxiStableModel where Tag == NapaxiSkillOpenClawMetadataTag {
    var userInvocable: Bool { bool("user_invocable") ?? bool("userInvocable") ?? true }
    var disableModelInvocation: Bool { bool("disable_model_invocation") ?? bool("disableModelInvocation") ?? false }
    var commandDispatch: String? { skillString("command_dispatch", "commandDispatch") }
    var commandTool: String? { skillString("command_tool", "commandTool") }
    var commandArgMode: String? { skillString("command_arg_mode", "commandArgMode") }
    var primaryEnv: String? { skillString("primary_env", "primaryEnv") }
    var skillKey: String? { skillString("skill_key", "skillKey") }
    var homepage: String? { skillString("homepage") }
    var emoji: String? { skillString("emoji") }
}

public extension NapaxiStableModel where Tag == NapaxiSkillStatusEntryTag {
    var name: String { string("name") ?? "" }
    var description: String { string("description") ?? "" }
    var sourceKind: String { string("source_kind") ?? string("sourceKind") ?? "" }
    var source: String { string("source") ?? "" }
    var trust: String { string("trust") ?? "" }
    var enabled: Bool { bool("enabled") ?? true }
    var eligible: Bool { bool("eligible") ?? false }
    var status: String { string("status") ?? "" }
    var requirements: NapaxiSkillRequirementSummary { raw.model("requirements") ?? NapaxiSkillRequirementSummary() }
    var missing: NapaxiSkillRequirementSummary { raw.model("missing") ?? NapaxiSkillRequirementSummary() }
    var installOptions: [[String: NapaxiJSONValue]] { raw.objectArray("install_options") ?? raw.objectArray("installOptions") ?? [] }
    var warnings: [String] { raw.stringArray("warnings") ?? [] }
    var error: String? { skillString("error") }
    var lifecycle: NapaxiSkillLifecycleSummary { raw.model("lifecycle") ?? NapaxiSkillLifecycleSummary() }
    var metadata: NapaxiSkillOpenClawMetadata { raw.model("metadata") ?? NapaxiSkillOpenClawMetadata() }
    var provenance: NapaxiSkillProvenance { raw.model("provenance") ?? NapaxiSkillProvenance() }
    var remediationActions: [NapaxiSkillRemediationAction] { raw.modelArray("remediation_actions") ?? raw.modelArray("remediationActions") ?? [] }
    var isReady: Bool { status == "ready" }
    var isBlocked: Bool {
        ["missing_requirements", "parse_error", "security_blocked", "too_large", "blocked"].contains(status)
    }
}

func normalizedSkillStatusReportObject(_ object: [String: NapaxiJSONValue]) throws -> [String: NapaxiJSONValue] {
    var normalized = object
    try normalized.normalizeSkillObjectList("entries", normalizedSkillStatusEntryObject)
    try normalized.normalizeSkillObjectList("top_blockers", normalizedSkillStatusEntryObject)
    return normalized
}

func normalizedSkillStatusEntryObject(_ object: [String: NapaxiJSONValue]) throws -> [String: NapaxiJSONValue] {
    try validateSkillStatusEntryObject(object)
    var normalized = object
    try normalized.normalizeSkillObjectList("remediation_actions") { action in
        try validateSkillRemediationActionObject(action)
        return action
    }
    try normalized.normalizeSkillObjectList("remediationActions") { action in
        try validateSkillRemediationActionObject(action)
        return action
    }
    return normalized
}

func validateSkillStatusEntryObject(_ object: [String: NapaxiJSONValue]) throws {
    try object.validateSkillOptionalString("name")
    try object.validateSkillOptionalString("description")
    try object.validateSkillOptionalString("source_kind")
    try object.validateSkillOptionalString("sourceKind")
    try object.validateSkillOptionalString("source")
    try object.validateSkillOptionalString("trust")
    try object.validateSkillOptionalBool("enabled")
    try object.validateSkillOptionalBool("eligible")
    try object.validateSkillOptionalString("status")
    try object.validateSkillOptionalArray("install_options")
    if case .object(let lifecycle)? = object["lifecycle"] {
        try validateSkillLifecycleSummaryObject(lifecycle)
    }
    if case .object(let metadata)? = object["metadata"] {
        try validateSkillOpenClawMetadataObject(metadata)
    }
    if case .object(let provenance)? = object["provenance"] {
        try validateSkillProvenanceObject(provenance)
    }
    if case .array(let values)? = object["remediation_actions"] {
        try validateSkillObjectItems(values, validateSkillRemediationActionObject)
    }
    if case .array(let values)? = object["remediationActions"] {
        try validateSkillObjectItems(values, validateSkillRemediationActionObject)
    }
}

func validateSkillOpenClawMetadataObject(_ object: [String: NapaxiJSONValue]) throws {
    try object.validateSkillOptionalBool("user_invocable")
    try object.validateSkillOptionalBool("userInvocable")
    try object.validateSkillOptionalBool("disable_model_invocation")
    try object.validateSkillOptionalBool("disableModelInvocation")
}

func validateSkillProvenanceObject(_ object: [String: NapaxiJSONValue]) throws {
    try object.validateSkillOptionalBool("legacy")
}

func validateSkillRemediationActionObject(_ object: [String: NapaxiJSONValue]) throws {
    try object.validateSkillOptionalBool("host_handled")
    try object.validateSkillOptionalBool("hostHandled")
}

public extension NapaxiStableModel where Tag == NapaxiSkillProvenanceTag {
    var sourceKind: String { skillString("source_kind", "sourceKind") ?? "" }
    var trust: String { skillString("trust") ?? "" }
    var managedBy: String { skillString("managed_by", "managedBy") ?? "" }
    var legacy: Bool { bool("legacy") ?? false }
}

public extension NapaxiStableModel where Tag == NapaxiSkillRemediationActionTag {
    var id: String { skillString("id") ?? "" }
    var kind: String { skillString("kind") ?? "" }
    var label: String { skillString("label") ?? "" }
    var requirement: String { skillString("requirement") ?? "" }
    var hostHandled: Bool { bool("host_handled") ?? bool("hostHandled") ?? true }
    var dangerLevel: String { skillString("danger_level", "dangerLevel") ?? "low" }
}

public extension NapaxiStableModel where Tag == NapaxiSkillCommandReportTag {
    init(map: [String: NapaxiJSONValue]) {
        self = Self.fromMap(map)
    }

    static func fromJson(_ jsonString: String) throws -> Self {
        try fromJsonString(jsonString)
    }

    static func fromJsonString(_ jsonString: String) throws -> Self {
        Self.fromMap(try skillObjectMap(from: jsonString))
    }

    static func fromMap(_ map: [String: NapaxiJSONValue]) -> Self {
        Self(raw: map)
    }

    var commands: [NapaxiSkillCommand] { raw.modelArray("commands") ?? [] }
    var total: Int { raw.int("total") ?? commands.count }
    var snapshotId: String? { skillString("snapshot_id", "snapshotId") }
}

func normalizedSkillCommandReportObject(_ object: [String: NapaxiJSONValue]) throws -> [String: NapaxiJSONValue] {
    var normalized = object
    try normalized.normalizeSkillObjectListOrEmpty("commands", normalizedSkillCommandObject)
    return normalized
}

public extension NapaxiStableModel where Tag == NapaxiSkillSourceReportTag {
    init(map: [String: NapaxiJSONValue]) {
        self = Self.fromMap(map)
    }

    static func fromJson(_ jsonString: String) throws -> Self {
        try fromJsonString(jsonString)
    }

    static func fromJsonString(_ jsonString: String) throws -> Self {
        Self.fromMap(try skillObjectMap(from: jsonString))
    }

    static func fromMap(_ map: [String: NapaxiJSONValue]) -> Self {
        Self(raw: map)
    }

    var agentId: String { skillString("agent_id", "agentId") ?? "" }
    var sources: [NapaxiSkillSourceEntry] { raw.modelArray("sources") ?? [] }
}

func normalizedSkillSourceReportObject(_ object: [String: NapaxiJSONValue]) throws -> [String: NapaxiJSONValue] {
    var normalized = object
    try normalized.normalizeSkillObjectListOrEmpty("sources", normalizedSkillSourceEntryObject)
    return normalized
}

public extension NapaxiStableModel where Tag == NapaxiSkillSourceEntryTag {
    init(map: [String: NapaxiJSONValue]) {
        self = Self.fromMap(map)
    }

    static func fromMap(_ map: [String: NapaxiJSONValue]) -> Self {
        Self(raw: map)
    }

    var id: String { skillString("id") ?? "" }
    var kind: String { skillString("kind") ?? "" }
    var root: String { skillString("root") ?? "" }
    var priority: Int { raw.int("priority") ?? 0 }
    var trust: String { skillString("trust") ?? "" }
    var exists: Bool { bool("exists") ?? false }
    var version: Int { raw.int("version") ?? 0 }
    var updatedAt: String? { skillString("updated_at", "updatedAt") }
}

func normalizedSkillSourceEntryObject(_ object: [String: NapaxiJSONValue]) throws -> [String: NapaxiJSONValue] {
    try object.validateSkillOptionalBool("exists")
    return object
}

public extension NapaxiStableModel where Tag == NapaxiSkillRefreshResultTag {
    init(map: [String: NapaxiJSONValue]) {
        self = Self.fromMap(map)
    }

    static func fromJson(_ jsonString: String) throws -> Self {
        try fromJsonString(jsonString)
    }

    static func fromJsonString(_ jsonString: String) throws -> Self {
        Self.fromMap(try skillObjectMap(from: jsonString))
    }

    static func fromMap(_ map: [String: NapaxiJSONValue]) -> Self {
        Self(raw: map)
    }

    var success: Bool { bool("success") ?? false }
    var agentId: String { skillString("agent_id", "agentId") ?? "" }
    var sourceId: String { skillString("source_id", "sourceId") ?? "" }
    var version: Int { raw.int("version") ?? 0 }
    var recordedAt: String { skillString("recorded_at", "recordedAt") ?? "" }
    var error: String? { skillString("error") }
}

func normalizedSkillRefreshResultObject(_ object: [String: NapaxiJSONValue]) throws -> [String: NapaxiJSONValue] {
    try object.validateSkillOptionalBool("success")
    return object
}

public extension NapaxiStableModel where Tag == NapaxiSkillCommandTag {
    init(map: [String: NapaxiJSONValue]) {
        self = Self.fromMap(map)
    }

    static func fromMap(_ map: [String: NapaxiJSONValue]) -> Self {
        Self(raw: map)
    }

    var name: String { skillString("name") ?? "" }
    var skillName: String { skillString("skill_name", "skillName") ?? "" }
    var description: String { skillString("description") ?? "" }
    var dispatch: NapaxiSkillCommandDispatch? { raw.model("dispatch") }
    var argMode: String? { skillString("arg_mode", "argMode") }
    var eligible: Bool { bool("eligible") ?? false }
    var disabledReason: String? { skillString("disabled_reason", "disabledReason") }
}

func normalizedSkillCommandObject(_ object: [String: NapaxiJSONValue]) throws -> [String: NapaxiJSONValue] {
    try validateSkillCommandObject(object)
    return object
}

func validateSkillCommandObject(_ object: [String: NapaxiJSONValue]) throws {
    try object.validateSkillOptionalBool("eligible")
}

public extension NapaxiStableModel where Tag == NapaxiSkillCommandDispatchTag {
    init(map: [String: NapaxiJSONValue]) {
        self = Self.fromMap(map)
    }

    static func fromMap(_ map: [String: NapaxiJSONValue]) -> Self {
        Self(raw: map)
    }

    static func fromMapOrNull(_ map: [String: NapaxiJSONValue]?) -> Self? {
        guard let map else { return nil }
        return Self.fromMap(map)
    }

    var kind: String { skillString("kind") ?? "" }
    var toolName: String? { skillString("tool_name", "toolName") }
}

public extension NapaxiStableModel where Tag == NapaxiSkillCommandResolutionTag {
    init(map: [String: NapaxiJSONValue]) {
        self = Self.fromMap(map)
    }

    static func fromJson(_ jsonString: String) throws -> Self {
        try fromJsonString(jsonString)
    }

    static func fromJsonString(_ jsonString: String) throws -> Self {
        Self.fromMap(try skillObjectMap(from: jsonString))
    }

    static func fromMap(_ map: [String: NapaxiJSONValue]) -> Self {
        Self(raw: map)
    }

    var matched: Bool { bool("matched") ?? false }
    var command: NapaxiSkillCommand? { raw.model("command") }
    var args: String? { skillString("args") }
    var error: String? { skillString("error") }
}

func normalizedSkillCommandResolutionObject(_ object: [String: NapaxiJSONValue]) throws -> [String: NapaxiJSONValue] {
    try object.validateSkillOptionalBool("matched")
    var normalized = object
    if case .object(let command)? = object["command"] {
        normalized["command"] = .object(try normalizedSkillCommandObject(command))
    }
    return normalized
}

public extension NapaxiStableModel where Tag == NapaxiSkillCommandRunTag {
    init(map: [String: NapaxiJSONValue]) {
        self = Self.fromMap(map)
    }

    static func fromJson(_ jsonString: String) throws -> Self {
        try fromJsonString(jsonString)
    }

    static func fromJsonString(_ jsonString: String) throws -> Self {
        Self.fromMap(try skillObjectMap(from: jsonString))
    }

    static func fromMap(_ map: [String: NapaxiJSONValue]) -> Self {
        Self(raw: map)
    }

    var success: Bool { bool("success") ?? false }
    var status: String { skillString("status") ?? "" }
    var commandName: String { skillString("command_name", "commandName") ?? "" }
    var skillName: String? { skillString("skill_name", "skillName") }
    var args: String? { skillString("args") }
    var sessionKey: String? { skillString("session_key", "sessionKey") }
    var message: String? { skillString("message") }
    var dispatch: NapaxiSkillCommandDispatch? { raw.model("dispatch") }
    var error: String? { skillString("error") }
}

func normalizedSkillCommandRunObject(_ object: [String: NapaxiJSONValue]) throws -> [String: NapaxiJSONValue] {
    try object.validateSkillOptionalBool("success")
    return object
}

public extension NapaxiStableModel where Tag == NapaxiSkillSnapshotListTag {
    init(map: [String: NapaxiJSONValue]) {
        self = Self.fromMap(map)
    }

    static func fromJson(_ jsonString: String) throws -> Self {
        try fromJsonString(jsonString)
    }

    static func fromJsonString(_ jsonString: String) throws -> Self {
        Self.fromMap(try skillObjectMap(from: jsonString))
    }

    static func fromMap(_ map: [String: NapaxiJSONValue]) -> Self {
        Self(raw: map)
    }

    var snapshots: [NapaxiSkillSnapshotIndexEntry] { raw.modelArray("snapshots") ?? [] }
    var total: Int { raw.int("total") ?? snapshots.count }
}

func normalizedSkillSnapshotListObject(_ object: [String: NapaxiJSONValue]) throws -> [String: NapaxiJSONValue] {
    var normalized = object
    try normalized.normalizeSkillObjectListOrEmpty("snapshots") { entry in entry }
    return normalized
}

public extension NapaxiStableModel where Tag == NapaxiSkillSnapshotIndexEntryTag {
    init(map: [String: NapaxiJSONValue]) {
        self = Self.fromMap(map)
    }

    static func fromMap(_ map: [String: NapaxiJSONValue]) -> Self {
        Self(raw: map)
    }

    var snapshotId: String { skillString("snapshot_id", "snapshotId") ?? "" }
    var agentId: String { skillString("agent_id", "agentId") ?? "" }
    var purpose: String { skillString("purpose") ?? "" }
    var createdAt: String { skillString("created_at", "createdAt") ?? "" }
}

public extension NapaxiStableModel where Tag == NapaxiSkillSnapshotTag {
    init(map: [String: NapaxiJSONValue]) {
        self = Self.fromMap(map)
    }

    static func fromJson(_ jsonString: String) throws -> Self {
        try fromJsonString(jsonString)
    }

    static func fromJsonString(_ jsonString: String) throws -> Self {
        Self.fromMap(try skillObjectMap(from: jsonString))
    }

    static func fromMap(_ map: [String: NapaxiJSONValue]) -> Self {
        Self(raw: map)
    }

    var snapshotId: String { skillString("snapshot_id", "snapshotId") ?? "" }
    var agentId: String { skillString("agent_id", "agentId") ?? "" }
    var purpose: String { skillString("purpose") ?? "" }
    var createdAt: String { skillString("created_at", "createdAt") ?? "" }
    var sourceVersions: [String: Int] {
        (raw.object("source_versions") ?? raw.object("sourceVersions"))?.mapValues { value in
            if let number = value.numberValue { return Int(number) }
            if let string = value.stringValue { return Int(string) ?? 0 }
            return 0
        } ?? [:]
    }
    var catalogEntries: [NapaxiSkillSnapshotCatalogEntry] {
        raw.modelArray("catalog_entries") ?? raw.modelArray("catalogEntries") ?? []
    }
    var commandEntries: [NapaxiSkillCommand] {
        raw.modelArray("command_entries") ?? raw.modelArray("commandEntries") ?? []
    }
    var statusCounts: [String: NapaxiJSONValue] { raw.object("status_counts") ?? raw.object("statusCounts") ?? [:] }
    var catalogPlan: [String: NapaxiJSONValue] { raw.object("catalog_plan") ?? raw.object("catalogPlan") ?? [:] }
}

func normalizedSkillSnapshotObject(_ object: [String: NapaxiJSONValue]) throws -> [String: NapaxiJSONValue] {
    var normalized = object
    normalized.normalizeSkillObjectOrEmptyIfPresent("source_versions")
    if normalized["source_versions"] == nil || normalized["source_versions"] == .null {
        normalized.normalizeSkillObjectOrEmptyIfPresent("sourceVersions")
    }
    try normalized.normalizeSkillObjectListOrEmpty("catalog_entries") { entry in entry }
    if normalized["catalog_entries"] == nil || normalized["catalog_entries"] == .null {
        try normalized.normalizeSkillObjectListOrEmpty("catalogEntries") { entry in entry }
    }
    try normalized.normalizeSkillObjectListOrEmpty("command_entries", normalizedSkillCommandObject)
    if normalized["command_entries"] == nil || normalized["command_entries"] == .null {
        try normalized.normalizeSkillObjectListOrEmpty("commandEntries", normalizedSkillCommandObject)
    }
    normalized.normalizeSkillObjectOrEmptyIfPresent("status_counts")
    if normalized["status_counts"] == nil || normalized["status_counts"] == .null {
        normalized.normalizeSkillObjectOrEmptyIfPresent("statusCounts")
    }
    normalized.normalizeSkillObjectOrEmptyIfPresent("catalog_plan")
    if normalized["catalog_plan"] == nil || normalized["catalog_plan"] == .null {
        normalized.normalizeSkillObjectOrEmptyIfPresent("catalogPlan")
    }
    return normalized
}

public extension NapaxiStableModel where Tag == NapaxiSkillSnapshotCatalogEntryTag {
    init(map: [String: NapaxiJSONValue]) {
        self = Self.fromMap(map)
    }

    static func fromMap(_ map: [String: NapaxiJSONValue]) -> Self {
        Self(raw: map)
    }

    var name: String { skillString("name") ?? "" }
    var version: String { skillString("version") ?? "" }
    var description: String { skillString("description") ?? "" }
    var trust: String { skillString("trust") ?? "" }
    var activationHint: String { skillString("activation_hint", "activationHint") ?? "" }
    var contentHash: String { skillString("content_hash", "contentHash") ?? "" }
}

public extension NapaxiStableModel where Tag == NapaxiSkillSecretRequirementReportTag {
    init(map: [String: NapaxiJSONValue]) {
        self = Self.fromMap(map)
    }

    static func fromJson(_ jsonString: String) throws -> Self {
        try fromJsonString(jsonString)
    }

    static func fromJsonString(_ jsonString: String) throws -> Self {
        Self.fromMap(try skillObjectMap(from: jsonString))
    }

    static func fromMap(_ map: [String: NapaxiJSONValue]) -> Self {
        Self(raw: map)
    }

    var requirements: [NapaxiSkillSecretRequirement] { raw.modelArray("requirements") ?? [] }
}

func normalizedSkillSecretRequirementReportObject(_ object: [String: NapaxiJSONValue]) throws -> [String: NapaxiJSONValue] {
    var normalized = object
    try normalized.normalizeSkillObjectListOrEmpty("requirements", normalizedSkillSecretRequirementObject)
    return normalized
}

public extension NapaxiStableModel where Tag == NapaxiSkillSecretRequirementTag {
    init(map: [String: NapaxiJSONValue]) {
        self = Self.fromMap(map)
    }

    static func fromMap(_ map: [String: NapaxiJSONValue]) -> Self {
        Self(raw: map)
    }

    var skillName: String { skillString("skill_name", "skillName") ?? "" }
    var skillKey: String { skillString("skill_key", "skillKey") ?? "" }
    var key: String { skillString("key") ?? "" }
    var source: String { skillString("source") ?? "" }
    var available: Bool { bool("available") ?? false }
}

func normalizedSkillSecretRequirementObject(_ object: [String: NapaxiJSONValue]) throws -> [String: NapaxiJSONValue] {
    try object.validateSkillOptionalBool("available")
    return object
}

public extension NapaxiStableModel where Tag == NapaxiSkillRemediationRunListTag {
    init(map: [String: NapaxiJSONValue]) {
        self = Self.fromMap(map)
    }

    static func fromJson(_ jsonString: String) throws -> Self {
        try fromJsonString(jsonString)
    }

    static func fromJsonString(_ jsonString: String) throws -> Self {
        Self.fromMap(try skillObjectMap(from: jsonString))
    }

    static func fromMap(_ map: [String: NapaxiJSONValue]) -> Self {
        Self(raw: map)
    }

    var runs: [NapaxiSkillRemediationRun] { raw.modelArray("runs") ?? [] }
    var total: Int { raw.int("total") ?? runs.count }
}

func normalizedSkillRemediationRunListObject(_ object: [String: NapaxiJSONValue]) throws -> [String: NapaxiJSONValue] {
    var normalized = object
    try normalized.normalizeSkillObjectListOrEmpty("runs") { entry in entry }
    return normalized
}

public extension NapaxiStableModel where Tag == NapaxiSkillRemediationRunTag {
    init(map: [String: NapaxiJSONValue]) {
        self = Self.fromMap(map)
    }

    static func fromJson(_ jsonString: String) throws -> Self {
        try fromJsonString(jsonString)
    }

    static func fromJsonString(_ jsonString: String) throws -> Self {
        Self.fromMap(try skillObjectMap(from: jsonString))
    }

    static func fromMap(_ map: [String: NapaxiJSONValue]) -> Self {
        Self(raw: map)
    }

    var runId: String { skillString("run_id", "runId") ?? "" }
    var agentId: String { skillString("agent_id", "agentId") ?? "" }
    var skillName: String { skillString("skill_name", "skillName") ?? "" }
    var actionId: String { skillString("action_id", "actionId") ?? "" }
    var status: String { skillString("status") ?? "" }
    var requestedAt: String { skillString("requested_at", "requestedAt") ?? "" }
    var updatedAt: String { skillString("updated_at", "updatedAt") ?? "" }
    var result: [String: NapaxiJSONValue]? { raw.object("result") }
}

public extension NapaxiStableModel where Tag == NapaxiSkillStatusReportTag {
    var entries: [NapaxiSkillStatusEntry] { raw.modelArray("entries") ?? [] }
    var ready: Int { raw.int("ready") ?? 0 }
    var disabled: Int { raw.int("disabled") ?? 0 }
    var blocked: Int { raw.int("blocked") ?? 0 }
    var missingRequirements: Int { raw.int("missing_requirements") ?? raw.int("missingRequirements") ?? 0 }
    var parseError: Int { raw.int("parse_error") ?? raw.int("parseError") ?? 0 }
    var securityBlocked: Int { raw.int("security_blocked") ?? raw.int("securityBlocked") ?? 0 }
    var tooLarge: Int { raw.int("too_large") ?? raw.int("tooLarge") ?? 0 }
    var topBlockers: [NapaxiSkillStatusEntry] { raw.modelArray("top_blockers") ?? raw.modelArray("topBlockers") ?? [] }
}

public extension NapaxiStableModel where Tag == NapaxiSkillUsageRecordTag {
    var skillName: String { string("skill_name") ?? string("skillName") ?? "" }
    var createdAt: String? { string("created_at") ?? string("createdAt") }
    var state: String { string("state") ?? "active" }
    var pinned: Bool { bool("pinned") ?? false }
    var createdBy: String? { string("created_by") ?? string("createdBy") }
    var useCount: Int { raw.int("use_count") ?? raw.int("useCount") ?? 0 }
    var viewCount: Int { raw.int("view_count") ?? raw.int("viewCount") ?? 0 }
    var patchCount: Int { raw.int("patch_count") ?? raw.int("patchCount") ?? 0 }
    var lastUsedAt: String? { string("last_used_at") ?? string("lastUsedAt") }
    var lastViewedAt: String? { string("last_viewed_at") ?? string("lastViewedAt") }
    var lastPatchedAt: String? { string("last_patched_at") ?? string("lastPatchedAt") }
    var archivedAt: String? { string("archived_at") ?? string("archivedAt") }
    var absorbedInto: String? { string("absorbed_into") ?? string("absorbedInto") }
}

func validateSkillUsageRecordObject(_ object: [String: NapaxiJSONValue]) throws {
    try object.validateSkillOptionalString("skill_name")
    try object.validateSkillOptionalString("skillName")
    try object.validateSkillOptionalString("created_at")
    try object.validateSkillOptionalString("createdAt")
    try object.validateSkillOptionalString("state")
    try object.validateSkillOptionalBool("pinned")
    try object.validateSkillOptionalString("created_by")
    try object.validateSkillOptionalString("createdBy")
    try object.validateSkillOptionalNumber("use_count")
    try object.validateSkillOptionalNumber("useCount")
    try object.validateSkillOptionalNumber("view_count")
    try object.validateSkillOptionalNumber("viewCount")
    try object.validateSkillOptionalNumber("patch_count")
    try object.validateSkillOptionalNumber("patchCount")
    try object.validateSkillOptionalString("last_used_at")
    try object.validateSkillOptionalString("lastUsedAt")
    try object.validateSkillOptionalString("last_viewed_at")
    try object.validateSkillOptionalString("lastViewedAt")
    try object.validateSkillOptionalString("last_patched_at")
    try object.validateSkillOptionalString("lastPatchedAt")
    try object.validateSkillOptionalString("archived_at")
    try object.validateSkillOptionalString("archivedAt")
    try object.validateSkillOptionalString("absorbed_into")
    try object.validateSkillOptionalString("absorbedInto")
}

public extension NapaxiStableModel where Tag == NapaxiCuratorRunSummaryTag {
    var dryRun: Bool { bool("dry_run") ?? bool("dryRun") ?? true }
    var checked: Int { raw.int("checked") ?? 0 }
    var markedStale: Int { raw.int("marked_stale") ?? raw.int("markedStale") ?? 0 }
    var archived: Int { raw.int("archived") ?? 0 }
    var restoredActive: Int { raw.int("restored_active") ?? raw.int("restoredActive") ?? 0 }
    var protectedSkipped: Int { raw.int("protected_skipped") ?? raw.int("protectedSkipped") ?? 0 }
    var actions: [String] { raw.stringArray("actions") ?? [] }
}

func validateSkillCuratorRunSummaryObject(_ object: [String: NapaxiJSONValue]) throws {
    try object.validateSkillOptionalBool("dry_run")
    try object.validateSkillOptionalBool("dryRun")
    try object.validateSkillOptionalNumber("checked")
    try object.validateSkillOptionalNumber("marked_stale")
    try object.validateSkillOptionalNumber("markedStale")
    try object.validateSkillOptionalNumber("archived")
    try object.validateSkillOptionalNumber("restored_active")
    try object.validateSkillOptionalNumber("restoredActive")
    try object.validateSkillOptionalStringArray("actions")
}

public extension NapaxiStableModel where Tag == NapaxiSkillSupportFileReadResultTag {
    var success: Bool { bool("success") ?? false }
    var skillName: String? { string("skill_name") ?? string("skillName") }
    var filePath: String? { string("file_path") ?? string("filePath") }
    var content: String? { string("content") }
    var error: String? { string("error") }
}

func validateSkillSupportFileReadResultObject(_ object: [String: NapaxiJSONValue]) throws {
    try object.validateSkillOptionalBool("success")
    try object.validateSkillOptionalString("skill_name")
    try object.validateSkillOptionalString("skillName")
    try object.validateSkillOptionalString("file_path")
    try object.validateSkillOptionalString("filePath")
    try object.validateSkillOptionalString("content")
    try object.validateSkillOptionalString("error")
}

public extension NapaxiStableModel where Tag == NapaxiSkillInstallExtraFileTag {
    init(path: String, bytes: Data) {
        self.init(raw: ["path": .string(path), "content_base64": .string(bytes.base64EncodedString())])
    }

    var path: String { string("path") ?? "" }
    var contentBase64: String { string("content_base64") ?? string("contentBase64") ?? "" }
}

public extension NapaxiStableModel where Tag == NapaxiSkillInstallInputTag {
    init(skillMd: String, extraFiles: [NapaxiSkillInstallExtraFile] = []) {
        self.init(raw: [
            "skill_md": .string(skillMd),
            "extra_files": .array(extraFiles.map { .object($0.raw) }),
        ])
    }

    var skillMd: String { string("skill_md") ?? string("skillMd") ?? "" }
    var extraFiles: [NapaxiSkillInstallExtraFile] { raw.modelArray("extra_files") ?? raw.modelArray("extraFiles") ?? [] }

    func installPayloadJSON() throws -> String {
        try jsonString()
    }

    func toInstallPayloadJson() throws -> String {
        try installPayloadJSON()
    }
}

public extension NapaxiStableModel where Tag == NapaxiSkillInstallResultTag {
    var name: String? { error == nil ? string("name") : nil }
    var success: Bool { error == nil ? bool("success") ?? false : false }
    var error: String? { string("error") }
}

func validateSkillInstallResultObject(_ object: [String: NapaxiJSONValue]) throws {
    if object.keys.contains("error") {
        guard case .string? = object["error"] else {
            throw NapaxiError.invalidJSON("Expected skill field 'error' to be a string")
        }
        return
    }
    try object.validateSkillOptionalString("name")
    try object.validateSkillOptionalBool("success")
}

public extension NapaxiStableModel where Tag == NapaxiCatalogSearchResultTag {
    var results: [NapaxiCatalogSkillInfo] { raw.modelArray("results") ?? [] }
    var error: String? { skillString("error") }
}

func normalizedSkillCatalogSearchResultObject(_ object: [String: NapaxiJSONValue]) throws -> [String: NapaxiJSONValue] {
    var normalized = object
    try normalized.normalizeSkillRequiredObjectListOrEmpty("results") { entry in entry }
    return normalized
}

public extension NapaxiStableModel where Tag == NapaxiCatalogPackagePageTag {
    var items: [NapaxiCatalogSkillInfo] { raw.modelArray("items") ?? [] }
    var nextCursor: String? { skillString("nextCursor", "next_cursor") }
    var error: String? { skillString("error") }
}

func normalizedSkillCatalogPackagePageObject(_ object: [String: NapaxiJSONValue]) throws -> [String: NapaxiJSONValue] {
    var normalized = object
    try normalized.normalizeSkillRequiredObjectListOrEmpty("items") { entry in entry }
    return normalized
}

public extension NapaxiStableModel where Tag == NapaxiCatalogSkillInfoTag {
    var slug: String { skillString("slug", "name") ?? "" }
    var name: String { skillString("displayName", "name", "slug") ?? "" }
    var description: String { skillString("description", "summary") ?? "" }
    var version: String { skillString("version") ?? raw.object("latestVersion")?.skillString("version") ?? "" }
    var score: Double { raw.double("score") }
    var stars: Int? { raw.int("stars") ?? raw.object("stats")?.int("stars") }
    var downloads: Int? { raw.int("downloads") ?? raw.object("stats")?.int("downloads") }
    var installsCurrent: Int? { raw.int("installsCurrent") ?? raw.object("stats")?.int("installsCurrent") }
    var installsAllTime: Int? { raw.int("installsAllTime") ?? raw.object("stats")?.int("installsAllTime") }
    var owner: String? { skillString("owner", "ownerHandle") ?? raw.object("owner")?.skillString("handle") }
    var ownerName: String? { skillString("ownerName") ?? raw.object("owner")?.skillString("displayName") }
    var summary: String? { skillString("summary") }
    var tags: [String] {
        let tags = raw.stringArray("tags") ?? []
        return tags.isEmpty ? raw.stringArray("capabilityTags") ?? [] : tags
    }
    var updatedAtMilliseconds: Int? { raw.numberInt("updatedAt") }
}

func decodeSkillCatalogInfo(from value: NapaxiJSONValue) throws -> NapaxiCatalogSkillInfo {
    guard case .object(let object) = value else {
        throw NapaxiError.invalidJSON("Expected skill catalog info object")
    }
    return NapaxiCatalogSkillInfo(raw: object)
}

private func skillObjectMap(from jsonString: String) throws -> [String: NapaxiJSONValue] {
    let value = try NapaxiRawJSON(jsonString: jsonString).value
    guard case .object(let object) = value else {
        throw NapaxiError.invalidJSON("Skill JSON must be an object")
    }
    return object
}

private extension Dictionary where Key == String, Value == NapaxiJSONValue {
    func int(_ key: String) -> Int? {
        guard let value = self[key] else { return nil }
        if let number = value.numberValue { return Int(number) }
        if let string = value.stringValue { return Int(string) }
        return nil
    }

    func numberInt(_ key: String) -> Int? {
        guard let value = self[key], let number = value.numberValue else { return nil }
        return Int(number)
    }

    func double(_ key: String) -> Double {
        guard let value = self[key] else { return 0 }
        if let number = value.numberValue { return number }
        if let string = value.stringValue { return Double(string) ?? 0 }
        return 0
    }

    func object(_ key: String) -> [String: NapaxiJSONValue]? {
        if case .object(let object)? = self[key] {
            return object
        }
        return nil
    }

    func objectArray(_ key: String) -> [[String: NapaxiJSONValue]]? {
        if case .array(let values)? = self[key] {
            return values.compactMap { value in
                if case .object(let object) = value { return object }
                return nil
            }
        }
        return nil
    }

    func stringArray(_ key: String) -> [String]? {
        if case .array(let values)? = self[key] {
            return values.compactMap(\.stringValue)
        }
        return nil
    }

    func skillString(_ key: String) -> String? {
        self[key]?.skillStringValue
    }

    func validateSkillOptionalString(_ key: String) throws {
        guard let value = self[key], value != .null else { return }
        guard case .string = value else {
            throw NapaxiError.invalidJSON("Expected skill field '\(key)' to be a string")
        }
    }

    func validateSkillOptionalBool(_ key: String) throws {
        guard let value = self[key], value != .null else { return }
        guard case .bool = value else {
            throw NapaxiError.invalidJSON("Expected skill field '\(key)' to be a bool")
        }
    }

    func validateSkillOptionalNumber(_ key: String) throws {
        guard let value = self[key], value != .null else { return }
        guard case .number = value else {
            throw NapaxiError.invalidJSON("Expected skill field '\(key)' to be a number")
        }
    }

    func validateSkillOptionalStringArray(_ key: String) throws {
        guard let value = self[key], value != .null else { return }
        guard case .array(let values) = value else {
            throw NapaxiError.invalidJSON("Expected skill field '\(key)' to be an array")
        }
        for item in values {
            guard case .string = item else {
                throw NapaxiError.invalidJSON("Expected skill field '\(key)' to contain strings")
            }
        }
    }

    func validateSkillOptionalArray(_ key: String) throws {
        guard let value = self[key], value != .null else { return }
        guard case .array = value else {
            throw NapaxiError.invalidJSON("Expected skill field '\(key)' to be an array")
        }
    }

    func validateSkillOptionalObject(
        _ key: String,
        _ validate: ([String: NapaxiJSONValue]) throws -> Void
    ) throws {
        guard let value = self[key], value != .null else { return }
        guard case .object(let object) = value else {
            throw NapaxiError.invalidJSON("Expected skill field '\(key)' to be an object")
        }
        try validate(object)
    }

    mutating func normalizeSkillObjectList(
        _ key: String,
        _ normalize: ([String: NapaxiJSONValue]) throws -> [String: NapaxiJSONValue]
    ) throws {
        guard let value = self[key], value != .null else { return }
        guard case .array(let values) = value else {
            throw NapaxiError.invalidJSON("Expected skill field '\(key)' to be an array")
        }
        var objects: [NapaxiJSONValue] = []
        for value in values {
            guard case .object(let object) = value else { continue }
            objects.append(.object(try normalize(object)))
        }
        self[key] = .array(objects)
    }

    mutating func normalizeSkillObjectListOrEmpty(
        _ key: String,
        _ normalize: ([String: NapaxiJSONValue]) throws -> [String: NapaxiJSONValue]
    ) throws {
        guard let value = self[key], value != .null else { return }
        guard case .array(let values) = value else {
            self[key] = .array([])
            return
        }
        var objects: [NapaxiJSONValue] = []
        for value in values {
            guard case .object(let object) = value else { continue }
            objects.append(.object(try normalize(object)))
        }
        self[key] = .array(objects)
    }

    mutating func normalizeSkillRequiredObjectListOrEmpty(
        _ key: String,
        _ normalize: ([String: NapaxiJSONValue]) throws -> [String: NapaxiJSONValue]
    ) throws {
        guard let value = self[key], value != .null else {
            self[key] = .array([])
            return
        }
        guard case .array(let values) = value else {
            throw NapaxiError.invalidJSON("Expected skill field '\(key)' to be an array")
        }
        var objects: [NapaxiJSONValue] = []
        for value in values {
            guard case .object(let object) = value else {
                throw NapaxiError.invalidJSON("Expected skill field '\(key)' to contain objects")
            }
            objects.append(.object(try normalize(object)))
        }
        self[key] = .array(objects)
    }

    mutating func normalizeSkillObjectOrEmptyIfPresent(_ key: String) {
        guard let value = self[key], value != .null else { return }
        guard case .object = value else {
            self[key] = .object([:])
            return
        }
    }

    func model<T: Decodable>(_ key: String) -> T? {
        guard let value = self[key] else { return nil }
        return try? JSONDecoder().decode(T.self, from: JSONEncoder().encode(value))
    }

    func modelArray<T: Decodable>(_ key: String) -> [T]? {
        guard let value = self[key] else { return nil }
        return try? JSONDecoder().decode([T].self, from: JSONEncoder().encode(value))
    }
}

private func validateSkillObjectItems(
    _ values: [NapaxiJSONValue],
    _ validate: ([String: NapaxiJSONValue]) throws -> Void
) throws {
    for value in values {
        guard case .object(let object) = value else { continue }
        try validate(object)
    }
}
