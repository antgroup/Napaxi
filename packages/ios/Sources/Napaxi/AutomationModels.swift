import Foundation

public struct NapaxiAutomationTrigger: Codable, Equatable, Sendable {
    public var kind: String
    public var atMs: Int?
    public var timezone: String?
    public var hour: Int?
    public var minute: Int?
    public var daysOfWeek: [Int]?
    public var everyMs: Int?
    public var anchorMs: Int?
    public var eventType: String?
    public var source: String?

    private init(
        kind: String,
        atMs: Int? = nil,
        timezone: String? = nil,
        hour: Int? = nil,
        minute: Int? = nil,
        daysOfWeek: [Int]? = nil,
        everyMs: Int? = nil,
        anchorMs: Int? = nil,
        eventType: String? = nil,
        source: String? = nil
    ) {
        self.kind = kind
        self.atMs = atMs
        self.timezone = timezone
        self.hour = hour
        self.minute = minute
        self.daysOfWeek = daysOfWeek
        self.everyMs = everyMs
        self.anchorMs = anchorMs
        self.eventType = eventType
        self.source = source
    }

    public static func oneShotAt(atMs: Int, timezone: String? = nil) -> Self {
        Self(kind: "oneShotAt", atMs: atMs, timezone: timezone)
    }

    public static func localTime(
        hour: Int,
        minute: Int,
        timezone: String,
        daysOfWeek: [Int]? = nil
    ) -> Self {
        Self(kind: "localTime", timezone: timezone, hour: hour, minute: minute, daysOfWeek: daysOfWeek)
    }

    public static func interval(everyMs: Int, anchorMs: Int? = nil) -> Self {
        Self(kind: "interval", everyMs: everyMs, anchorMs: anchorMs)
    }

    public static func manual() -> Self {
        Self(kind: "manual")
    }

    public static func hostEvent(eventType: String, source: String? = nil) -> Self {
        Self(kind: "hostEvent", eventType: eventType, source: source)
    }

    public init(json: [String: NapaxiJSONValue]) {
        self = Self.fromJson(json)
    }

    public static func fromJson(_ json: [String: NapaxiJSONValue]) -> Self {
        let object = NapaxiAutomationJSONObject(values: json)
        return Self(
            kind: object.string("kind") ?? "manual",
            atMs: object.int("atMs", "at_ms"),
            timezone: object.string("timezone"),
            hour: object.int("hour"),
            minute: object.int("minute"),
            daysOfWeek: object.intArray("daysOfWeek", "days_of_week"),
            everyMs: object.int("everyMs", "every_ms"),
            anchorMs: object.int("anchorMs", "anchor_ms"),
            eventType: object.string("eventType", "event_type"),
            source: object.string("source")
        )
    }

    public func toJson() -> [String: NapaxiJSONValue] {
        var json: [String: NapaxiJSONValue] = ["kind": .string(kind)]
        json.setInt("atMs", atMs)
        json.setString("timezone", timezone)
        json.setInt("hour", hour)
        json.setInt("minute", minute)
        if let daysOfWeek {
            json["daysOfWeek"] = .array(daysOfWeek.map { .number(Double($0)) })
        }
        json.setInt("everyMs", everyMs)
        json.setInt("anchorMs", anchorMs)
        json.setString("eventType", eventType)
        json.setString("source", source)
        return json
    }

    public init(from decoder: Decoder) throws {
        let object = try NapaxiAutomationJSONObject(decoder: decoder)
        self = Self.fromJson(object.values)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: NapaxiAutomationCodingKey.self)
        try container.encode(kind, forKey: "kind")
        try container.encodeIfPresent(atMs, forKey: "atMs")
        try container.encodeIfPresent(timezone, forKey: "timezone")
        try container.encodeIfPresent(hour, forKey: "hour")
        try container.encodeIfPresent(minute, forKey: "minute")
        try container.encodeIfPresent(daysOfWeek, forKey: "daysOfWeek")
        try container.encodeIfPresent(everyMs, forKey: "everyMs")
        try container.encodeIfPresent(anchorMs, forKey: "anchorMs")
        try container.encodeIfPresent(eventType, forKey: "eventType")
        try container.encodeIfPresent(source, forKey: "source")
    }
}

public struct NapaxiAutomationPayload: Codable, Equatable, Sendable {
    public var kind: String
    public var text: String?
    public var sessionKeyJSON: String?
    public var wakeMode: String?
    public var message: String?
    public var sessionMode: String?
    public var modelProfileId: String?
    public var maxIterations: Int?

