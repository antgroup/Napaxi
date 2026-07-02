import Foundation

public enum JSONValue: Codable, Equatable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: JSONValue])
    case array([JSONValue])
    case null

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([String: JSONValue].self) {
            self = .object(value)
        } else {
            self = .array(try container.decode([JSONValue].self))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value):
            try container.encode(value)
        case .number(let value):
            try container.encode(value)
        case .bool(let value):
            try container.encode(value)
        case .object(let value):
            try container.encode(value)
        case .array(let value):
            try container.encode(value)
        case .null:
            try container.encodeNil()
        }
    }
}

public struct AgentPackage: Codable, Equatable {
    public var providerId: String
    public var agentId: String
    public var displayName: String
    public var description: String
    public var systemPrompt: String
    public var actions: [AgentAction]
    public var handoff: [String: JSONValue]
    public var result: [String: JSONValue]

    public init(
        providerId: String,
        agentId: String,
        displayName: String,
        description: String = "",
        systemPrompt: String = "",
        actions: [AgentAction] = [],
        handoff: [String: JSONValue] = [:],
        result: [String: JSONValue] = [:]
    ) {
        self.providerId = providerId
        self.agentId = agentId
        self.displayName = displayName
        self.description = description
        self.systemPrompt = systemPrompt
        self.actions = actions
        self.handoff = handoff
        self.result = result
    }
}

public struct AgentAction: Codable, Equatable {
    public var actionId: String
    public var toolName: String
    public var description: String
    public var parameters: [String: JSONValue]
    public var resultSchema: [String: JSONValue]
    public var risk: String
    public var confirmationPolicy: String
    public var executionModes: [String]
    public var timeoutSeconds: Int

    public init(
        actionId: String,
        toolName: String,
        description: String,
        parameters: [String: JSONValue] = ["type": .string("object"), "properties": .object([:])],
        resultSchema: [String: JSONValue] = ["type": .string("object")],
        risk: String = "high",
        confirmationPolicy: String = "provider_required",
        executionModes: [String] = [],
        timeoutSeconds: Int = 600
    ) {
        self.actionId = actionId
        self.toolName = toolName
        self.description = description
        self.parameters = parameters
        self.resultSchema = resultSchema
        self.risk = risk
        self.confirmationPolicy = confirmationPolicy
        self.executionModes = executionModes
        self.timeoutSeconds = timeoutSeconds
    }
}

public struct AgentInstallRequest: Codable, Equatable {
    public var protocolVersion: Int
    public var requestId: String
    public var nonce: String
    public var hostPackageName: String
    public var createdAt: String
    public var expiresAt: String
    public var hostSigningCertSha256: String
    public var hostInstanceId: String
    public var hostSharedSecret: String
    public var hostBundleId: String
    public var hostTeamId: String
    public var hostCallbackScheme: String
    public var callbackUrl: String

    private enum CodingKeys: String, CodingKey {
        case protocolVersion
        case requestId
        case nonce
        case hostPackageName
        case createdAt
        case expiresAt
        case hostSigningCertSha256
        case hostInstanceId
        case hostSharedSecret
        case hostBundleId
        case hostTeamId
        case hostCallbackScheme
        case callbackUrl
    }

