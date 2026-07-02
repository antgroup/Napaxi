import Foundation

public struct NapaxiA2AAgentCard: Codable, Equatable, Sendable {
    public var agentId: String
    public var displayName: String
    public var description: String
    public var acceptedInputModes: [String]
    public var acceptedOutputModes: [String]
    public var deepLinkUrl: String
    public var universalLinkUrl: String?
    public var capabilities: [String]
    public var requiresUserConfirmation: Bool

    public init(
        agentId: String,
        displayName: String,
        description: String = "",
        acceptedInputModes: [String] = [],
        acceptedOutputModes: [String] = [],
        deepLinkUrl: String = "",
        universalLinkUrl: String? = nil,
        capabilities: [String] = [],
        requiresUserConfirmation: Bool = true
    ) {
        self.agentId = agentId
        self.displayName = displayName
        self.description = description
        self.acceptedInputModes = acceptedInputModes
        self.acceptedOutputModes = acceptedOutputModes
        self.deepLinkUrl = deepLinkUrl
        self.universalLinkUrl = universalLinkUrl
        self.capabilities = capabilities
        self.requiresUserConfirmation = requiresUserConfirmation
    }

    public init(json: [String: NapaxiJSONValue]) {
        self = Self.fromJson(json)
    }

    public static func fromJson(_ json: [String: NapaxiJSONValue]) -> Self {
        let object = NapaxiA2AJSONObject(values: json)
        return Self(
            agentId: object.string("agentId", "agent_id") ?? "",
            displayName: object.string("displayName", "display_name") ?? "",
            description: object.string("description") ?? "",
            acceptedInputModes: object.stringArray("acceptedInputModes", "accepted_input_modes"),
            acceptedOutputModes: object.stringArray("acceptedOutputModes", "accepted_output_modes"),
            deepLinkUrl: object.string("deepLinkUrl", "deep_link_url") ?? "",
            universalLinkUrl: object.string("universalLinkUrl", "universal_link_url"),
            capabilities: object.stringArray("capabilities"),
            requiresUserConfirmation: object.bool("requiresUserConfirmation", "requires_user_confirmation") ?? true
        )
    }

    public func toJson() -> [String: NapaxiJSONValue] {
        var json: [String: NapaxiJSONValue] = [
            "agentId": .string(agentId),
            "displayName": .string(displayName),
            "description": .string(description),
            "acceptedInputModes": .array(acceptedInputModes.map { .string($0) }),
            "acceptedOutputModes": .array(acceptedOutputModes.map { .string($0) }),
            "deepLinkUrl": .string(deepLinkUrl),
            "capabilities": .array(capabilities.map { .string($0) }),
            "requiresUserConfirmation": .bool(requiresUserConfirmation),
        ]
        json.a2aSetString("universalLinkUrl", universalLinkUrl)
        return json
    }

    public init(from decoder: Decoder) throws {
        self = Self.fromJson(try NapaxiA2AJSONObject(decoder: decoder).values)
    }

    public func encode(to encoder: Encoder) throws {
        try NapaxiJSONValue.object(toJson()).encode(to: encoder)
    }
}

public struct NapaxiA2AParty: Codable, Equatable, Sendable {
    public var agentId: String
    public var peerId: String
    public var displayName: String
    public var deepLinkUrl: String

    public init(
        agentId: String,
        peerId: String = "",
        displayName: String = "",
        deepLinkUrl: String = ""
    ) {
        self.agentId = agentId
        self.peerId = peerId
        self.displayName = displayName
        self.deepLinkUrl = deepLinkUrl
    }

    public init(json: [String: NapaxiJSONValue]) {
        self = Self.fromJson(json)
    }

    public static func fromJson(_ json: [String: NapaxiJSONValue]) -> Self {
        let object = NapaxiA2AJSONObject(values: json)
        return Self(
            agentId: object.string("agentId", "agent_id") ?? "",
            peerId: object.string("peerId", "peer_id") ?? "",
            displayName: object.string("displayName", "display_name") ?? "",
            deepLinkUrl: object.string("deepLinkUrl", "deep_link_url") ?? ""
        )
    }

    public func toJson() -> [String: NapaxiJSONValue] {
        var json: [String: NapaxiJSONValue] = ["agentId": .string(agentId)]
        json.a2aSetNonEmptyString("peerId", peerId)
        json.a2aSetNonEmptyString("displayName", displayName)
        json.a2aSetNonEmptyString("deepLinkUrl", deepLinkUrl)
        return json
    }

    public init(from decoder: Decoder) throws {
        self = Self.fromJson(try NapaxiA2AJSONObject(decoder: decoder).values)
    }

    public func encode(to encoder: Encoder) throws {
        try NapaxiJSONValue.object(toJson()).encode(to: encoder)
    }
}

public struct NapaxiA2ADeepLinkEnvelope: Codable, Equatable, Sendable {
    public var protocolVersion: Int
    public var envelopeId: String
    public var kind: String
    public var sender: NapaxiA2AParty
    public var recipient: NapaxiA2AParty?
    public var task: NapaxiA2ATaskRequest?
    public var result: NapaxiA2ATaskResult?
    public var callback: NapaxiA2ACallback?
    public var createdAt: String
    public var expiresAt: String
    public var nonce: String
    public var idempotencyKey: String
    public var signatureAlgorithm: String
    public var signature: String?