    public var sessionKeyJson: String? {
        get { sessionKeyJSON }
        set { sessionKeyJSON = newValue }
    }

    private init(
        kind: String,
        text: String? = nil,
        sessionKeyJSON: String? = nil,
        wakeMode: String? = nil,
        message: String? = nil,
        sessionMode: String? = nil,
        modelProfileId: String? = nil,
        maxIterations: Int? = nil
    ) {
        self.kind = kind
        self.text = text
        self.sessionKeyJSON = sessionKeyJSON
        self.wakeMode = wakeMode
        self.message = message
        self.sessionMode = sessionMode
        self.modelProfileId = modelProfileId
        self.maxIterations = maxIterations
    }

    public static func systemEvent(
        text: String,
        sessionKeyJSON: String? = nil,
        wakeMode: String = "next_foreground_or_host_wake"
    ) -> Self {
        Self(kind: "systemEvent", text: text, sessionKeyJSON: sessionKeyJSON, wakeMode: wakeMode)
    }

    public static func agentTurn(
        message: String,
        sessionMode: String = "isolated",
        modelProfileId: String? = nil,
        maxIterations: Int? = nil
    ) -> Self {
        Self(
            kind: "agentTurn",
            message: message,
            sessionMode: sessionMode,
            modelProfileId: modelProfileId,
            maxIterations: maxIterations
        )
    }

    public init(json: [String: NapaxiJSONValue]) {
        self = Self.fromJson(json)
    }

    public static func fromJson(_ json: [String: NapaxiJSONValue]) -> Self {
        let object = NapaxiAutomationJSONObject(values: json)
        return Self(
            kind: object.string("kind") ?? "systemEvent",
            text: object.string("text"),
            sessionKeyJSON: object.string("sessionKey", "session_key"),
            wakeMode: object.string("wakeMode", "wake_mode") ?? "next_foreground_or_host_wake",
            message: object.string("message"),
            sessionMode: object.string("sessionMode", "session_mode") ?? "isolated",
            modelProfileId: object.string("modelProfileId", "model_profile_id"),
            maxIterations: object.int("maxIterations", "max_iterations")
        )
    }

    public func toJson() -> [String: NapaxiJSONValue] {
        var json: [String: NapaxiJSONValue] = ["kind": .string(kind)]
        json.setString("text", text)
        json.setString("sessionKey", sessionKeyJSON)
        json.setString("wakeMode", wakeMode)
        json.setString("message", message)
        json.setString("sessionMode", sessionMode)
        json.setString("modelProfileId", modelProfileId)
        json.setInt("maxIterations", maxIterations)
        return json
    }

    public init(from decoder: Decoder) throws {
        let object = try NapaxiAutomationJSONObject(decoder: decoder)
        self = Self.fromJson(object.values)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: NapaxiAutomationCodingKey.self)
        try container.encode(kind, forKey: "kind")
        try container.encodeIfPresent(text, forKey: "text")
        try container.encodeIfPresent(sessionKeyJSON, forKey: "sessionKey")
        try container.encodeIfPresent(wakeMode, forKey: "wakeMode")
        try container.encodeIfPresent(message, forKey: "message")
        try container.encodeIfPresent(sessionMode, forKey: "sessionMode")
        try container.encodeIfPresent(modelProfileId, forKey: "modelProfileId")
        try container.encodeIfPresent(maxIterations, forKey: "maxIterations")
    }
}

public struct NapaxiAutomationPolicy: Codable, Equatable, Sendable {
    public var requiresUserVisibleNotification: Bool
    public var allowHighRiskTools: Bool
    public var maxRunDurationMs: Int
    public var maxRetries: Int
    public var retryBackoffMs: [Int]
    public var deleteAfterSuccess: Bool?

    public init(
        requiresUserVisibleNotification: Bool = true,
        allowHighRiskTools: Bool = false,
        maxRunDurationMs: Int = 600_000,
        maxRetries: Int = 2,
        retryBackoffMs: [Int] = [30_000, 300_000],
        deleteAfterSuccess: Bool? = nil
    ) {
        self.requiresUserVisibleNotification = requiresUserVisibleNotification
        self.allowHighRiskTools = allowHighRiskTools
        self.maxRunDurationMs = maxRunDurationMs
        self.maxRetries = maxRetries
        self.retryBackoffMs = retryBackoffMs
        self.deleteAfterSuccess = deleteAfterSuccess
    }