    public init(
        protocolVersion: Int = 2,
        requestId: String,
        nonce: String,
        hostPackageName: String = "",
        createdAt: String,
        expiresAt: String,
        hostSigningCertSha256: String = "",
        hostInstanceId: String,
        hostSharedSecret: String,
        hostBundleId: String = "",
        hostTeamId: String = "",
        hostCallbackScheme: String = "",
        callbackUrl: String = ""
    ) {
        self.protocolVersion = protocolVersion
        self.requestId = requestId
        self.nonce = nonce
        self.hostPackageName = hostPackageName
        self.createdAt = createdAt
        self.expiresAt = expiresAt
        self.hostSigningCertSha256 = hostSigningCertSha256
        self.hostInstanceId = hostInstanceId
        self.hostSharedSecret = hostSharedSecret
        self.hostBundleId = hostBundleId
        self.hostTeamId = hostTeamId
        self.hostCallbackScheme = hostCallbackScheme
        self.callbackUrl = callbackUrl
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.protocolVersion = try container.decodeIfPresent(Int.self, forKey: .protocolVersion) ?? 1
        self.requestId = try container.decodeIfPresent(String.self, forKey: .requestId) ?? ""
        self.nonce = try container.decodeIfPresent(String.self, forKey: .nonce) ?? ""
        self.hostPackageName = try container.decodeIfPresent(String.self, forKey: .hostPackageName) ?? ""
        self.createdAt = try container.decodeIfPresent(String.self, forKey: .createdAt) ?? ""
        self.expiresAt = try container.decodeIfPresent(String.self, forKey: .expiresAt) ?? ""
        self.hostSigningCertSha256 = try container.decodeIfPresent(String.self, forKey: .hostSigningCertSha256) ?? ""
        self.hostInstanceId = try container.decodeIfPresent(String.self, forKey: .hostInstanceId) ?? ""
        self.hostSharedSecret = try container.decodeIfPresent(String.self, forKey: .hostSharedSecret) ?? ""
        self.hostBundleId = try container.decodeIfPresent(String.self, forKey: .hostBundleId) ?? ""
        self.hostTeamId = try container.decodeIfPresent(String.self, forKey: .hostTeamId) ?? ""
        self.hostCallbackScheme = try container.decodeIfPresent(String.self, forKey: .hostCallbackScheme) ?? ""
        self.callbackUrl = try container.decodeIfPresent(String.self, forKey: .callbackUrl) ?? ""
    }
}

public struct AgentInstallResult: Codable, Equatable {
    public var status: String
    public var requestId: String
    public var nonce: String
    public var package: AgentPackage?
    public var error: [String: JSONValue]?
    public var completedAt: String

    public init(
        status: String,
        requestId: String,
        nonce: String,
        package: AgentPackage?,
        error: [String: JSONValue]? = nil,
        completedAt: String
    ) {
        self.status = status
        self.requestId = requestId
        self.nonce = nonce
        self.package = package
        self.error = error
        self.completedAt = completedAt
    }
}

public struct AgentTriggerRequest: Codable, Equatable {
    public var protocolVersion: Int
    public var requestId: String
    public var providerId: String
    public var agentId: String
    public var message: String
    public var source: String
    public var eventType: String
    public var payload: [String: JSONValue]
    public var createdAt: String
    public var expiresAt: String
    public var nonce: String
    public var idempotencyKey: String
    public var hostInstanceId: String
    public var signatureAlgorithm: String
    public var signature: String?

    public init(
        protocolVersion: Int = 2,
        requestId: String,
        providerId: String,
        agentId: String,
        message: String,
        source: String = "",
        eventType: String = "",
        payload: [String: JSONValue] = [:],
        createdAt: String,
        expiresAt: String,
        nonce: String,
        idempotencyKey: String,
        hostInstanceId: String = "",
        signatureAlgorithm: String = "",
        signature: String? = nil
    ) {
        self.protocolVersion = protocolVersion
        self.requestId = requestId
        self.providerId = providerId
        self.agentId = agentId
        self.message = message
        self.source = source
        self.eventType = eventType
        self.payload = payload
        self.createdAt = createdAt
        self.expiresAt = expiresAt
        self.nonce = nonce
        self.idempotencyKey = idempotencyKey
        self.hostInstanceId = hostInstanceId
        self.signatureAlgorithm = signatureAlgorithm
        self.signature = signature
    }
}

public struct ActionProposal: Codable, Equatable {
    public var requestId: String
    public var providerId: String
    public var agentId: String
    public var actionId: String
    public var toolName: String
    public var arguments: [String: JSONValue]
    public var userIntentSummary: String
    public var createdAt: String
    public var expiresAt: String
    public var nonce: String
    public var idempotencyKey: String
    public var callback: [String: JSONValue]
    public var risk: String
    public var confirmationPolicy: String
    public var hostInstanceId: String
    public var signatureAlgorithm: String
    public var signature: String?