    public init(
        protocolVersion: Int = 1,
        envelopeId: String,
        kind: String,
        sender: NapaxiA2AParty,
        recipient: NapaxiA2AParty? = nil,
        task: NapaxiA2ATaskRequest? = nil,
        result: NapaxiA2ATaskResult? = nil,
        callback: NapaxiA2ACallback? = nil,
        createdAt: String,
        expiresAt: String,
        nonce: String,
        idempotencyKey: String,
        signatureAlgorithm: String = "",
        signature: String? = nil
    ) {
        self.protocolVersion = protocolVersion
        self.envelopeId = envelopeId
        self.kind = kind
        self.sender = sender
        self.recipient = recipient
        self.task = task
        self.result = result
        self.callback = callback
        self.createdAt = createdAt
        self.expiresAt = expiresAt
        self.nonce = nonce
        self.idempotencyKey = idempotencyKey
        self.signatureAlgorithm = signatureAlgorithm
        self.signature = signature
    }

    public init(json: [String: NapaxiJSONValue]) {
        self = Self.fromJson(json)
    }

    public init(jsonString raw: String) throws {
        self = Self.fromJson(try decodeJsonObject(raw))
    }

    public static func fromJson(_ json: [String: NapaxiJSONValue]) -> Self {
        let object = NapaxiA2AJSONObject(values: json)
        return Self(
            protocolVersion: object.int("protocolVersion", "protocol_version") ?? 1,
            envelopeId: object.string("envelopeId", "envelope_id") ?? "",
            kind: object.string("kind") ?? "task_request",
            sender: NapaxiA2AParty.fromJson(object.object("sender") ?? [:]),
            recipient: object.object("recipient").map(NapaxiA2AParty.fromJson),
            task: object.object("task").map(NapaxiA2ATaskRequest.fromJson),
            result: object.object("result").map(NapaxiA2ATaskResult.fromJson),
            callback: object.object("callback").map(NapaxiA2ACallback.fromJson),
            createdAt: object.string("createdAt", "created_at") ?? "",
            expiresAt: object.string("expiresAt", "expires_at") ?? "",
            nonce: object.string("nonce") ?? "",
            idempotencyKey: object.string("idempotencyKey", "idempotency_key") ?? "",
            signatureAlgorithm: object.string("signatureAlgorithm", "signature_algorithm") ?? "",
            signature: object.string("signature")
        )
    }

    public func toJson() -> [String: NapaxiJSONValue] {
        var json: [String: NapaxiJSONValue] = [
            "protocolVersion": .number(Double(protocolVersion)),
            "envelopeId": .string(envelopeId),
            "kind": .string(kind),
            "sender": .object(sender.toJson()),
            "createdAt": .string(createdAt),
            "expiresAt": .string(expiresAt),
            "nonce": .string(nonce),
            "idempotencyKey": .string(idempotencyKey),
        ]
        if let recipient { json["recipient"] = .object(recipient.toJson()) }
        if let task { json["task"] = .object(task.toJson()) }
        if let result { json["result"] = .object(result.toJson()) }
        if let callback { json["callback"] = .object(callback.toJson()) }
        json.a2aSetNonEmptyString("signatureAlgorithm", signatureAlgorithm)
        json.a2aSetString("signature", signature)
        return json
    }

    public func jsonString() throws -> String {
        try toJson().jsonString()
    }

    public func toJsonString() throws -> String {
        try jsonString()
    }

    public init(from decoder: Decoder) throws {
        self = Self.fromJson(try NapaxiA2AJSONObject(decoder: decoder).values)
    }

    public func encode(to encoder: Encoder) throws {
        try NapaxiJSONValue.object(toJson()).encode(to: encoder)
    }
}

public struct NapaxiA2ATaskRequest: Codable, Equatable, Sendable {
    public var taskId: String
    public var message: String
    public var artifacts: [NapaxiA2AArtifact]
    public var context: [String: NapaxiJSONValue]
    public var requestedOutputModes: [String]
    public var riskHint: String
    public var sessionMode: String
    public var parentTaskId: String?

    public init(
        taskId: String,
        message: String,
        artifacts: [NapaxiA2AArtifact] = [],
        context: [String: NapaxiJSONValue] = [:],
        requestedOutputModes: [String] = [],
        riskHint: String = "",
        sessionMode: String = "isolated",
        parentTaskId: String? = nil
    ) {
        self.taskId = taskId
        self.message = message
        self.artifacts = artifacts
        self.context = context
        self.requestedOutputModes = requestedOutputModes
        self.riskHint = riskHint
        self.sessionMode = sessionMode
        self.parentTaskId = parentTaskId
    }

    public init(json: [String: NapaxiJSONValue]) {
        self = Self.fromJson(json)
    }