    public init(json: [String: NapaxiJSONValue]) {
        self = Self.fromJson(json)
    }

    public static func fromJson(_ json: [String: NapaxiJSONValue]) -> Self {
        let object = NapaxiAutomationJSONObject(values: json)
        return Self(
            requiresUserVisibleNotification: object.bool("requiresUserVisibleNotification", "requires_user_visible_notification") ?? true,
            allowHighRiskTools: object.bool("allowHighRiskTools", "allow_high_risk_tools") ?? false,
            maxRunDurationMs: object.int("maxRunDurationMs", "max_run_duration_ms") ?? 600_000,
            maxRetries: object.int("maxRetries", "max_retries") ?? 2,
            retryBackoffMs: object.intArray("retryBackoffMs", "retry_backoff_ms") ?? [30_000, 300_000],
            deleteAfterSuccess: object.bool("deleteAfterSuccess", "delete_after_success")
        )
    }

    public func toJson() -> [String: NapaxiJSONValue] {
        var json: [String: NapaxiJSONValue] = [
            "requiresUserVisibleNotification": .bool(requiresUserVisibleNotification),
            "allowHighRiskTools": .bool(allowHighRiskTools),
            "maxRunDurationMs": .number(Double(maxRunDurationMs)),
            "maxRetries": .number(Double(maxRetries)),
            "retryBackoffMs": .array(retryBackoffMs.map { .number(Double($0)) }),
        ]
        json.setBool("deleteAfterSuccess", deleteAfterSuccess)
        return json
    }

    public init(from decoder: Decoder) throws {
        let object = try NapaxiAutomationJSONObject(decoder: decoder)
        self = Self.fromJson(object.values)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: NapaxiAutomationCodingKey.self)
        try container.encode(requiresUserVisibleNotification, forKey: "requiresUserVisibleNotification")
        try container.encode(allowHighRiskTools, forKey: "allowHighRiskTools")
        try container.encode(maxRunDurationMs, forKey: "maxRunDurationMs")
        try container.encode(maxRetries, forKey: "maxRetries")
        try container.encode(retryBackoffMs, forKey: "retryBackoffMs")
        try container.encodeIfPresent(deleteAfterSuccess, forKey: "deleteAfterSuccess")
    }
}

public struct NapaxiAutomationJobState: Codable, Equatable, Sendable {
    public var nextRunAtMs: Int?
    public var lastRunAtMs: Int?
    public var lastRunStatus: String?
    public var lastError: String?
    public var consecutiveErrors: Int
    public var runningRunId: String?
    public var runningAtMs: Int?
    public var lastWakeSource: String?
    public var lastWakeAtMs: Int?

    public init(
        nextRunAtMs: Int? = nil,
        lastRunAtMs: Int? = nil,
        lastRunStatus: String? = nil,
        lastError: String? = nil,
        consecutiveErrors: Int = 0,
        runningRunId: String? = nil,
        runningAtMs: Int? = nil,
        lastWakeSource: String? = nil,
        lastWakeAtMs: Int? = nil
    ) {
        self.nextRunAtMs = nextRunAtMs
        self.lastRunAtMs = lastRunAtMs
        self.lastRunStatus = lastRunStatus
        self.lastError = lastError
        self.consecutiveErrors = consecutiveErrors
        self.runningRunId = runningRunId
        self.runningAtMs = runningAtMs
        self.lastWakeSource = lastWakeSource
        self.lastWakeAtMs = lastWakeAtMs
    }

    public init(json: [String: NapaxiJSONValue]) {
        self = Self.fromJson(json)
    }

    public static func fromJson(_ json: [String: NapaxiJSONValue]) -> Self {
        let object = NapaxiAutomationJSONObject(values: json)
        return Self(
            nextRunAtMs: object.int("nextRunAtMs", "next_run_at_ms"),
            lastRunAtMs: object.int("lastRunAtMs", "last_run_at_ms"),
            lastRunStatus: object.string("lastRunStatus", "last_run_status"),
            lastError: object.string("lastError", "last_error"),
            consecutiveErrors: object.int("consecutiveErrors", "consecutive_errors") ?? 0,
            runningRunId: object.string("runningRunId", "running_run_id"),
            runningAtMs: object.int("runningAtMs", "running_at_ms"),
            lastWakeSource: object.string("lastWakeSource", "last_wake_source"),
            lastWakeAtMs: object.int("lastWakeAtMs", "last_wake_at_ms")
        )
    }

