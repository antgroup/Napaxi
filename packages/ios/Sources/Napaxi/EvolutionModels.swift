import Foundation

public extension NapaxiStableString where Tag == NapaxiEvolutionRunStatusTag {
    static let queued = Self(rawValue: "queued")
    static let running = Self(rawValue: "running")
    static let completed = Self(rawValue: "completed")
    static let failed = Self(rawValue: "failed")
    static let unknown = Self(rawValue: "unknown")
}

public extension NapaxiStableModel where Tag == NapaxiEvolutionRunTag {
    var id: String { string("id") ?? "" }
    var agentId: String { string("agent_id") ?? string("agentId") ?? "" }
    var threadId: String { string("thread_id") ?? string("threadId") ?? "" }
    var reviewType: String { string("review_type") ?? string("reviewType") ?? "" }
    var status: NapaxiEvolutionRunStatus {
        let rawStatus = string("status") ?? ""
        switch rawStatus {
        case "queued":
            return .queued
        case "running":
            return .running
        case "completed":
            return .completed
        case "failed":
            return .failed
        default:
            return .unknown
        }
    }
    var queuedAt: String { string("queued_at") ?? string("queuedAt") ?? "" }
    var startedAt: String? { string("started_at") ?? string("startedAt") }
    var completedAt: String? { string("completed_at") ?? string("completedAt") }
    var suggestionsCount: Int { raw.int("suggestions_count") ?? raw.int("suggestionsCount") ?? 0 }
    var autoAppliedCount: Int { raw.int("auto_applied_count") ?? raw.int("autoAppliedCount") ?? 0 }
    var pendingCount: Int { raw.int("pending_count") ?? raw.int("pendingCount") ?? 0 }
    var error: String? { string("error") }
    var isFinished: Bool { status == .completed || status == .failed }
}

public extension NapaxiStableModel where Tag == NapaxiEvolutionDiagnosticTag {
    var id: String { string("id") ?? "" }
    var createdAt: String { string("created_at") ?? string("createdAt") ?? "" }
    var agentId: String { string("agent_id") ?? string("agentId") ?? "" }
    var threadId: String { string("thread_id") ?? string("threadId") ?? "" }
    var reviewType: String { string("review_type") ?? string("reviewType") ?? "" }
    var triggerReason: String { string("trigger_reason") ?? string("triggerReason") ?? "" }
    var inputSummary: [String: NapaxiJSONValue] { raw.object("input_summary") ?? raw.object("inputSummary") ?? [:] }
    var toolCalls: [String] { raw.stringArray("tool_calls") ?? raw.stringArray("toolCalls") ?? [] }
    var suggestionsCount: Int { raw.int("suggestions_count") ?? raw.int("suggestionsCount") ?? 0 }
    var pendingCount: Int { raw.int("pending_count") ?? raw.int("pendingCount") ?? 0 }
    var autoAppliedCount: Int { raw.int("auto_applied_count") ?? raw.int("autoAppliedCount") ?? 0 }
    var applyResult: String? { string("apply_result") ?? string("applyResult") }
    var failureReason: String? { string("failure_reason") ?? string("failureReason") }
}

public extension NapaxiStableModel where Tag == NapaxiSkillConsolidationReviewResultTag {
    var reviewed: Bool { bool("reviewed") ?? false }
    var dryRun: Bool { bool("dry_run") ?? bool("dryRun") ?? true }
    var suggestionsCount: Int { raw.int("suggestions_count") ?? raw.int("suggestionsCount") ?? 0 }
    var pendingCount: Int { raw.int("pending_count") ?? raw.int("pendingCount") ?? 0 }
    var pendingId: String? { string("pending_id") ?? string("pendingId") }
    var actions: [[String: NapaxiJSONValue]] { raw.objectArray("actions") ?? [] }
    var warnings: [String] { raw.stringArray("warnings") ?? [] }
    var error: String? { string("error") }
}

