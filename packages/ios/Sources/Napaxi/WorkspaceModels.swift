import Foundation

public extension NapaxiStableModel where Tag == NapaxiWorkspaceFileTag {
    init(map: [String: NapaxiJSONValue]) {
        self = Self.fromMap(map)
    }

    static func fromMap(_ map: [String: NapaxiJSONValue]) -> Self {
        Self(raw: map)
    }

    static func fromJson(_ jsonString: String) throws -> Self {
        try fromJsonString(jsonString)
    }

    static func fromJsonString(_ jsonString: String) throws -> Self {
        let object = try workspaceObjectMap(from: jsonString)
        try validateWorkspaceFileObject(object)
        return Self(raw: object)
    }

    func toMap() -> [String: NapaxiJSONValue] {
        raw
    }

    var path: String { string("path") ?? "" }
    var content: String { string("content") ?? "" }
    var updatedAt: Date? { raw.date("updatedAt") ?? raw.date("updated_at") }
}

public extension NapaxiStableModel where Tag == NapaxiWorkspaceEntryTag {
    init(map: [String: NapaxiJSONValue]) {
        self = Self.fromMap(map)
    }

    static func fromMap(_ map: [String: NapaxiJSONValue]) -> Self {
        Self(raw: map)
    }

    func toMap() -> [String: NapaxiJSONValue] {
        raw
    }

    var path: String { string("path") ?? "" }
    var isDirectory: Bool { bool("isDirectory") ?? bool("is_directory") ?? false }
    var updatedAt: Date? { raw.date("updatedAt") ?? raw.date("updated_at") }
    var preview: String? { string("preview") }
    var name: String { path.split(separator: "/").last.map(String.init) ?? path }
}

public extension NapaxiStableModel where Tag == NapaxiMemorySearchResultTag {
    init(map: [String: NapaxiJSONValue]) {
        self = Self.fromMap(map)
    }

    static func fromMap(_ map: [String: NapaxiJSONValue]) -> Self {
        Self(raw: map)
    }

    func toMap() -> [String: NapaxiJSONValue] {
        raw
    }

    var source: String { string("source") ?? "" }
    var path: String { string("path") ?? "" }
    var content: String { string("content") ?? "" }
    var score: Double { raw.numericDouble("score") ?? 0 }
    var isHybridMatch: Bool { bool("isHybridMatch") ?? bool("is_hybrid_match") ?? false }
    var updatedAt: Date? { raw.date("updatedAt") ?? raw.date("updated_at") }
    var threadId: String? { raw.nonEmptyString("threadId", "thread_id") }
    var turnId: String? { raw.nonEmptyString("turnId", "turn_id") }
    var createdAt: Date? { raw.date("createdAt") ?? raw.date("created_at") }
}

public extension NapaxiStableModel where Tag == NapaxiMemoryRecallSnippetTag {
    init(map: [String: NapaxiJSONValue]) {
        self = Self.fromMap(map)
    }

    static func fromMap(_ map: [String: NapaxiJSONValue]) -> Self {
        Self(raw: map)
    }

    func toMap() -> [String: NapaxiJSONValue] {
        raw
    }

    var source: String { string("source") ?? "" }
    var path: String { string("path") ?? "" }
    var content: String { string("content") ?? "" }
    var score: Double { raw.numericDouble("score") ?? 0 }
    var turnId: String? { raw.nonEmptyString("turnId", "turn_id") }
    var createdAt: Date? { raw.date("createdAt") ?? raw.date("created_at") }
}

public extension NapaxiStableModel where Tag == NapaxiMemoryRecallSessionTag {
    init(map: [String: NapaxiJSONValue]) {
        self = Self.fromMap(map)
    }

    static func fromMap(_ map: [String: NapaxiJSONValue]) -> Self {
        Self(raw: map)
    }

    func toMap() -> [String: NapaxiJSONValue] {
        raw
    }

    var threadId: String { raw.nonEmptyString("threadId", "thread_id") ?? "" }
    var title: String { string("title") ?? "" }
    var summary: String { string("summary") ?? "" }
    var snippets: [NapaxiMemoryRecallSnippet] { raw.modelArray("snippets") ?? [] }
    var score: Double { raw.numericDouble("score") ?? 0 }
    var source: String { string("source") ?? "" }
    var startedAt: Date? { raw.date("startedAt") ?? raw.date("started_at") }
    var lastActiveAt: Date? { raw.date("lastActiveAt") ?? raw.date("last_active_at") }
    var cached: Bool { bool("cached") ?? false }
    var fallback: Bool { bool("fallback") ?? false }
    var sourceDocIds: [String] { raw.stringArray("sourceDocIds") ?? raw.stringArray("source_doc_ids") ?? [] }
    var systemNote: String { raw.nonEmptyString("systemNote", "system_note") ?? "" }
    var sourceHash: String { raw.nonEmptyString("sourceHash", "source_hash") ?? "" }
}

public extension NapaxiStableModel where Tag == NapaxiRecallIndexStatsTag {
    init(map: [String: NapaxiJSONValue]) {
        self = Self.fromMap(map)
    }

    static func fromMap(_ map: [String: NapaxiJSONValue]) -> Self {
        Self(raw: map)
    }

    func toMap() -> [String: NapaxiJSONValue] {
        raw
    }