    public init(
        requestId: String,
        providerId: String,
        agentId: String,
        actionId: String,
        toolName: String,
        arguments: [String: JSONValue] = [:],
        userIntentSummary: String = "",
        createdAt: String,
        expiresAt: String,
        nonce: String,
        idempotencyKey: String,
        callback: [String: JSONValue] = [:],
        risk: String = "high",
        confirmationPolicy: String = "provider_required",
        hostInstanceId: String = "",
        signatureAlgorithm: String = "",
        signature: String? = nil
    ) {
        self.requestId = requestId
        self.providerId = providerId
        self.agentId = agentId
        self.actionId = actionId
        self.toolName = toolName
        self.arguments = arguments
        self.userIntentSummary = userIntentSummary
        self.createdAt = createdAt
        self.expiresAt = expiresAt
        self.nonce = nonce
        self.idempotencyKey = idempotencyKey
        self.callback = callback
        self.risk = risk
        self.confirmationPolicy = confirmationPolicy
        self.hostInstanceId = hostInstanceId
        self.signatureAlgorithm = signatureAlgorithm
        self.signature = signature
    }
}

public struct ActionResult: Codable, Equatable {
    public var requestId: String
    public var status: String
    public var result: [String: JSONValue]
    public var error: String?
    public var providerTraceId: String?
    public var completedAt: String
    public var signature: String?

    public init(
        requestId: String,
        status: String,
        result: [String: JSONValue] = [:],
        error: String? = nil,
        providerTraceId: String? = nil,
        completedAt: String,
        signature: String? = nil
    ) {
        self.requestId = requestId
        self.status = status
        self.result = result
        self.error = error
        self.providerTraceId = providerTraceId
        self.completedAt = completedAt
        self.signature = signature
    }
}

public struct ProposalValidationResult: Equatable {
    public var isValid: Bool
    public var code: String?
    public var message: String?

    public static func valid() -> ProposalValidationResult {
        ProposalValidationResult(isValid: true, code: nil, message: nil)
    }

    public static func failure(_ code: String, _ message: String) -> ProposalValidationResult {
        ProposalValidationResult(isValid: false, code: code, message: message)
    }
}

public enum TrustedProposalStatus {
    public static let trusted = "trusted"
    public static let untrusted = "untrusted"
    public static let replayed = "replayed"
    public static let expired = "expired"
    public static let signatureInvalid = "signature_invalid"
}

public struct TrustedProposalValidationResult: Equatable {
    public var status: String
    public var isValid: Bool
    public var isTrusted: Bool
    public var code: String?
    public var message: String?

    public static func trusted() -> TrustedProposalValidationResult {
        TrustedProposalValidationResult(
            status: TrustedProposalStatus.trusted,
            isValid: true,
            isTrusted: true,
            code: nil,
            message: nil
        )
    }

    public static func failure(
        status: String,
        code: String,
        message: String
    ) -> TrustedProposalValidationResult {
        TrustedProposalValidationResult(
            status: status,
            isValid: false,
            isTrusted: false,
            code: code,
            message: message
        )
    }
}

public struct TrustedHostBinding: Codable, Equatable {
    public var hostBundleId: String
    public var hostTeamId: String
    public var hostCallbackScheme: String
    public var hostInstanceId: String
    public var hostSharedSecret: String
    public var installedAt: String
    public var protocolVersion: Int

    public init(
        hostBundleId: String,
        hostTeamId: String = "",
        hostCallbackScheme: String = "",
        hostInstanceId: String,
        hostSharedSecret: String,
        installedAt: String,
        protocolVersion: Int = 2
    ) {
        self.hostBundleId = hostBundleId
        self.hostTeamId = hostTeamId
        self.hostCallbackScheme = hostCallbackScheme
        self.hostInstanceId = hostInstanceId
        self.hostSharedSecret = hostSharedSecret
        self.installedAt = installedAt
        self.protocolVersion = protocolVersion
    }
}