    public func toJson() -> [String: NapaxiJSONValue] {
        var json: [String: NapaxiJSONValue] = ["consecutiveErrors": .number(Double(consecutiveErrors))]
        json.setInt("nextRunAtMs", nextRunAtMs)
        json.setInt("lastRunAtMs", lastRunAtMs)
        json.setString("lastRunStatus", lastRunStatus)
        json.setString("lastError", lastError)
        json.setString("runningRunId", runningRunId)
        json.setInt("runningAtMs", runningAtMs)
        json.setString("lastWakeSource", lastWakeSource)
        json.setInt("lastWakeAtMs", lastWakeAtMs)
        return json
    }

    public init(from decoder: Decoder) throws {
        let object = try NapaxiAutomationJSONObject(decoder: decoder)
        self = Self.fromJson(object.values)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: NapaxiAutomationCodingKey.self)
        try container.encodeIfPresent(nextRunAtMs, forKey: "nextRunAtMs")
        try container.encodeIfPresent(lastRunAtMs, forKey: "lastRunAtMs")
        try container.encodeIfPresent(lastRunStatus, forKey: "lastRunStatus")
        try container.encodeIfPresent(lastError, forKey: "lastError")
        try container.encode(consecutiveErrors, forKey: "consecutiveErrors")
        try container.encodeIfPresent(runningRunId, forKey: "runningRunId")
        try container.encodeIfPresent(runningAtMs, forKey: "runningAtMs")
        try container.encodeIfPresent(lastWakeSource, forKey: "lastWakeSource")
        try container.encodeIfPresent(lastWakeAtMs, forKey: "lastWakeAtMs")
    }
}

public struct NapaxiAutomationJob: Codable, Equatable, Sendable {
    public var id: String
    public var name: String
    public var enabled: Bool
    public var accountId: String
    public var agentId: String
    public var trigger: NapaxiAutomationTrigger
    public var payload: NapaxiAutomationPayload
    public var policy: NapaxiAutomationPolicy
    public var state: NapaxiAutomationJobState
    public var createdAt: Int
    public var updatedAt: Int

    public init(
        id: String = "",
        name: String,
        enabled: Bool = true,
        accountId: String = "",
        agentId: String = "",
        trigger: NapaxiAutomationTrigger,
        payload: NapaxiAutomationPayload,
        policy: NapaxiAutomationPolicy = NapaxiAutomationPolicy(),
        state: NapaxiAutomationJobState = NapaxiAutomationJobState(),
        createdAt: Int = 0,
        updatedAt: Int = 0
    ) {
        self.id = id
        self.name = name
        self.enabled = enabled
        self.accountId = accountId
        self.agentId = agentId
        self.trigger = trigger
        self.payload = payload
        self.policy = policy
        self.state = state
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    public init(json: [String: NapaxiJSONValue]) {
        self = Self.fromJson(json)
    }

    public static func fromJson(_ json: [String: NapaxiJSONValue]) -> Self {
        let object = NapaxiAutomationJSONObject(values: json)
        return Self(
            id: object.string("id") ?? "",
            name: object.string("name") ?? "",
            enabled: object.bool("enabled") ?? true,
            accountId: object.string("accountId", "account_id") ?? "",
            agentId: object.string("agentId", "agent_id") ?? "",
            trigger: NapaxiAutomationTrigger.fromJson(object.object("trigger") ?? [:]),
            payload: NapaxiAutomationPayload.fromJson(object.object("payload") ?? [:]),
            policy: NapaxiAutomationPolicy.fromJson(object.object("policy") ?? [:]),
            state: NapaxiAutomationJobState.fromJson(object.object("state") ?? [:]),
            createdAt: object.int("createdAt", "created_at") ?? 0,
            updatedAt: object.int("updatedAt", "updated_at") ?? 0
        )
    }

    public func toJson() -> [String: NapaxiJSONValue] {
        var json: [String: NapaxiJSONValue] = [
            "name": .string(name),
            "enabled": .bool(enabled),
            "trigger": .object(trigger.toJson()),
            "payload": .object(payload.toJson()),
            "policy": .object(policy.toJson()),
        ]
        json.setNonEmptyString("id", id)
        json.setNonEmptyString("accountId", accountId)
        json.setNonEmptyString("agentId", agentId)
        if createdAt > 0 { json["createdAt"] = .number(Double(createdAt)) }
        if updatedAt > 0 { json["updatedAt"] = .number(Double(updatedAt)) }
        return json
    }

    public init(from decoder: Decoder) throws {
        let object = try NapaxiAutomationJSONObject(decoder: decoder)
        try object.validateObjectOrNull("trigger", context: "automation job trigger")
        try object.validateObjectOrNull("payload", context: "automation job payload")
        try object.validateObjectOrNull("policy", context: "automation job policy")
        try object.validateObjectOrNull("state", context: "automation job state")
        self = Self.fromJson(object.values)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: NapaxiAutomationCodingKey.self)
        if !id.isEmpty { try container.encode(id, forKey: "id") }
        try container.encode(name, forKey: "name")
        try container.encode(enabled, forKey: "enabled")
        if !accountId.isEmpty { try container.encode(accountId, forKey: "accountId") }
        if !agentId.isEmpty { try container.encode(agentId, forKey: "agentId") }
        try container.encode(trigger, forKey: "trigger")
        try container.encode(payload, forKey: "payload")
        try container.encode(policy, forKey: "policy")
        if createdAt > 0 { try container.encode(createdAt, forKey: "createdAt") }
        if updatedAt > 0 { try container.encode(updatedAt, forKey: "updatedAt") }
    }