    public static func fromJson(_ json: [String: NapaxiJSONValue]) -> Self {
        let object = NapaxiA2AJSONObject(values: json)
        return Self(
            taskId: object.string("taskId", "task_id") ?? "",
            message: object.string("message") ?? "",
            artifacts: object.objectArray("artifacts").map(NapaxiA2AArtifact.fromJson),
            context: object.object("context") ?? [:],
            requestedOutputModes: object.stringArray("requestedOutputModes", "requested_output_modes"),
            riskHint: object.string("riskHint", "risk_hint") ?? "",
            sessionMode: object.string("sessionMode", "session_mode") ?? "isolated",
            parentTaskId: object.string("parentTaskId", "parent_task_id")
        )
    }

    public func toJson() -> [String: NapaxiJSONValue] {
        var json: [String: NapaxiJSONValue] = [
            "taskId": .string(taskId),
            "message": .string(message),
            "sessionMode": .string(sessionMode),
        ]
        if !artifacts.isEmpty {
            json["artifacts"] = .array(artifacts.map { .object($0.toJson()) })
        }
        if !context.isEmpty { json["context"] = .object(context) }
        if !requestedOutputModes.isEmpty {
            json["requestedOutputModes"] = .array(requestedOutputModes.map { .string($0) })
        }
        json.a2aSetNonEmptyString("riskHint", riskHint)
        json.a2aSetString("parentTaskId", parentTaskId)
        return json
    }

    public init(from decoder: Decoder) throws {
        self = Self.fromJson(try NapaxiA2AJSONObject(decoder: decoder).values)
    }

    public func encode(to encoder: Encoder) throws {
        try NapaxiJSONValue.object(toJson()).encode(to: encoder)
    }
}

public struct NapaxiA2AArtifact: Codable, Equatable, Sendable {
    public var artifactId: String
    public var mimeType: String
    public var name: String
    public var uri: String?
    public var text: String?
    public var metadata: [String: NapaxiJSONValue]

    public init(
        artifactId: String,
        mimeType: String = "",
        name: String = "",
        uri: String? = nil,
        text: String? = nil,
        metadata: [String: NapaxiJSONValue] = [:]
    ) {
        self.artifactId = artifactId
        self.mimeType = mimeType
        self.name = name
        self.uri = uri
        self.text = text
        self.metadata = metadata
    }

    public init(json: [String: NapaxiJSONValue]) {
        self = Self.fromJson(json)
    }

    public static func fromJson(_ json: [String: NapaxiJSONValue]) -> Self {
        let object = NapaxiA2AJSONObject(values: json)
        return Self(
            artifactId: object.string("artifactId", "artifact_id") ?? "",
            mimeType: object.string("mimeType", "mime_type") ?? "",
            name: object.string("name") ?? "",
            uri: object.string("uri"),
            text: object.string("text"),
            metadata: object.object("metadata") ?? [:]
        )
    }

    public func toJson() -> [String: NapaxiJSONValue] {
        var json: [String: NapaxiJSONValue] = ["artifactId": .string(artifactId)]
        json.a2aSetNonEmptyString("mimeType", mimeType)
        json.a2aSetNonEmptyString("name", name)
        json.a2aSetString("uri", uri)
        json.a2aSetString("text", text)
        if !metadata.isEmpty { json["metadata"] = .object(metadata) }
        return json
    }

    public init(from decoder: Decoder) throws {
        self = Self.fromJson(try NapaxiA2AJSONObject(decoder: decoder).values)
    }

    public func encode(to encoder: Encoder) throws {
        try NapaxiJSONValue.object(toJson()).encode(to: encoder)
    }
}

public struct NapaxiA2ACallback: Codable, Equatable, Sendable {
    public var deepLinkUrl: String
    public var universalLinkUrl: String?

    public init(deepLinkUrl: String = "", universalLinkUrl: String? = nil) {
        self.deepLinkUrl = deepLinkUrl
        self.universalLinkUrl = universalLinkUrl
    }

    public init(json: [String: NapaxiJSONValue]) {
        self = Self.fromJson(json)
    }

    public static func fromJson(_ json: [String: NapaxiJSONValue]) -> Self {
        let object = NapaxiA2AJSONObject(values: json)
        return Self(
            deepLinkUrl: object.string("deepLinkUrl", "deep_link_url") ?? "",
            universalLinkUrl: object.string("universalLinkUrl", "universal_link_url")
        )
    }

    public func toJson() -> [String: NapaxiJSONValue] {
        var json: [String: NapaxiJSONValue] = [:]
        json.a2aSetNonEmptyString("deepLinkUrl", deepLinkUrl)
        json.a2aSetString("universalLinkUrl", universalLinkUrl)
        return json
    }

    public init(from decoder: Decoder) throws {
        self = Self.fromJson(try NapaxiA2AJSONObject(decoder: decoder).values)
    }

    public func encode(to encoder: Encoder) throws {
        try NapaxiJSONValue.object(toJson()).encode(to: encoder)
    }
}

public struct NapaxiA2ATaskResult: Codable, Equatable, Sendable {
    public var taskId: String
    public var status: String
    public var message: String?
    public var artifacts: [NapaxiA2AArtifact]
    public var runId: String?
    public var completedAt: String?
    public var error: String?