    var status: String { string("status") ?? "" }
    var dbPath: String { raw.nonEmptyString("dbPath", "db_path") ?? "" }
    var schemaVersion: Int { raw.numericInt("schemaVersion") ?? raw.numericInt("schema_version") ?? 0 }
    var indexedDocs: Int { raw.numericInt("indexedDocs") ?? raw.numericInt("indexed_docs") ?? 0 }
    var memoryDocs: Int { raw.numericInt("memoryDocs") ?? raw.numericInt("memory_docs") ?? 0 }
    var journalDocs: Int { raw.numericInt("journalDocs") ?? raw.numericInt("journal_docs") ?? 0 }
    var legacyDailyDocs: Int { raw.numericInt("legacyDailyDocs") ?? raw.numericInt("legacy_daily_docs") ?? 0 }
    var cachedSummaries: Int { raw.numericInt("cachedSummaries") ?? raw.numericInt("cached_summaries") ?? 0 }
    var lastRebuildAt: Date? { raw.date("lastRebuildAt") ?? raw.date("last_rebuild_at") }
}

public extension NapaxiStableModel where Tag == NapaxiJournalDayTag {
    init(map: [String: NapaxiJSONValue]) {
        self = Self.fromMap(map)
    }

    static func fromMap(_ map: [String: NapaxiJSONValue]) -> Self {
        Self(raw: map)
    }

    func toMap() -> [String: NapaxiJSONValue] {
        raw
    }

    var date: String { string("date") ?? "" }
    var path: String { string("path") ?? "" }
    var turnCount: Int { raw.numericInt("turnCount") ?? raw.numericInt("turn_count") ?? 0 }
    var updatedAt: Date? { raw.date("updatedAt") ?? raw.date("updated_at") }
    var legacy: Bool { bool("legacy") ?? false }
}

public extension NapaxiStableModel where Tag == NapaxiJournalTurnRecordTag {
    init(map: [String: NapaxiJSONValue]) {
        self = Self.fromMap(map)
    }

    static func fromMap(_ map: [String: NapaxiJSONValue]) -> Self {
        Self(raw: map)
    }

    func toMap() -> [String: NapaxiJSONValue] {
        raw
    }

    var turnId: String { string("turnId") ?? string("turn_id") ?? "" }
    var createdAt: Date? { raw.date("createdAt") ?? raw.date("created_at") }
    var agentId: String { string("agentId") ?? string("agent_id") ?? "" }
    var threadId: String { string("threadId") ?? string("thread_id") ?? "" }
    var user: String { string("user") ?? "" }
    var assistant: String { string("assistant") ?? "" }
    var kind: String { string("kind") ?? "turn" }
}

public extension NapaxiStableModel where Tag == NapaxiWorkspacePathsTag {
    static var soul: String { "SOUL.md" }
    static var identity: String { "IDENTITY.md" }
    static var agents: String { "AGENTS.md" }
    static var user: String { "USER.md" }
    static var memory: String { "MEMORY.md" }
    static var project: String { "PROJECT.md" }
    static var heartbeat: String { "HEARTBEAT.md" }
    static var tools: String { "TOOLS.md" }
    static var bootstrap: String { "BOOTSTRAP.md" }
    static var profile: String { "context/profile.json" }
    static var dailyDir: String { "daily/" }
}

func validateWorkspaceFileObject(_ object: [String: NapaxiJSONValue]) throws {
    try object.validateWorkspaceOptionalString("path")
    try object.validateWorkspaceOptionalString("content")
    try object.validateWorkspaceOptionalString("updatedAt")
    try object.validateWorkspaceOptionalString("updated_at")
}

func validateWorkspaceEntryObject(_ object: [String: NapaxiJSONValue]) throws {
    try object.validateWorkspaceOptionalString("path")
    try object.validateWorkspaceOptionalBool("isDirectory")
    try object.validateWorkspaceOptionalBool("is_directory")
    try object.validateWorkspaceOptionalString("updatedAt")
    try object.validateWorkspaceOptionalString("updated_at")
    try object.validateWorkspaceOptionalString("preview")
}

private func workspaceObjectMap(from jsonString: String) throws -> [String: NapaxiJSONValue] {
    let value = try NapaxiRawJSON(jsonString: jsonString).value
    guard case .object(let object) = value else {
        throw NapaxiError.invalidJSON("Workspace JSON must be an object")
    }
    return object
}

private extension Dictionary where Key == String, Value == NapaxiJSONValue {
    func numericInt(_ key: String) -> Int? {
        guard case .number(let number)? = self[key] else { return nil }
        return Int(number)
    }

    func numericDouble(_ key: String) -> Double? {
        guard case .number(let number)? = self[key] else { return nil }
        return number
    }

    func nonEmptyString(_ keys: String...) -> String? {
        for key in keys {
            if let value = self[key]?.stringValue, !value.isEmpty {
                return value
            }
        }
        return nil
    }

    func date(_ key: String) -> Date? {
        guard let string = self[key]?.stringValue else { return nil }
        return ISO8601DateFormatter.napaxiWorkspaceFormatter.date(from: string)
            ?? ISO8601DateFormatter.napaxiWorkspaceFormatterNoFraction.date(from: string)
    }

    func stringArray(_ key: String) -> [String]? {
        if case .array(let values)? = self[key] {
            return values.map(\.jsonCodecDisplayString)
        }
        return nil
    }

    func modelArray<T: Decodable>(_ key: String) -> [T]? {
        guard let value = self[key] else { return nil }
        return try? JSONDecoder().decode([T].self, from: JSONEncoder().encode(value))
    }

    func validateWorkspaceOptionalString(_ key: String) throws {
        guard let value = self[key], value != .null else { return }
        guard case .string = value else {
            throw NapaxiError.invalidJSON("Expected workspace field '\(key)' to be a string")
        }
    }

    func validateWorkspaceOptionalBool(_ key: String) throws {
        guard let value = self[key], value != .null else { return }
        guard case .bool = value else {
            throw NapaxiError.invalidJSON("Expected workspace field '\(key)' to be a bool")
        }
    }
}

private extension ISO8601DateFormatter {
    static let napaxiWorkspaceFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    static let napaxiWorkspaceFormatterNoFraction: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
}