    public func jsonString() throws -> String {
        try toJson().jsonString()
    }
}

public struct NapaxiAutomationRun: Codable, Equatable, Sendable {
    public var runId: String
    public var jobId: String
    public var status: String
    public var triggerSource: String
    public var startedAt: Int
    public var completedAt: Int?
    public var durationMs: Int?
    public var sessionKeyJSON: String?
    public var summary: String?
    public var error: String?
    public var toolCallCount: Int
    public var deliveryStatus: String

    public var sessionKeyJson: String? {
        get { sessionKeyJSON }
        set { sessionKeyJSON = newValue }
    }

    public init(
        runId: String,
        jobId: String,
        status: String,
        triggerSource: String,
        startedAt: Int,
        completedAt: Int? = nil,
        durationMs: Int? = nil,
        sessionKeyJSON: String? = nil,
        summary: String? = nil,
        error: String? = nil,
        toolCallCount: Int = 0,
        deliveryStatus: String
    ) {
        self.runId = runId
        self.jobId = jobId
        self.status = status
        self.triggerSource = triggerSource
        self.startedAt = startedAt
        self.completedAt = completedAt
        self.durationMs = durationMs
        self.sessionKeyJSON = sessionKeyJSON
        self.summary = summary
        self.error = error
        self.toolCallCount = toolCallCount
        self.deliveryStatus = deliveryStatus
    }

    public init(json: [String: NapaxiJSONValue]) {
        self = Self.fromJson(json)
    }

    public static func fromJson(_ json: [String: NapaxiJSONValue]) -> Self {
        let object = NapaxiAutomationJSONObject(values: json)
        return Self(
            runId: object.string("runId", "run_id") ?? "",
            jobId: object.string("jobId", "job_id") ?? "",
            status: object.string("status") ?? "",
            triggerSource: object.string("triggerSource", "trigger_source") ?? "",
            startedAt: object.int("startedAt", "started_at") ?? 0,
            completedAt: object.int("completedAt", "completed_at"),
            durationMs: object.int("durationMs", "duration_ms"),
            sessionKeyJSON: object.string("sessionKey", "session_key"),
            summary: object.string("summary"),
            error: object.string("error"),
            toolCallCount: object.int("toolCallCount", "tool_call_count") ?? 0,
            deliveryStatus: object.string("deliveryStatus", "delivery_status") ?? "unknown"
        )
    }

    public init(from decoder: Decoder) throws {
        let object = try NapaxiAutomationJSONObject(decoder: decoder)
        self = Self.fromJson(object.values)
    }
}

public struct NapaxiAutomationWake: Codable, Equatable, Sendable {
    public var jobId: String
    public var atMs: Int
    public var trigger: NapaxiAutomationTrigger

    public init(jobId: String, atMs: Int, trigger: NapaxiAutomationTrigger) {
        self.jobId = jobId
        self.atMs = atMs
        self.trigger = trigger
    }

    public init(json: [String: NapaxiJSONValue]) {
        self = Self.fromJson(json)
    }

    public static func fromJson(_ json: [String: NapaxiJSONValue]) -> Self {
        let object = NapaxiAutomationJSONObject(values: json)
        return Self(
            jobId: object.string("jobId", "job_id") ?? "",
            atMs: object.int("atMs", "at_ms") ?? 0,
            trigger: NapaxiAutomationTrigger.fromJson(object.object("trigger") ?? [:])
        )
    }