    public init(
        taskId: String,
        status: String,
        message: String? = nil,
        artifacts: [NapaxiA2AArtifact] = [],
        runId: String? = nil,
        completedAt: String? = nil,
        error: String? = nil
    ) {
        self.taskId = taskId
        self.status = status
        self.message = message
        self.artifacts = artifacts
        self.runId = runId
        self.completedAt = completedAt
        self.error = error
    }

    public init(json: [String: NapaxiJSONValue]) {
        self = Self.fromJson(json)
    }

    public static func fromJson(_ json: [String: NapaxiJSONValue]) -> Self {
        let object = NapaxiA2AJSONObject(values: json)
        return Self(
            taskId: object.string("taskId", "task_id") ?? "",
            status: object.string("status") ?? "received",
            message: object.string("message"),
            artifacts: object.objectArray("artifacts").map(NapaxiA2AArtifact.fromJson),
            runId: object.string("runId", "run_id"),
            completedAt: object.string("completedAt", "completed_at"),
            error: object.string("error")
        )
    }

    public func toJson() -> [String: NapaxiJSONValue] {
        var json: [String: NapaxiJSONValue] = [
            "taskId": .string(taskId),
            "status": .string(status),
        ]
        json.a2aSetString("message", message)
        if !artifacts.isEmpty {
            json["artifacts"] = .array(artifacts.map { .object($0.toJson()) })
        }
        json.a2aSetString("runId", runId)
        json.a2aSetString("completedAt", completedAt)
        json.a2aSetString("error", error)
        return json
    }

    public init(from decoder: Decoder) throws {
        self = Self.fromJson(try NapaxiA2AJSONObject(decoder: decoder).values)
    }

    public func encode(to encoder: Encoder) throws {
        try NapaxiJSONValue.object(toJson()).encode(to: encoder)
    }
}

public struct NapaxiA2APeer: Codable, Equatable, Sendable {
    public var peerId: String
    public var agentId: String
    public var displayName: String
    public var deepLinkUrl: String
    public var trustLevel: String
    public var sharedSecret: String
    public var publicKey: String
    public var endpoints: [NapaxiA2APeerEndpoint]
    public var lastSeenAt: String?
    public var createdAt: String
    public var updatedAt: String

    public init(
        peerId: String,
        agentId: String,
        displayName: String = "",
        deepLinkUrl: String = "",
        trustLevel: String = "untrusted",
        sharedSecret: String = "",
        publicKey: String = "",
        endpoints: [NapaxiA2APeerEndpoint] = [],
        lastSeenAt: String? = nil,
        createdAt: String = "",
        updatedAt: String = ""
    ) {
        self.peerId = peerId
        self.agentId = agentId
        self.displayName = displayName
        self.deepLinkUrl = deepLinkUrl
        self.trustLevel = trustLevel
        self.sharedSecret = sharedSecret
        self.publicKey = publicKey
        self.endpoints = endpoints
        self.lastSeenAt = lastSeenAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    public init(json: [String: NapaxiJSONValue]) {
        self = Self.fromJson(json)
    }

    public static func fromJson(_ json: [String: NapaxiJSONValue]) -> Self {
        let object = NapaxiA2AJSONObject(values: json)
        return Self(
            peerId: object.string("peerId", "peer_id") ?? "",
            agentId: object.string("agentId", "agent_id") ?? "",
            displayName: object.string("displayName", "display_name") ?? "",
            deepLinkUrl: object.string("deepLinkUrl", "deep_link_url") ?? "",
            trustLevel: object.string("trustLevel", "trust_level") ?? "",
            sharedSecret: object.string("sharedSecret", "shared_secret") ?? "",
            publicKey: object.string("publicKey", "public_key") ?? "",
            endpoints: object.objectArray("endpoints").map(NapaxiA2APeerEndpoint.fromJson),
            lastSeenAt: object.string("lastSeenAt", "last_seen_at"),
            createdAt: object.string("createdAt", "created_at") ?? "",
            updatedAt: object.string("updatedAt", "updated_at") ?? ""
        )
    }

    public func toJson() -> [String: NapaxiJSONValue] {
        var json: [String: NapaxiJSONValue] = [
            "peerId": .string(peerId),
            "agentId": .string(agentId),
            "displayName": .string(displayName),
            "deepLinkUrl": .string(deepLinkUrl),
            "trustLevel": .string(trustLevel),
            "sharedSecret": .string(sharedSecret),
            "publicKey": .string(publicKey),
            "endpoints": .array(endpoints.map { .object($0.toJson()) }),
            "createdAt": .string(createdAt),
            "updatedAt": .string(updatedAt),
        ]
        json.a2aSetString("lastSeenAt", lastSeenAt)
        return json
    }

    public init(from decoder: Decoder) throws {
        self = Self.fromJson(try NapaxiA2AJSONObject(decoder: decoder).values)
    }

    public func encode(to encoder: Encoder) throws {
        try NapaxiJSONValue.object(toJson()).encode(to: encoder)
    }
}

public struct NapaxiA2ATaskRecord: Codable, Equatable, Sendable {
    public var taskId: String
    public var envelopeId: String
    public var idempotencyKey: String
    public var agentId: String
    public var sender: NapaxiA2AParty
    public var callback: NapaxiA2ACallback?
    public var request: NapaxiA2ATaskRequest
    public var status: String
    public var trust: String
    public var source: String
    public var createdAt: String
    public var updatedAt: String
    public var sessionId: String?
    public var peerMessageId: String?
    public var sessionKey: String?
    public var runId: String?
    public var summary: String?
    public var resultArtifacts: [NapaxiA2AArtifact]
    public var error: String?