func validateEvolutionRunObject(_ object: [String: NapaxiJSONValue]) throws {
    _ = try object.requiredEvolutionString("id")
    _ = try object.requiredEvolutionString("agent_id")
    _ = try object.requiredEvolutionString("thread_id")
    _ = try object.requiredEvolutionString("review_type")
    try object.validateEvolutionOptionalString("status")
    try object.validateEvolutionRequiredDateString("queued_at")
    try object.validateEvolutionOptionalInt("suggestions_count")
    try object.validateEvolutionOptionalInt("auto_applied_count")
    try object.validateEvolutionOptionalInt("pending_count")
    try object.validateEvolutionOptionalString("error")
}

func validateEvolutionDiagnosticObject(_ object: [String: NapaxiJSONValue]) throws {
    try object.validateEvolutionOptionalString("id")
    try object.validateEvolutionRequiredDateString("created_at")
    try object.validateEvolutionOptionalString("agent_id")
    try object.validateEvolutionOptionalString("thread_id")
    try object.validateEvolutionOptionalString("review_type")
    try object.validateEvolutionOptionalString("trigger_reason")
    try object.validateEvolutionObjectOrNull("input_summary")
    try object.validateEvolutionStringArrayOrNull("tool_calls")
    try object.validateEvolutionOptionalInt("suggestions_count")
    try object.validateEvolutionOptionalInt("pending_count")
    try object.validateEvolutionOptionalInt("auto_applied_count")
    try object.validateEvolutionOptionalString("apply_result")
    try object.validateEvolutionOptionalString("failure_reason")
}

private extension Dictionary where Key == String, Value == NapaxiJSONValue {
    func requiredEvolutionString(_ key: String) throws -> String {
        guard case .string(let value)? = self[key] else {
            throw NapaxiError.invalidJSON("Expected evolution field '\(key)' to be a string")
        }
        return value
    }

    func validateEvolutionOptionalString(_ key: String) throws {
        guard let value = self[key], value != .null else { return }
        guard case .string = value else {
            throw NapaxiError.invalidJSON("Expected evolution field '\(key)' to be a string")
        }
    }

    func validateEvolutionRequiredDateString(_ key: String) throws {
        let value = try requiredEvolutionString(key)
        guard isValidEvolutionDateString(value) else {
            throw NapaxiError.invalidJSON("Expected evolution field '\(key)' to be an ISO-8601 date string")
        }
    }

    func validateEvolutionOptionalInt(_ key: String) throws {
        guard let value = self[key], value != .null else { return }
        guard case .number(let number) = value,
              number.isFinite,
              number.rounded(.towardZero) == number
        else {
            throw NapaxiError.invalidJSON("Expected evolution field '\(key)' to be an integer")
        }
    }

    func validateEvolutionObjectOrNull(_ key: String) throws {
        guard let value = self[key], value != .null else { return }
        guard case .object = value else {
            throw NapaxiError.invalidJSON("Expected evolution field '\(key)' to be an object")
        }
    }

    func validateEvolutionStringArrayOrNull(_ key: String) throws {
        guard let value = self[key], value != .null else { return }
        guard case .array(let values) = value else {
            throw NapaxiError.invalidJSON("Expected evolution field '\(key)' to be an array")
        }
        for item in values {
            guard case .string = item else {
                throw NapaxiError.invalidJSON("Expected evolution field '\(key)' to contain strings")
            }
        }
    }

    func isValidEvolutionDateString(_ value: String) -> Bool {
        guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }

        let formatter = ISO8601DateFormatter()
        if formatter.date(from: value) != nil {
            return true
        }

        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: value) != nil
    }

    func int(_ key: String) -> Int? {
        guard case .number(let value)? = self[key], value.isFinite else { return nil }
        let integer = value.rounded(.towardZero)
        guard integer == value else { return nil }
        return Int(integer)
    }

    func object(_ key: String) -> [String: NapaxiJSONValue]? {
        guard case .object(let object)? = self[key] else { return nil }
        return object
    }

    func objectArray(_ key: String) -> [[String: NapaxiJSONValue]]? {
        guard case .array(let values)? = self[key] else { return nil }
        return values.compactMap { value in
            guard case .object(let object) = value else { return nil }
            return object
        }
    }

    func stringArray(_ key: String) -> [String]? {
        guard case .array(let values)? = self[key] else { return nil }
        return values.compactMap(\.stringValue)
    }
}