    public init(from decoder: Decoder) throws {
        let object = try NapaxiAutomationJSONObject(decoder: decoder)
        try object.validateObjectOrNull("trigger", context: "automation wake trigger")
        self = Self.fromJson(object.values)
    }
}

public func decodeJsonObjectOrNull(_ raw: String) throws -> [String: NapaxiJSONValue]? {
    guard case .object(let object) = try NapaxiRawJSON(jsonString: raw).value,
          object["error"] == nil else {
        return nil
    }
    return object
}

public func decodeAutomationJobs(_ raw: String) throws -> [NapaxiAutomationJob] {
    let value = try NapaxiRawJSON(jsonString: raw).value
    guard case .array = value else { return [] }
    return try decodeJsonObjectListFromValue(value, NapaxiAutomationJob.fromJson)
}

public func decodeAutomationRuns(_ raw: String) throws -> [NapaxiAutomationRun] {
    let value = try NapaxiRawJSON(jsonString: raw).value
    guard case .array = value else { return [] }
    return try decodeJsonObjectListFromValue(value, NapaxiAutomationRun.fromJson)
}

private struct NapaxiAutomationCodingKey: CodingKey {
    var stringValue: String
    var intValue: Int?

    init?(stringValue: String) {
        self.stringValue = stringValue
    }

    init?(intValue: Int) {
        self.stringValue = String(intValue)
        self.intValue = intValue
    }
}

private extension KeyedEncodingContainer where Key == NapaxiAutomationCodingKey {
    mutating func encode<T: Encodable>(_ value: T, forKey key: String) throws {
        try encode(value, forKey: NapaxiAutomationCodingKey(stringValue: key)!)
    }

    mutating func encodeIfPresent<T: Encodable>(_ value: T?, forKey key: String) throws {
        try encodeIfPresent(value, forKey: NapaxiAutomationCodingKey(stringValue: key)!)
    }
}

private struct NapaxiAutomationJSONObject {
    let values: [String: NapaxiJSONValue]

    init(values: [String: NapaxiJSONValue]) {
        self.values = values
    }

    init(decoder: Decoder) throws {
        self.values = try decoder.singleValueContainer().decode([String: NapaxiJSONValue].self)
    }

    func string(_ keys: String...) -> String? {
        for key in keys {
            if let value = values[key]?.stringValue {
                return value
            }
        }
        return nil
    }

    func bool(_ keys: String...) -> Bool? {
        for key in keys {
            if let value = values[key]?.boolValue {
                return value
            }
        }
        return nil
    }

    func int(_ keys: String...) -> Int? {
        for key in keys {
            guard let value = values[key] else { continue }
            if let number = value.numberValue {
                return Int(number)
            }
            if let string = value.stringValue, let int = Int(string) {
                return int
            }
        }
        return nil
    }

    func intArray(_ keys: String...) -> [Int]? {
        for key in keys {
            guard case .array(let values)? = values[key] else { continue }
            let ints = values.compactMap { value -> Int? in
                if let number = value.numberValue { return Int(number) }
                if let string = value.stringValue { return Int(string) }
                return nil
            }.filter { $0 > 0 }
            return ints
        }
        return nil
    }

    func object(_ keys: String...) -> [String: NapaxiJSONValue]? {
        for key in keys {
            guard case .object(let object)? = values[key] else { continue }
            return object
        }
        return nil
    }

    func validateObjectOrNull(_ key: String, context: String) throws {
        guard let value = values[key] else { return }
        switch value {
        case .object, .null:
            return
        default:
            throw NapaxiError.invalidJSON("Expected \(context) object")
        }
    }

    func decode<T: Decodable>(_ type: T.Type, _ key: String) throws -> T? {
        guard let value = values[key] else {
            return nil
        }
        let data = try JSONEncoder().encode(value)
        return try JSONDecoder().decode(type, from: data)
    }
}

private extension Dictionary where Key == String, Value == NapaxiJSONValue {
    mutating func setString(_ key: String, _ value: String?) {
        guard let value else { return }
        self[key] = .string(value)
    }

    mutating func setNonEmptyString(_ key: String, _ value: String) {
        guard !value.isEmpty else { return }
        self[key] = .string(value)
    }

    mutating func setInt(_ key: String, _ value: Int?) {
        guard let value else { return }
        self[key] = .number(Double(value))
    }

    mutating func setBool(_ key: String, _ value: Bool?) {
        guard let value else { return }
        self[key] = .bool(value)
    }
}