    public init(
        taskId: String,
        envelopeId: String,
        idempotencyKey: String,
        agentId: String,
        sender: NapaxiA2AParty,
        callback: NapaxiA2ACallback? = nil,
        request: NapaxiA2ATaskRequest,
        status: String,
        trust: String,
        source: String,
        createdAt: String,
        updatedAt: String,
        sessionId: String? = nil,
        peerMessageId: String? = nil,
        sessionKey: String? = nil,
        runId: String? = nil,
        summary: String? = nil,
        resultArtifacts: [NapaxiA2AArtifact] = [],
        error: String? = nil
    ) {
        self.taskId = taskId
        self.envelopeId = envelopeId
        self.idempotencyKey = idempotencyKey
        self.agentId = agentId
        self.sender = sender
        self.callback = callback
        self.request = request
        self.status = status
        self.trust = trust
        self.source = source
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.sessionId = sessionId
        self.peerMessageId = peerMessageId
        self.sessionKey = sessionKey
        self.runId = runId
        self.summary = summary
        self.resultArtifacts = resultArtifacts
        self.error = error
    }

    public init(json: [String: NapaxiJSONValue]) {
        self = Self.fromJson(json)
    }

    public static func fromJson(_ json: [String: NapaxiJSONValue]) -> Self {
        let object = NapaxiA2AJSONObject(values: json)
        return Self(
            taskId: object.string("taskId", "task_id") ?? "",
            envelopeId: object.string("envelopeId", "envelope_id") ?? "",
            idempotencyKey: object.string("idempotencyKey", "idempotency_key") ?? "",
            agentId: object.string("agentId", "agent_id") ?? "",
            sender: NapaxiA2AParty.fromJson(object.object("sender") ?? [:]),
            callback: object.object("callback").map(NapaxiA2ACallback.fromJson),
            request: NapaxiA2ATaskRequest.fromJson(object.object("request") ?? [:]),
            status: object.string("status") ?? "received",
            trust: object.string("trust") ?? "untrusted",
            source: object.string("source") ?? "",
            createdAt: object.string("createdAt", "created_at") ?? "",
            updatedAt: object.string("updatedAt", "updated_at") ?? "",
            sessionId: object.string("sessionId", "session_id"),
            peerMessageId: object.string("peerMessageId", "peer_message_id"),
            sessionKey: object.string("sessionKey", "session_key"),
            runId: object.string("runId", "run_id"),
            summary: object.string("summary"),
            resultArtifacts: object.objectArray("resultArtifacts", "result_artifacts").map(NapaxiA2AArtifact.fromJson),
            error: object.string("error")
        )
    }

    public init(from decoder: Decoder) throws {
        self = Self.fromJson(try NapaxiA2AJSONObject(decoder: decoder).values)
    }

    public func toJson() -> [String: NapaxiJSONValue] {
        var json: [String: NapaxiJSONValue] = [
            "taskId": .string(taskId),
            "envelopeId": .string(envelopeId),
            "idempotencyKey": .string(idempotencyKey),
            "agentId": .string(agentId),
            "sender": .object(sender.toJson()),
            "request": .object(request.toJson()),
            "status": .string(status),
            "trust": .string(trust),
            "source": .string(source),
            "createdAt": .string(createdAt),
            "updatedAt": .string(updatedAt),
        ]
        if let callback { json["callback"] = .object(callback.toJson()) }
        json.a2aSetString("sessionId", sessionId)
        json.a2aSetString("peerMessageId", peerMessageId)
        json.a2aSetString("sessionKey", sessionKey)
        json.a2aSetString("runId", runId)
        json.a2aSetString("summary", summary)
        if !resultArtifacts.isEmpty {
            json["resultArtifacts"] = .array(resultArtifacts.map { .object($0.toJson()) })
        }
        json.a2aSetString("error", error)
        return json
    }

    public func encode(to encoder: Encoder) throws {
        try NapaxiJSONValue.object(toJson()).encode(to: encoder)
    }
}

public struct NapaxiA2APeerInvite: Codable, Equatable, Sendable {
    public var peerId: String
    public var sharedSecret: String
    public var envelope: NapaxiA2ADeepLinkEnvelope
    public var deepLinkUrl: String

    public init(
        peerId: String,
        sharedSecret: String,
        envelope: NapaxiA2ADeepLinkEnvelope,
        deepLinkUrl: String
    ) {
        self.peerId = peerId
        self.sharedSecret = sharedSecret
        self.envelope = envelope
        self.deepLinkUrl = deepLinkUrl
    }

    public init(json: [String: NapaxiJSONValue]) {
        self = Self.fromJson(json)
    }

