import Foundation

public extension NapaxiStableString where Tag == NapaxiSessionRunRecordStatusTag {
    static let running: Self = "running"
    static let succeeded: Self = "succeeded"
    static let failed: Self = "failed"
    static let cancelled: Self = "cancelled"
    static let stalled: Self = "stalled"
    static let lost: Self = "lost"
    static let unverified: Self = "unverified"
    static let unknown: Self = "unknown"

    var wireName: String { rawValue }

    static func fromWire(_ value: String?) -> Self {
        switch value {
        case Self.running.rawValue: .running
        case Self.succeeded.rawValue: .succeeded
        case Self.failed.rawValue: .failed
        case Self.cancelled.rawValue: .cancelled
        case Self.stalled.rawValue: .stalled
        case Self.lost.rawValue: .lost
        case Self.unverified.rawValue: .unverified
        default: .unknown
        }
    }
}

public extension NapaxiStableString where Tag == NapaxiRunEvidenceKindTag {
    static let replyOnly: Self = "reply_only"
    static let toolObserved: Self = "tool_observed"
    static let sideEffectObserved: Self = "side_effect_observed"
    static let detachedTaskObserved: Self = "detached_task_observed"
    static let unknown: Self = "unknown"

    var wireName: String { rawValue }

    static func fromWire(_ value: String?) -> Self {
        switch value {
        case Self.replyOnly.rawValue: .replyOnly
        case Self.toolObserved.rawValue: .toolObserved
        case Self.sideEffectObserved.rawValue: .sideEffectObserved
        case Self.detachedTaskObserved.rawValue: .detachedTaskObserved
        default: .unknown
        }
    }
}

public extension NapaxiStableString where Tag == NapaxiRunVerificationTag {
    static let notRequired: Self = "not_required"
    static let verified: Self = "verified"
    static let unverified: Self = "unverified"
    static let failed: Self = "failed"
    static let unknown: Self = "unknown"

    var wireName: String { rawValue }

    static func fromWire(_ value: String?) -> Self {
        switch value {
        case Self.notRequired.rawValue: .notRequired
        case Self.verified.rawValue: .verified
        case Self.unverified.rawValue: .unverified
        case Self.failed.rawValue: .failed
        default: .unknown
        }
    }
}

public extension NapaxiStableModel where Tag == NapaxiRunEvidenceTag {
    init(
        kind: NapaxiRunEvidenceKind,
        source: String,
        effect: String? = nil,
        isError: Bool = false,
        digest: String? = nil
    ) {
        var raw: [String: NapaxiJSONValue] = [
            "kind": .string(kind.rawValue),
            "source": .string(source),
            "isError": .bool(isError),
        ]
        if let effect { raw["effect"] = .string(effect) }
        if let digest { raw["digest"] = .string(digest) }
        self.init(raw: raw)
    }

    var kind: NapaxiRunEvidenceKind { NapaxiRunEvidenceKind.fromWire(string("kind")) }
    var source: String { string("source") ?? "" }
    var effect: String? { string("effect") }
    var isError: Bool { bool("isError") ?? bool("is_error") ?? false }
    var digest: String? { string("digest") }
}

public extension NapaxiStableModel where Tag == NapaxiSessionRunRecordTag {
    init(
        runId: String,
        status: NapaxiSessionRunRecordStatus,
        agentId: String,
        sessionKey: String,
        threadId: String,
        startedAt: Int,
        completedAt: Int? = nil,
        durationMs: Int? = nil,
        evidenceKind: NapaxiRunEvidenceKind,
        verification: NapaxiRunVerification,
        toolCallCount: Int = 0,
        evidence: [NapaxiRunEvidence] = [],
        summary: String? = nil,
        error: String? = nil,
        parentRunId: String? = nil,
        childRunIds: [String] = []
    ) {
        var raw: [String: NapaxiJSONValue] = [
            "runId": .string(runId),
            "status": .string(status.rawValue),
            "agentId": .string(agentId),
            "sessionKey": .string(sessionKey),
            "threadId": .string(threadId),
            "startedAt": .number(Double(startedAt)),
            "evidenceKind": .string(evidenceKind.rawValue),
            "verification": .string(verification.rawValue),
            "toolCallCount": .number(Double(toolCallCount)),
            "evidence": .array(evidence.map { .object($0.raw) }),
        ]
        if let completedAt { raw["completedAt"] = .number(Double(completedAt)) }
        if let durationMs { raw["durationMs"] = .number(Double(durationMs)) }
        if let summary { raw["summary"] = .string(summary) }
        if let error { raw["error"] = .string(error) }
        if let parentRunId { raw["parentRunId"] = .string(parentRunId) }
        if !childRunIds.isEmpty { raw["childRunIds"] = .array(childRunIds.map { .string($0) }) }
        self.init(raw: raw)
    }

    var runId: String { string("runId") ?? string("run_id") ?? "" }
    var status: NapaxiSessionRunRecordStatus { NapaxiSessionRunRecordStatus.fromWire(string("status")) }
    var agentId: String { string("agentId") ?? string("agent_id") ?? "" }
    var sessionKey: String { string("sessionKey") ?? string("session_key") ?? "" }
    var threadId: String { string("threadId") ?? string("thread_id") ?? "" }
    var startedAt: Int { raw.int("startedAt") ?? raw.int("started_at") ?? 0 }
    var completedAt: Int? { raw.int("completedAt") ?? raw.int("completed_at") }
    var durationMs: Int? { raw.int("durationMs") ?? raw.int("duration_ms") }
    var evidenceKind: NapaxiRunEvidenceKind {
        NapaxiRunEvidenceKind.fromWire(string("evidenceKind") ?? string("evidence_kind"))
    }
    var verification: NapaxiRunVerification { NapaxiRunVerification.fromWire(string("verification")) }
    var toolCallCount: Int { raw.int("toolCallCount") ?? raw.int("tool_call_count") ?? 0 }
    var evidence: [NapaxiRunEvidence] { raw.modelArray("evidence") ?? [] }
    var summary: String? { string("summary") }
    var error: String? { string("error") }
    var parentRunId: String? { string("parentRunId") ?? string("parent_run_id") }
    var childRunIds: [String] { raw.stringArray("childRunIds") ?? raw.stringArray("child_run_ids") ?? [] }
}

public func decodeSessionRunRecords(_ raw: String) throws -> [NapaxiSessionRunRecord] {
    let value = try NapaxiRawJSON(jsonString: raw).value
    guard case .array = value else { return [] }
    return try decodeJsonObjectListFromValue(value) { object in
        NapaxiSessionRunRecord(raw: object)
    }
}

private extension Dictionary where Key == String, Value == NapaxiJSONValue {
    func int(_ key: String) -> Int? {
        guard let value = self[key] else { return nil }
        if let number = value.numberValue { return Int(number) }
        if let string = value.stringValue { return Int(string) }
        return nil
    }

    func stringArray(_ key: String) -> [String]? {
        if case .array(let values)? = self[key] {
            return values.compactMap(\.stringValue)
        }
        return nil
    }

    func modelArray<T: Decodable>(_ key: String) -> [T]? {
        guard let value = self[key] else { return nil }
        return try? JSONDecoder().decode([T].self, from: JSONEncoder().encode(value))
    }
}