    public static func fromJson(_ json: [String: NapaxiJSONValue]) -> Self {
        let object = NapaxiA2AJSONObject(values: json)
        return Self(
            peerId: object.string("peerId", "peer_id") ?? "",
            sharedSecret: object.string("sharedSecret", "shared_secret") ?? "",
            envelope: NapaxiA2ADeepLinkEnvelope.fromJson(object.object("envelope") ?? [:]),
            deepLinkUrl: object.string("deepLinkUrl", "deep_link_url") ?? ""
        )
    }

    public init(from decoder: Decoder) throws {
        self = Self.fromJson(try NapaxiA2AJSONObject(decoder: decoder).values)
    }

    public func encode(to encoder: Encoder) throws {
        try NapaxiJSONValue.object([
            "peerId": .string(peerId),
            "sharedSecret": .string(sharedSecret),
            "envelope": .object(envelope.toJson()),
            "deepLinkUrl": .string(deepLinkUrl),
        ]).encode(to: encoder)
    }
}

public struct NapaxiA2AResultLink: Codable, Equatable, Sendable {
    public var taskId: String
    public var envelope: NapaxiA2ADeepLinkEnvelope
    public var deepLinkUrl: String

    public init(taskId: String, envelope: NapaxiA2ADeepLinkEnvelope, deepLinkUrl: String) {
        self.taskId = taskId
        self.envelope = envelope
        self.deepLinkUrl = deepLinkUrl
    }

    public init(json: [String: NapaxiJSONValue]) {
        self = Self.fromJson(json)
    }

    public static func fromJson(_ json: [String: NapaxiJSONValue]) -> Self {
        let object = NapaxiA2AJSONObject(values: json)
        return Self(
            taskId: object.string("taskId", "task_id") ?? "",
            envelope: NapaxiA2ADeepLinkEnvelope.fromJson(object.object("envelope") ?? [:]),
            deepLinkUrl: object.string("deepLinkUrl", "deep_link_url") ?? ""
        )
    }

    public init(from decoder: Decoder) throws {
        self = Self.fromJson(try NapaxiA2AJSONObject(decoder: decoder).values)
    }

    public func encode(to encoder: Encoder) throws {
        try NapaxiJSONValue.object([
            "taskId": .string(taskId),
            "envelope": .object(envelope.toJson()),
            "deepLinkUrl": .string(deepLinkUrl),
        ]).encode(to: encoder)
    }
}

public struct NapaxiA2APeerEndpoint: Codable, Equatable, Sendable {
    public var transport: String
    public var uri: String
    public var priority: Int
    public var lastSeenAt: String?

    public init(transport: String, uri: String, priority: Int = 0, lastSeenAt: String? = nil) {
        self.transport = transport
        self.uri = uri
        self.priority = priority
        self.lastSeenAt = lastSeenAt
    }

    public init(json: [String: NapaxiJSONValue]) {
        let object = NapaxiA2AJSONObject(values: json)
        self.init(
            transport: object.string("transport") ?? "unknown",
            uri: object.string("uri") ?? "",
            priority: object.int("priority") ?? 0,
            lastSeenAt: object.string("lastSeenAt", "last_seen_at")
        )
    }

    public static func fromJson(_ json: [String: NapaxiJSONValue]) -> Self {
        Self(json: json)
    }

    public func toJson() -> [String: NapaxiJSONValue] {
        var json: [String: NapaxiJSONValue] = [
            "transport": .string(transport),
            "uri": .string(uri),
            "priority": .number(Double(priority)),
        ]
        json.a2aSetString("lastSeenAt", lastSeenAt)
        return json
    }
}

public struct NapaxiA2APeerSession: Codable, Equatable, Sendable {
    public var sessionId: String
    public var localPeerId: String
    public var remotePeerId: String
    public var remoteAgentId: String
    public var status: String
    public var transport: String
    public var endpoint: String
    public var createdAt: String
    public var updatedAt: String
    public var lastMessageAt: String?

    public init(json: [String: NapaxiJSONValue]) {
        let object = NapaxiA2AJSONObject(values: json)
        self.sessionId = object.string("sessionId", "session_id") ?? ""
        self.localPeerId = object.string("localPeerId", "local_peer_id") ?? ""
        self.remotePeerId = object.string("remotePeerId", "remote_peer_id") ?? ""
        self.remoteAgentId = object.string("remoteAgentId", "remote_agent_id") ?? ""
        self.status = object.string("status") ?? "active"
        self.transport = object.string("transport") ?? "unknown"
        self.endpoint = object.string("endpoint") ?? ""
        self.createdAt = object.string("createdAt", "created_at") ?? ""
        self.updatedAt = object.string("updatedAt", "updated_at") ?? ""
        self.lastMessageAt = object.string("lastMessageAt", "last_message_at")
    }

    public init(from decoder: Decoder) throws {
        self.init(json: try NapaxiA2AJSONObject(decoder: decoder).values)
    }
}

public struct NapaxiA2APeerMessage: Codable, Equatable, Sendable {
    public var messageId: String
    public var sessionId: String
    public var fromPeerId: String
    public var toPeerId: String
    public var kind: String
    public var createdAt: String
    public var expiresAt: String
    public var nonce: String
    public var idempotencyKey: String
    public var payload: [String: NapaxiJSONValue]
    public var signatureAlgorithm: String
    public var signature: String?

    public init(json: [String: NapaxiJSONValue]) {
        let object = NapaxiA2AJSONObject(values: json)
        self.messageId = object.string("messageId", "message_id") ?? ""
        self.sessionId = object.string("sessionId", "session_id") ?? ""
        self.fromPeerId = object.string("fromPeerId", "from_peer_id") ?? ""
        self.toPeerId = object.string("toPeerId", "to_peer_id") ?? ""
        self.kind = object.string("kind") ?? ""
        self.createdAt = object.string("createdAt", "created_at") ?? ""
        self.expiresAt = object.string("expiresAt", "expires_at") ?? ""
        self.nonce = object.string("nonce") ?? ""
        self.idempotencyKey = object.string("idempotencyKey", "idempotency_key") ?? ""
        self.payload = object.object("payload") ?? [:]
        self.signatureAlgorithm = object.string("signatureAlgorithm", "signature_algorithm") ?? ""
        self.signature = object.string("signature")
    }

    public init(from decoder: Decoder) throws {
        self.init(json: try NapaxiA2AJSONObject(decoder: decoder).values)
    }

    public func toJson() -> [String: NapaxiJSONValue] {
        var json: [String: NapaxiJSONValue] = [
            "messageId": .string(messageId),
            "sessionId": .string(sessionId),
            "fromPeerId": .string(fromPeerId),
            "toPeerId": .string(toPeerId),
            "kind": .string(kind),
            "createdAt": .string(createdAt),
            "expiresAt": .string(expiresAt),
            "nonce": .string(nonce),
            "idempotencyKey": .string(idempotencyKey),
            "payload": .object(payload),
        ]
        json.a2aSetNonEmptyString("signatureAlgorithm", signatureAlgorithm)
        json.a2aSetString("signature", signature)
        return json
    }

    public func jsonString() throws -> String {
        try toJson().jsonString()
    }
}

public struct NapaxiA2ADeliveryRecord: Codable, Equatable, Sendable {
    public var messageId: String
    public var sessionId: String
    public var direction: String
    public var kind: String
    public var status: String
    public var createdAt: String
    public var updatedAt: String
    public var taskId: String?
    public var error: String?

    public init(json: [String: NapaxiJSONValue]) {
        let object = NapaxiA2AJSONObject(values: json)
        self.messageId = object.string("messageId", "message_id") ?? ""
        self.sessionId = object.string("sessionId", "session_id") ?? ""
        self.direction = object.string("direction") ?? ""
        self.kind = object.string("kind") ?? ""
        self.status = object.string("status") ?? ""
        self.createdAt = object.string("createdAt", "created_at") ?? ""
        self.updatedAt = object.string("updatedAt", "updated_at") ?? ""
        self.taskId = object.string("taskId", "task_id")
        self.error = object.string("error")
    }

    public init(from decoder: Decoder) throws {
        self.init(json: try NapaxiA2AJSONObject(decoder: decoder).values)
    }
}

public struct NapaxiA2ALocalTransportStatus: Codable, Equatable, Sendable {
    public var supported: Bool
    public var running: Bool
    public var transport: String
    public var serviceType: String
    public var peerId: String
    public var agentId: String
    public var displayName: String
    public var endpoint: String
    public var listenerPort: Int
    public var registeredName: String
    public var discoveredPeerCount: Int
    public var activeDiscoveryCount: Int
    public var sentMessageCount: Int
    public var receivedMessageCount: Int
    public var multicastLockHeld: Bool
    public var lastError: String
    public var reason: String

    public init(json: [String: NapaxiJSONValue]) {
        let object = NapaxiA2AJSONObject(values: json)
        self.supported = object.bool("supported") ?? false
        self.running = object.bool("running") ?? false
        self.transport = object.string("transport") ?? ""
        self.serviceType = object.string("serviceType", "service_type") ?? ""
        self.peerId = object.string("peerId", "peer_id") ?? ""
        self.agentId = object.string("agentId", "agent_id") ?? ""
        self.displayName = object.string("displayName", "display_name") ?? ""
        self.endpoint = object.string("endpoint") ?? ""
        self.listenerPort = object.int("listenerPort", "listener_port") ?? 0
        self.registeredName = object.string("registeredName", "registered_name") ?? ""
        self.discoveredPeerCount = object.int("discoveredPeerCount", "discovered_peer_count") ?? 0
        self.activeDiscoveryCount = object.int("activeDiscoveryCount", "active_discovery_count") ?? 0
        self.sentMessageCount = object.int("sentMessageCount", "sent_message_count") ?? 0
        self.receivedMessageCount = object.int("receivedMessageCount", "received_message_count") ?? 0
        self.multicastLockHeld = object.bool("multicastLockHeld", "multicast_lock_held") ?? false
        self.lastError = object.string("lastError", "last_error") ?? ""
        self.reason = object.string("reason") ?? ""
    }

    public init(from decoder: Decoder) throws {
        self.init(json: try NapaxiA2AJSONObject(decoder: decoder).values)
    }
}

public struct NapaxiA2ALocalPeerAdvertisement: Codable, Equatable, Sendable {
    public var peerId: String
    public var agentId: String
    public var displayName: String
    public var publicKey: String
    public var transport: String
    public var endpoint: String
    public var host: String
    public var port: Int

    public init(json: [String: NapaxiJSONValue]) {
        let object = NapaxiA2AJSONObject(values: json)
        self.peerId = object.string("peerId", "peer_id") ?? ""
        self.agentId = object.string("agentId", "agent_id") ?? ""
        self.displayName = object.string("displayName", "display_name") ?? ""
        self.publicKey = object.string("publicKey", "public_key") ?? ""
        self.transport = object.string("transport") ?? "lan_tcp_jsonl"
        self.endpoint = object.string("endpoint") ?? ""
        self.host = object.string("host") ?? ""
        self.port = object.int("port") ?? 0
    }

    public init(from decoder: Decoder) throws {
        self.init(json: try NapaxiA2AJSONObject(decoder: decoder).values)
    }

    public func toPeer() -> NapaxiA2APeer {
        NapaxiA2APeer.fromJson([
            "peerId": .string(peerId),
            "agentId": .string(agentId),
            "displayName": .string(displayName),
            "trustLevel": .string("user_confirmed"),
        ])
    }
}

public struct NapaxiA2ALocalTransportEvent: Codable, Equatable, Sendable {
    public var action: String
    public var peer: NapaxiA2ALocalPeerAdvertisement?
    public var message: NapaxiA2APeerMessage?
    public var messageJson: String
    public var payload: [String: NapaxiJSONValue]

    public init(json: [String: NapaxiJSONValue]) {
        let object = NapaxiA2AJSONObject(values: json)
        self.action = object.string("action") ?? ""
        self.peer = object.object("peer").map(NapaxiA2ALocalPeerAdvertisement.init(json:))
        self.message = object.object("message").map(NapaxiA2APeerMessage.init(json:))
        self.messageJson = object.string("messageJson", "message_json") ?? ""
        self.payload = object.object("payload") ?? [:]
    }

    public init(fromEvent json: [String: NapaxiJSONValue]) {
        self.init(json: json)
    }

    public init(from decoder: Decoder) throws {
        self.init(json: try NapaxiA2AJSONObject(decoder: decoder).values)
    }
}

public func decodeA2APeers(_ raw: String) throws -> [NapaxiA2APeer] {
    let value = try NapaxiRawJSON(jsonString: raw).value
    guard case .array = value else { return [] }
    return try decodeJsonObjectListFromValue(value, NapaxiA2APeer.fromJson)
}

public func decodeA2ATasks(_ raw: String) throws -> [NapaxiA2ATaskRecord] {
    let value = try NapaxiRawJSON(jsonString: raw).value
    guard case .array = value else { return [] }
    return try decodeJsonObjectListFromValue(value, NapaxiA2ATaskRecord.fromJson)
}

public func decodeA2APeerSessions(_ raw: String) throws -> [NapaxiA2APeerSession] {
    let value = try NapaxiRawJSON(jsonString: raw).value
    guard case .array = value else { return [] }
    return try decodeJsonObjectListFromValue(value, NapaxiA2APeerSession.init(json:))
}

public func decodeA2APeerMessages(_ raw: String) throws -> [NapaxiA2APeerMessage] {
    let value = try NapaxiRawJSON(jsonString: raw).value
    guard case .array = value else { return [] }
    return try decodeJsonObjectListFromValue(value, NapaxiA2APeerMessage.init(json:))
}

public func decodeA2ADeliveryRecords(_ raw: String) throws -> [NapaxiA2ADeliveryRecord] {
    let value = try NapaxiRawJSON(jsonString: raw).value
    guard case .array = value else { return [] }
    return try decodeJsonObjectListFromValue(value, NapaxiA2ADeliveryRecord.init(json:))
}

private struct NapaxiA2AJSONObject {
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
            if let string = values[key]?.stringValue {
                return Bool(string)
            }
        }
        return nil
    }

    func int(_ keys: String...) -> Int? {
        for key in keys {
            guard let value = values[key] else { continue }
            if let number = value.numberValue { return Int(number) }
            if let string = value.stringValue, let int = Int(string) { return int }
        }
        return nil
    }

    func object(_ keys: String...) -> [String: NapaxiJSONValue]? {
        for key in keys {
            if case .object(let object)? = values[key] {
                return object
            }
        }
        return nil
    }

    func objectArray(_ keys: String...) -> [[String: NapaxiJSONValue]] {
        for key in keys {
            guard case .array(let values)? = values[key] else { continue }
            return values.compactMap { item in
                if case .object(let object) = item {
                    return object
                }
                return nil
            }
        }
        return []
    }

    func stringArray(_ keys: String...) -> [String] {
        for key in keys {
            guard case .array(let values)? = values[key] else { continue }
            return values.map(\.jsonCodecDisplayString)
        }
        return []
    }
}

private extension Dictionary where Key == String, Value == NapaxiJSONValue {
    mutating func a2aSetString(_ key: String, _ value: String?) {
        guard let value else { return }
        self[key] = .string(value)
    }

    mutating func a2aSetNonEmptyString(_ key: String, _ value: String) {
        guard !value.isEmpty else { return }
        self[key] = .string(value)
    }
}
