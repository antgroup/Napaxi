import Foundation
import CryptoKit
import Security

public struct NapaxiAgentProviderDescriptor: Codable, Equatable, Sendable {
    public var platform: String
    public var packageName: String
    public var installActivityName: String
    public var activityName: String
    public var label: String
    public var signingCertSha256: String
    public var installUrl: String
    public var actionUrl: String
    public var universalLinkDomain: String
    public var iosBundleId: String
    public var iosTeamId: String

    public init(
        platform: String = "android",
        packageName: String = "",
        installActivityName: String = "",
        activityName: String = "",
        label: String = "",
        signingCertSha256: String = "",
        installUrl: String = "",
        actionUrl: String = "",
        universalLinkDomain: String = "",
        iosBundleId: String = "",
        iosTeamId: String = ""
    ) {
        self.platform = platform
        self.packageName = packageName
        self.installActivityName = installActivityName
        self.activityName = activityName
        self.label = label
        self.signingCertSha256 = signingCertSha256
        self.installUrl = installUrl
        self.actionUrl = actionUrl
        self.universalLinkDomain = universalLinkDomain
        self.iosBundleId = iosBundleId
        self.iosTeamId = iosTeamId
    }

    public init(map: [String: NapaxiJSONValue]) {
        self = Self.fromMap(map)
    }

    public static func fromMap(_ map: [String: NapaxiJSONValue]) -> Self {
        let installActivityName = map.string("installActivityName")
        let activityName = map.string("activityName")
        return Self(
            platform: map.string("platform") ?? "android",
            packageName: map.string("packageName") ?? "",
            installActivityName: installActivityName ?? activityName ?? "",
            activityName: activityName ?? installActivityName ?? "",
            label: map.string("label") ?? "",
            signingCertSha256: map.string("signingCertSha256") ?? "",
            installUrl: map.string("installUrl") ?? "",
            actionUrl: map.string("actionUrl") ?? "",
            universalLinkDomain: map.string("universalLinkDomain") ?? "",
            iosBundleId: map.string("iosBundleId") ?? "",
            iosTeamId: map.string("iosTeamId") ?? ""
        )
    }

    enum CodingKeys: String, CodingKey {
        case platform
        case packageName
        case installActivityName
        case activityName
        case label
        case signingCertSha256
        case installUrl
        case actionUrl
        case universalLinkDomain
        case iosBundleId
        case iosTeamId
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let installActivityName = try container.decodeIfPresent(String.self, forKey: .installActivityName)
        let activityName = try container.decodeIfPresent(String.self, forKey: .activityName)
        self.init(
            platform: try container.decodeIfPresent(String.self, forKey: .platform) ?? "android",
            packageName: try container.decodeIfPresent(String.self, forKey: .packageName) ?? "",
            installActivityName: installActivityName ?? activityName ?? "",
            activityName: activityName ?? installActivityName ?? "",
            label: try container.decodeIfPresent(String.self, forKey: .label) ?? "",
            signingCertSha256: try container.decodeIfPresent(String.self, forKey: .signingCertSha256) ?? "",
            installUrl: try container.decodeIfPresent(String.self, forKey: .installUrl) ?? "",
            actionUrl: try container.decodeIfPresent(String.self, forKey: .actionUrl) ?? "",
            universalLinkDomain: try container.decodeIfPresent(String.self, forKey: .universalLinkDomain) ?? "",
            iosBundleId: try container.decodeIfPresent(String.self, forKey: .iosBundleId) ?? "",
            iosTeamId: try container.decodeIfPresent(String.self, forKey: .iosTeamId) ?? ""
        )
    }

    public func encode(to encoder: Encoder) throws {
        try NapaxiJSONValue.object(toJson()).encode(to: encoder)
    }

    public func jsonValue() -> NapaxiJSONValue {
        .object(toJson())
    }

    public func toJson() -> [String: NapaxiJSONValue] {
        var object: [String: NapaxiJSONValue] = [
            "platform": .string(platform),
            "packageName": .string(packageName),
            "installActivityName": .string(installActivityName),
            "activityName": .string(activityName),
            "label": .string(label),
            "signingCertSha256": .string(signingCertSha256),
        ]
        object.setNonEmpty("installUrl", installUrl)
        object.setNonEmpty("actionUrl", actionUrl)
        object.setNonEmpty("universalLinkDomain", universalLinkDomain)
        object.setNonEmpty("iosBundleId", iosBundleId)
        object.setNonEmpty("iosTeamId", iosTeamId)
        return object
    }
}

public struct NapaxiAgentProviderHostInfo: Codable, Equatable, Sendable {
    public var bundleId: String
    public var teamId: String
    public var callbackScheme: String
    public var backgroundTriggerSupported: Bool
    public var backgroundTriggerService: String

    public init(
        bundleId: String = Bundle.main.bundleIdentifier ?? "",
        teamId: String = "",
        callbackScheme: String = NapaxiAgentProviderHost.defaultCallbackScheme(),
        backgroundTriggerSupported: Bool = false,
        backgroundTriggerService: String = ""
    ) {
        self.bundleId = bundleId
        self.teamId = teamId
        self.callbackScheme = callbackScheme
        self.backgroundTriggerSupported = backgroundTriggerSupported
        self.backgroundTriggerService = backgroundTriggerService
    }
}

public struct NapaxiAgentInstallRequest: Codable, Equatable, Sendable {
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
    public var backgroundTriggerSupported: Bool
    public var hostBackgroundTriggerService: String

    public init(
        protocolVersion: Int = 1,
        requestId: String,
        nonce: String,
        hostPackageName: String,
        createdAt: String,
        expiresAt: String,
        hostSigningCertSha256: String = "",
        hostInstanceId: String,
        hostSharedSecret: String,
        hostBundleId: String = "",
        hostTeamId: String = "",
        hostCallbackScheme: String = "",
        callbackUrl: String = "",
        backgroundTriggerSupported: Bool = false,
        hostBackgroundTriggerService: String = ""
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
        self.backgroundTriggerSupported = backgroundTriggerSupported
        self.hostBackgroundTriggerService = hostBackgroundTriggerService
    }

    public init(map: [String: NapaxiJSONValue]) {
        self = Self.fromMap(map)
    }

    public static func fromMap(_ map: [String: NapaxiJSONValue]) -> Self {
        Self(
            protocolVersion: map.int("protocol_version") ?? 1,
            requestId: map.string("request_id") ?? "",
            nonce: map.string("nonce") ?? "",
            hostPackageName: map.string("host_package_name") ?? "",
            createdAt: map.string("created_at") ?? "",
            expiresAt: map.string("expires_at") ?? "",
            hostSigningCertSha256: map.string("host_signing_cert_sha256") ?? "",
            hostInstanceId: map.string("host_instance_id") ?? "",
            hostSharedSecret: map.string("host_shared_secret") ?? "",
            hostBundleId: map.string("host_bundle_id") ?? "",
            hostTeamId: map.string("host_team_id") ?? "",
            hostCallbackScheme: map.string("host_callback_scheme") ?? "",
            callbackUrl: map.string("callback_url") ?? "",
            backgroundTriggerSupported: map.bool("background_trigger_supported") ?? false,
            hostBackgroundTriggerService: map.string("host_background_trigger_service") ?? ""
        )
    }

    enum CodingKeys: String, CodingKey {
        case protocolVersion = "protocol_version"
        case requestId = "request_id"
        case nonce
        case hostPackageName = "host_package_name"
        case createdAt = "created_at"
        case expiresAt = "expires_at"
        case hostSigningCertSha256 = "host_signing_cert_sha256"
        case hostInstanceId = "host_instance_id"
        case hostSharedSecret = "host_shared_secret"
        case hostBundleId = "host_bundle_id"
        case hostTeamId = "host_team_id"
        case hostCallbackScheme = "host_callback_scheme"
        case callbackUrl = "callback_url"
        case backgroundTriggerSupported = "background_trigger_supported"
        case hostBackgroundTriggerService = "host_background_trigger_service"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            protocolVersion: try container.decodeIfPresent(Int.self, forKey: .protocolVersion) ?? 1,
            requestId: try container.decodeIfPresent(String.self, forKey: .requestId) ?? "",
            nonce: try container.decodeIfPresent(String.self, forKey: .nonce) ?? "",
            hostPackageName: try container.decodeIfPresent(String.self, forKey: .hostPackageName) ?? "",
            createdAt: try container.decodeIfPresent(String.self, forKey: .createdAt) ?? "",
            expiresAt: try container.decodeIfPresent(String.self, forKey: .expiresAt) ?? "",
            hostSigningCertSha256: try container.decodeIfPresent(String.self, forKey: .hostSigningCertSha256) ?? "",
            hostInstanceId: try container.decodeIfPresent(String.self, forKey: .hostInstanceId) ?? "",
            hostSharedSecret: try container.decodeIfPresent(String.self, forKey: .hostSharedSecret) ?? "",
            hostBundleId: try container.decodeIfPresent(String.self, forKey: .hostBundleId) ?? "",
            hostTeamId: try container.decodeIfPresent(String.self, forKey: .hostTeamId) ?? "",
            hostCallbackScheme: try container.decodeIfPresent(String.self, forKey: .hostCallbackScheme) ?? "",
            callbackUrl: try container.decodeIfPresent(String.self, forKey: .callbackUrl) ?? "",
            backgroundTriggerSupported: try container.decodeIfPresent(Bool.self, forKey: .backgroundTriggerSupported) ?? false,
            hostBackgroundTriggerService: try container.decodeIfPresent(String.self, forKey: .hostBackgroundTriggerService) ?? ""
        )
    }

    public func encode(to encoder: Encoder) throws {
        try NapaxiJSONValue.object(toJson()).encode(to: encoder)
    }

    public func jsonString() throws -> String {
        try NapaxiAgentProviderHost.jsonString(from: self)
    }

    public func toJson() -> [String: NapaxiJSONValue] {
        var object: [String: NapaxiJSONValue] = [
            "protocol_version": .number(Double(protocolVersion)),
            "request_id": .string(requestId),
            "nonce": .string(nonce),
            "host_package_name": .string(hostPackageName),
            "created_at": .string(createdAt),
            "expires_at": .string(expiresAt),
            "host_signing_cert_sha256": .string(hostSigningCertSha256),
            "host_instance_id": .string(hostInstanceId),
            "host_shared_secret": .string(hostSharedSecret),
        ]
        object.setNonEmpty("host_bundle_id", hostBundleId)
        object.setNonEmpty("host_team_id", hostTeamId)
        object.setNonEmpty("host_callback_scheme", hostCallbackScheme)
        object.setNonEmpty("callback_url", callbackUrl)
        if backgroundTriggerSupported {
            object["background_trigger_supported"] = .bool(backgroundTriggerSupported)
        }
        object.setNonEmpty("host_background_trigger_service", hostBackgroundTriggerService)
        return object
    }

    public func toJsonString() throws -> String {
        try NapaxiRawJSON(.object(toJson())).jsonString()
    }
}

public struct NapaxiAgentProviderInstallResponse: Codable, Equatable, Sendable {
    public var installResultJSON: String
    public var installResultJson: String {
        get { installResultJSON }
        set { installResultJSON = newValue }
    }
    public var installBinding: [String: NapaxiJSONValue]

    public init(installResultJSON: String, installBinding: [String: NapaxiJSONValue]) {
        self.installResultJSON = installResultJSON
        self.installBinding = installBinding
    }

    public init(installResultJson: String, installBinding: [String: NapaxiJSONValue]) {
        self.init(installResultJSON: installResultJson, installBinding: installBinding)
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let object = try container.decode([String: NapaxiJSONValue].self)
        self.init(
            installResultJSON: object["installResultJson"]?.stringValue
                ?? object["installResultJSON"]?.stringValue
                ?? object["install_result_json"]?.stringValue
                ?? "",
            installBinding: object["installBinding"]?.objectValue
                ?? object["install_binding"]?.objectValue
                ?? [:]
        )
    }

    public func encode(to encoder: Encoder) throws {
        try NapaxiJSONValue.object([
            "installResultJson": .string(installResultJSON),
            "installBinding": .object(installBinding),
        ]).encode(to: encoder)
    }
}

public struct NapaxiAgentTriggerRequest: Codable, Equatable, Sendable {
    public var protocolVersion: Int
    public var requestId: String
    public var providerId: String
    public var agentId: String
    public var message: String
    public var source: String
    public var eventType: String
    public var payload: [String: NapaxiJSONValue]
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
        payload: [String: NapaxiJSONValue] = [:],
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

    public init(map: [String: NapaxiJSONValue]) {
        self = Self.fromMap(map)
    }

    public static func fromMap(_ map: [String: NapaxiJSONValue]) -> Self {
        Self(
            protocolVersion: map.int("protocol_version") ?? 2,
            requestId: map.string("request_id") ?? "",
            providerId: map.string("provider_id") ?? "",
            agentId: map.string("agent_id") ?? "",
            message: map.string("message") ?? "",
            source: map.string("source") ?? "",
            eventType: map.string("event_type") ?? "",
            payload: map.object("payload") ?? [:],
            createdAt: map.string("created_at") ?? "",
            expiresAt: map.string("expires_at") ?? "",
            nonce: map.string("nonce") ?? "",
            idempotencyKey: map.string("idempotency_key") ?? "",
            hostInstanceId: map.string("host_instance_id") ?? "",
            signatureAlgorithm: map.string("signature_algorithm") ?? "",
            signature: map.string("signature")
        )
    }

    enum CodingKeys: String, CodingKey {
        case protocolVersion = "protocol_version"
        case requestId = "request_id"
        case providerId = "provider_id"
        case agentId = "agent_id"
        case message
        case source
        case eventType = "event_type"
        case payload
        case createdAt = "created_at"
        case expiresAt = "expires_at"
        case nonce
        case idempotencyKey = "idempotency_key"
        case hostInstanceId = "host_instance_id"
        case signatureAlgorithm = "signature_algorithm"
        case signature
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            protocolVersion: try container.decodeIfPresent(Int.self, forKey: .protocolVersion) ?? 2,
            requestId: try container.decodeIfPresent(String.self, forKey: .requestId) ?? "",
            providerId: try container.decodeIfPresent(String.self, forKey: .providerId) ?? "",
            agentId: try container.decodeIfPresent(String.self, forKey: .agentId) ?? "",
            message: try container.decodeIfPresent(String.self, forKey: .message) ?? "",
            source: try container.decodeIfPresent(String.self, forKey: .source) ?? "",
            eventType: try container.decodeIfPresent(String.self, forKey: .eventType) ?? "",
            payload: try container.decodeIfPresent([String: NapaxiJSONValue].self, forKey: .payload) ?? [:],
            createdAt: try container.decodeIfPresent(String.self, forKey: .createdAt) ?? "",
            expiresAt: try container.decodeIfPresent(String.self, forKey: .expiresAt) ?? "",
            nonce: try container.decodeIfPresent(String.self, forKey: .nonce) ?? "",
            idempotencyKey: try container.decodeIfPresent(String.self, forKey: .idempotencyKey) ?? "",
            hostInstanceId: try container.decodeIfPresent(String.self, forKey: .hostInstanceId) ?? "",
            signatureAlgorithm: try container.decodeIfPresent(String.self, forKey: .signatureAlgorithm) ?? "",
            signature: try container.decodeIfPresent(String.self, forKey: .signature)
        )
    }

    public func encode(to encoder: Encoder) throws {
        try NapaxiJSONValue.object(toJson()).encode(to: encoder)
    }

    public init(jsonString: String) throws {
        let value = try NapaxiRawJSON(jsonString: jsonString).value
        guard case .object(let object) = value else {
            throw NapaxiError.invalidJSON("Agent trigger request JSON must be an object")
        }
        self = Self.fromMap(object)
    }

    public static func fromJsonString(_ value: String) throws -> Self {
        try Self(jsonString: value)
    }

    public func jsonString() throws -> String {
        try NapaxiAgentProviderHost.jsonString(from: self)
    }

    public func toJson() -> [String: NapaxiJSONValue] {
        var object: [String: NapaxiJSONValue] = [
            "protocol_version": .number(Double(protocolVersion)),
            "request_id": .string(requestId),
            "provider_id": .string(providerId),
            "agent_id": .string(agentId),
            "message": .string(message),
            "source": .string(source),
            "event_type": .string(eventType),
            "payload": .object(payload),
            "created_at": .string(createdAt),
            "expires_at": .string(expiresAt),
            "nonce": .string(nonce),
            "idempotency_key": .string(idempotencyKey),
        ]
        object.setNonEmpty("host_instance_id", hostInstanceId)
        object.setNonEmpty("signature_algorithm", signatureAlgorithm)
        object.setNonEmpty("signature", signature)
        return object
    }

    public func toJsonString() throws -> String {
        try NapaxiRawJSON(.object(toJson())).jsonString()
    }
}

public struct NapaxiAcceptedAgentTrigger: Codable, Equatable, Sendable {
    public var request: NapaxiAgentTriggerRequest
    public var displayName: String

    public init(request: NapaxiAgentTriggerRequest, displayName: String) {
        self.request = request
        self.displayName = displayName
    }
}

public final class NapaxiAgentProviderHost: @unchecked Sendable {
    public typealias URLOpener = @Sendable (URL) async -> Bool

    public static let triggerSignatureAlgorithm = "hmac-sha256-v1"
    public static let defaultInstallTimeoutSeconds: UInt64 = 10 * 60
    static let consumedTriggerRequestIdsKey = "agent_provider.consumed_triggers.v1"

    public private(set) var pendingProviderInstall: NapaxiAgentProviderDescriptor?
    public private(set) var pendingTriggerRequestJSON: String?
    public private(set) var pendingActionResultJSON: String?

    public let callbackScheme: String?
    public let hostInfo: NapaxiAgentProviderHostInfo

    private var pendingInstall: PendingInstall?
    private var pendingAction: PendingAction?
    private var consumedTriggerRequestIds = Set<String>()
    private let consumedTriggerStore: UserDefaults?
    private let lock = NSLock()

    public init(
        callbackScheme: String? = nil,
        hostInfo: NapaxiAgentProviderHostInfo? = nil,
        consumedTriggerStore: UserDefaults? = .standard
    ) {
        self.callbackScheme = callbackScheme
        let resolvedScheme = callbackScheme ?? hostInfo?.callbackScheme ?? Self.defaultCallbackScheme()
        self.hostInfo = hostInfo ?? NapaxiAgentProviderHostInfo(callbackScheme: resolvedScheme)
        self.consumedTriggerStore = consumedTriggerStore
        self.consumedTriggerRequestIds = Set(
            consumedTriggerStore?.stringArray(forKey: Self.consumedTriggerRequestIdsKey) ?? []
        )
    }

    @discardableResult
    public func handleOpenURL(_ url: URL) -> Bool {
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func value(_ name: String) -> String? {
            items.first(where: { $0.name == name })?.value
        }

        if let installResult = value("install_result") {
            return handleInstallCallback(installResultJSON: installResult)
        }
        if let result = value("result"), !result.isEmpty {
            pendingActionResultJSON = result
            return handleActionCallback(resultJSON: result)
        }
        if isActionCallbackURL(url) {
            return handleActionCallback(
                resultJSON: Self.failedActionResultJSON(
                    requestId: pendingActionRequestId() ?? "",
                    message: "Provider action returned no result"
                )
            )
        }
        if let trigger = value("trigger_request"), !trigger.isEmpty {
            pendingTriggerRequestJSON = trigger
            return true
        }
        guard let installURL = value("install_url"), !installURL.isEmpty else {
            return false
        }
        let actionURL = value("action_url") ?? installURL
        let domain = value("universal_link_domain")
            ?? URL(string: installURL)?.host
            ?? ""
        pendingProviderInstall = NapaxiAgentProviderDescriptor(
            platform: "ios",
            label: value("label") ?? domain,
            installUrl: installURL,
            actionUrl: actionURL,
            universalLinkDomain: domain,
            iosBundleId: value("ios_bundle_id") ?? "",
            iosTeamId: value("ios_team_id") ?? ""
        )
        return true
    }

    public func createInstallRequest(now: Date = Date()) -> NapaxiAgentInstallRequest {
        let created = Self.isoString(now)
        let expires = Self.isoString(now.addingTimeInterval(10 * 60))
        let scheme = hostInfo.callbackScheme
        return NapaxiAgentInstallRequest(
            protocolVersion: 2,
            requestId: Self.randomHex(byteCount: 16),
            nonce: Self.randomHex(byteCount: 16),
            hostPackageName: hostInfo.bundleId,
            createdAt: created,
            expiresAt: expires,
            hostInstanceId: Self.randomHex(byteCount: 16),
            hostSharedSecret: Self.randomHex(byteCount: 32),
            hostBundleId: hostInfo.bundleId,
            hostTeamId: hostInfo.teamId,
            hostCallbackScheme: scheme,
            callbackUrl: scheme.isEmpty ? "" : "\(scheme)://agent-provider/install-callback",
            backgroundTriggerSupported: hostInfo.backgroundTriggerSupported,
            hostBackgroundTriggerService: hostInfo.backgroundTriggerService
        )
    }

    public func installURL(
        for provider: NapaxiAgentProviderDescriptor,
        request: NapaxiAgentInstallRequest
    ) throws -> URL {
        guard !hostInfo.callbackScheme.isEmpty else {
            throw NapaxiError.invalidState("Host app must declare a URL scheme for iOS provider callbacks")
        }
        guard let installURL = URL(string: provider.installUrl),
              let requestJSON = try? request.jsonString(),
              let handoffURL = Self.appendQueryItem("install_request", value: requestJSON, to: installURL) else {
            throw NapaxiError.invalidState("Unable to build provider install URL")
        }
        return handoffURL
    }

    public func requestInstall(
        provider: NapaxiAgentProviderDescriptor,
        timeoutSeconds: UInt64 = NapaxiAgentProviderHost.defaultInstallTimeoutSeconds,
        openURL: @escaping URLOpener
    ) async throws -> NapaxiAgentProviderInstallResponse {
        let request = createInstallRequest()
        let handoffURL = try installURL(for: provider, request: request)

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                lock.lock()
                if pendingInstall != nil {
                    lock.unlock()
                    continuation.resume(throwing: NapaxiError.invalidState("Agent provider install already in progress"))
                    return
                }
                pendingInstall = PendingInstall(provider: provider, request: request, continuation: continuation)
                lock.unlock()

                Task {
                    let opened = await openURL(handoffURL)
                    if !opened {
                        self.finishInstall(.failure(NapaxiError.invalidState("Unable to open provider install URL")))
                    }
                }
                Task {
                    try? await Task.sleep(nanoseconds: timeoutSeconds * 1_000_000_000)
                    self.finishInstall(.failure(NapaxiError.invalidState("Timed out waiting for provider install callback")))
                }
            }
        } onCancel: {
            finishInstall(.failure(CancellationError()))
        }
    }

    public func actionURL(requestJSON: String) throws -> URL {
        guard let request = Self.parseJSONObject(requestJSON),
              let proposal = request["proposal"] as? [String: Any],
              let action = request["action"] as? [String: Any],
              var package = request["package"] as? [String: Any],
              let binding = package["install_binding"] as? [String: Any] else {
            throw NapaxiError.invalidJSON("Invalid provider action request JSON")
        }
        guard binding["platform"] as? String == "ios" else {
            throw NapaxiError.invalidState("Provider action package is not installed with an iOS binding")
        }
        guard let actionURLString = binding["action_url"] as? String,
              let actionURL = URL(string: actionURLString),
              !actionURLString.isEmpty else {
            throw NapaxiError.invalidState("Provider action binding is missing action_url")
        }
        let scheme = binding["host_callback_scheme"] as? String ?? hostInfo.callbackScheme
        guard !scheme.isEmpty else {
            throw NapaxiError.invalidState("Host callback scheme is unavailable")
        }
        if var safeBinding = package["install_binding"] as? [String: Any] {
            safeBinding.removeValue(forKey: "host_shared_secret")
            package["install_binding"] = safeBinding
        }
        let requestId = proposal["request_id"] as? String ?? ""
        let callbackURL = "\(scheme)://agent-provider/action-callback?request_id=\(Self.urlEncode(requestId))"
        guard
            let proposalJSON = Self.jsonString(fromJSONObject: proposal),
            let actionJSON = Self.jsonString(fromJSONObject: action),
            let packageJSON = Self.jsonString(fromJSONObject: package),
            let withProposal = Self.appendQueryItem("proposal", value: proposalJSON, to: actionURL),
            let withAction = Self.appendQueryItem("action", value: actionJSON, to: withProposal),
            let withPackage = Self.appendQueryItem("package", value: packageJSON, to: withAction),
            let handoffURL = Self.appendQueryItem("callback_url", value: callbackURL, to: withPackage)
        else {
            throw NapaxiError.invalidState("Unable to build provider action URL")
        }
        return handoffURL
    }

    public func executeProviderAction(
        requestJSON: String,
        openURL: @escaping URLOpener
    ) async -> String {
        let requestId = (Self.parseJSONObject(requestJSON)?["proposal"] as? [String: Any])?["request_id"] as? String ?? ""
        do {
            let handoffURL = try actionURL(requestJSON: requestJSON)
            return await withTaskCancellationHandler {
                await withCheckedContinuation { continuation in
                    lock.lock()
                    if pendingAction != nil {
                        lock.unlock()
                        continuation.resume(returning: Self.failedActionResultJSON(requestId: requestId, message: "Agent provider action already in progress"))
                        return
                    }
                    pendingAction = PendingAction(requestId: requestId, continuation: continuation)
                    lock.unlock()

                    Task {
                        let opened = await openURL(handoffURL)
                        if !opened {
                            self.finishAction(resultJSON: Self.failedActionResultJSON(requestId: requestId, message: "Provider action handoff failed"))
                        }
                    }
                }
            } onCancel: {
                finishAction(resultJSON: Self.failedActionResultJSON(requestId: requestId, message: "Provider action cancelled"))
            }
        } catch {
            return Self.failedActionResultJSON(requestId: requestId, message: error.localizedDescription)
        }
    }

    public func consumePendingTriggerRequest() throws -> NapaxiAgentTriggerRequest? {
        guard let json = consumePendingTriggerRequestJSON() else {
            return nil
        }
        return try NapaxiAgentTriggerRequest(jsonString: json)
    }

    public func getPendingAgentTriggerRequest() throws -> NapaxiAgentTriggerRequest? {
        guard let json = getPendingAgentTriggerRequestJSON() else {
            return nil
        }
        return try NapaxiAgentTriggerRequest(jsonString: json)
    }

    @discardableResult
    public func validateTrigger(
        _ request: NapaxiAgentTriggerRequest,
        installedPackageJSON: String,
        now: Date = Date()
    ) throws -> [String: NapaxiJSONValue] {
        let package = try NapaxiRawJSON(jsonString: installedPackageJSON).value
        guard case .object(let packageObject) = package else {
            throw NapaxiError.invalidJSON("Installed Agent package must be a JSON object")
        }
        return try validateTrigger(request, installedPackage: packageObject, now: now)
    }

    @discardableResult
    public func validateTrigger(
        _ request: NapaxiAgentTriggerRequest,
        installedPackage: [String: NapaxiJSONValue],
        now: Date = Date()
    ) throws -> [String: NapaxiJSONValue] {
        if request.protocolVersion < 2 {
            throw NapaxiError.invalidState("Agent trigger protocol v2 is required")
        }
        if request.requestId.isEmpty ||
            request.providerId.isEmpty ||
            request.agentId.isEmpty ||
            request.message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
            request.nonce.isEmpty ||
            request.idempotencyKey.isEmpty {
            throw NapaxiError.invalidState("Agent trigger is missing required fields")
        }
        guard let expiresAt = Self.parseISODate(request.expiresAt), expiresAt > now else {
            throw NapaxiError.invalidState("Agent trigger expired")
        }
        let consumed = {
            lock.lock()
            defer { lock.unlock() }
            return consumedTriggerIdsLocked().contains(request.requestId)
        }()
        if consumed {
            throw NapaxiError.invalidState("Agent trigger has already been consumed")
        }
        guard !request.hostInstanceId.isEmpty,
              request.signatureAlgorithm == Self.triggerSignatureAlgorithm,
              let signature = request.signature,
              !signature.isEmpty else {
            throw NapaxiError.invalidState("Agent trigger is missing trusted signature fields")
        }
        guard installedPackage["provider_id"]?.stringValue == request.providerId else {
            throw NapaxiError.invalidState("Agent trigger provider does not match installed Agent")
        }
        guard installedPackage["agent_id"]?.stringValue == request.agentId else {
            throw NapaxiError.invalidState("Triggered Agent is not installed")
        }
        guard case .object(let binding)? = installedPackage["install_binding"],
              binding["host_instance_id"]?.stringValue == request.hostInstanceId,
              let secret = binding["host_shared_secret"]?.stringValue,
              !secret.isEmpty else {
            throw NapaxiError.invalidState("Agent trigger is not bound to a trusted host")
        }
        let expected = Self.hmacSHA256Base64NoPad(secret: secret, payload: Self.triggerSignaturePayload(request))
        guard expected == signature else {
            throw NapaxiError.invalidState("Agent trigger signature is invalid")
        }
        return installedPackage
    }

    public func acceptTrigger(
        _ request: NapaxiAgentTriggerRequest,
        installedPackage: [String: NapaxiJSONValue],
        now: Date = Date()
    ) throws -> NapaxiAcceptedAgentTrigger {
        let package = try validateTrigger(request, installedPackage: installedPackage, now: now)
        do {
            lock.lock()
            defer { lock.unlock() }
            var consumed = consumedTriggerIdsLocked()
            consumed.insert(request.requestId)
            consumedTriggerRequestIds = consumed
            consumedTriggerStore?.set(Array(consumed).sorted(), forKey: Self.consumedTriggerRequestIdsKey)
        }
        let displayName = package["display_name"]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines)
        return NapaxiAcceptedAgentTrigger(
            request: request,
            displayName: displayName?.isEmpty == false ? displayName! : request.agentId
        )
    }

    public func acceptTrigger(
        _ request: NapaxiAgentTriggerRequest,
        installedPackageJSON: String,
        now: Date = Date()
    ) throws -> NapaxiAcceptedAgentTrigger {
        let package = try validateTrigger(request, installedPackageJSON: installedPackageJSON, now: now)
        return try acceptTrigger(request, installedPackage: package, now: now)
    }

    public func consumePendingProviderInstall() -> NapaxiAgentProviderDescriptor? {
        defer { pendingProviderInstall = nil }
        return pendingProviderInstall
    }

    public func getPendingProviderInstallRequest() -> NapaxiAgentProviderDescriptor? {
        pendingProviderInstall
    }

    public func clearPendingProviderInstallRequest() {
        pendingProviderInstall = nil
    }

    public func consumePendingTriggerRequestJSON() -> String? {
        defer { pendingTriggerRequestJSON = nil }
        return pendingTriggerRequestJSON
    }

    public func getPendingAgentTriggerRequestJSON() -> String? {
        pendingTriggerRequestJSON
    }

    public func clearPendingAgentTriggerRequest() {
        pendingTriggerRequestJSON = nil
    }

    private func consumedTriggerIdsLocked() -> Set<String> {
        guard let consumedTriggerStore else {
            return consumedTriggerRequestIds
        }
        let persisted = Set(consumedTriggerStore.stringArray(forKey: Self.consumedTriggerRequestIdsKey) ?? [])
        if persisted != consumedTriggerRequestIds {
            consumedTriggerRequestIds.formUnion(persisted)
        }
        return consumedTriggerRequestIds
    }

    public func consumePendingActionResultJSON() -> String? {
        defer { pendingActionResultJSON = nil }
        return pendingActionResultJSON
    }

    public static func defaultCallbackScheme() -> String {
        let types = Bundle.main.object(forInfoDictionaryKey: "CFBundleURLTypes") as? [[String: Any]]
        let schemes = types?
            .flatMap { $0["CFBundleURLSchemes"] as? [String] ?? [] }
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } ?? []
        return schemes.first(where: { $0.localizedCaseInsensitiveContains("agent") })
            ?? schemes.first
            ?? ""
    }

    static func jsonString<T: Encodable>(from value: T) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return String(data: try encoder.encode(value), encoding: .utf8) ?? "{}"
    }

    public static func triggerSignaturePayload(_ request: NapaxiAgentTriggerRequest) -> String {
        let payloadHash = sha256Base64NoPad(canonicalJSON(.object(request.payload)))
        return [
            "request_id=\(request.requestId)",
            "provider_id=\(request.providerId)",
            "agent_id=\(request.agentId)",
            "message=\(request.message)",
            "source=\(request.source)",
            "event_type=\(request.eventType)",
            "payload_sha256=\(payloadHash)",
            "created_at=\(request.createdAt)",
            "expires_at=\(request.expiresAt)",
            "nonce=\(request.nonce)",
            "idempotency_key=\(request.idempotencyKey)",
            "host_instance_id=\(request.hostInstanceId)",
        ].joined(separator: "\n")
    }

    public static func triggerSignature(
        for request: NapaxiAgentTriggerRequest,
        hostSharedSecret: String
    ) -> String {
        hmacSHA256Base64NoPad(secret: hostSharedSecret, payload: triggerSignaturePayload(request))
    }

    private func handleInstallCallback(installResultJSON: String) -> Bool {
        lock.lock()
        let pending = pendingInstall
        pendingInstall = nil
        lock.unlock()
        guard let pending else {
            return true
        }
        guard let installResult = try? NapaxiAgentInstallResult(jsonString: installResultJSON) else {
            pending.continuation.resume(throwing: NapaxiError.invalidJSON("Invalid provider install result JSON"))
            return true
        }
        guard let expiresAt = Self.parseISODate(pending.request.expiresAt), expiresAt > Date() else {
            pending.continuation.resume(throwing: NapaxiError.invalidState("Install request expired"))
            return true
        }
        guard installResult.requestId == pending.request.requestId,
              installResult.nonce == pending.request.nonce else {
            pending.continuation.resume(throwing: NapaxiError.invalidState("Install result does not match the request"))
            return true
        }
        guard installResult.status == "succeeded" else {
            let message = installResult.errorMessage ?? "Provider install failed"
            pending.continuation.resume(throwing: NapaxiError.invalidState(message))
            return true
        }
        let binding: [String: NapaxiJSONValue] = [
            "platform": .string("ios"),
            "app_package_name": .string(""),
            "activity_name": .string(""),
            "signing_cert_sha256": .string(""),
            "installed_at": .string(Self.isoString(Date())),
            "install_request_id": .string(installResult.requestId),
            "protocol_version": .number(Double(pending.request.protocolVersion)),
            "host_package_name": .string(pending.request.hostPackageName),
            "host_signing_cert_sha256": .string(pending.request.hostSigningCertSha256),
            "host_instance_id": .string(pending.request.hostInstanceId),
            "host_shared_secret": .string(pending.request.hostSharedSecret),
            "ios_bundle_id": .string(pending.provider.iosBundleId),
            "ios_team_id": .string(pending.provider.iosTeamId),
            "install_url": .string(pending.provider.installUrl),
            "action_url": .string(pending.provider.actionUrl),
            "universal_link_domain": .string(pending.provider.universalLinkDomain),
            "host_bundle_id": .string(pending.request.hostBundleId),
            "host_team_id": .string(pending.request.hostTeamId),
            "host_callback_scheme": .string(pending.request.hostCallbackScheme),
            "background_trigger_supported": .bool(pending.request.backgroundTriggerSupported),
            "host_background_trigger_service": .string(pending.request.hostBackgroundTriggerService),
        ]
        pending.continuation.resume(returning: NapaxiAgentProviderInstallResponse(
            installResultJSON: installResultJSON,
            installBinding: binding
        ))
        return true
    }

    private func handleActionCallback(resultJSON: String) -> Bool {
        finishAction(resultJSON: resultJSON)
        return true
    }

    private func isActionCallbackURL(_ url: URL) -> Bool {
        url.host == "agent-provider" && url.path == "/action-callback"
    }

    private func pendingActionRequestId() -> String? {
        lock.lock()
        defer { lock.unlock() }
        return pendingAction?.requestId
    }

    private func finishInstall(_ result: Result<NapaxiAgentProviderInstallResponse, Error>) {
        lock.lock()
        let pending = pendingInstall
        pendingInstall = nil
        lock.unlock()
        guard let pending else { return }
        switch result {
        case .success(let response):
            pending.continuation.resume(returning: response)
        case .failure(let error):
            pending.continuation.resume(throwing: error)
        }
    }

    private func finishAction(resultJSON: String) {
        lock.lock()
        let pending = pendingAction
        pendingAction = nil
        lock.unlock()
        pending?.continuation.resume(returning: resultJSON)
    }

    private static func parseJSONObject(_ value: String) -> [String: Any]? {
        guard let data = value.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data),
              let map = object as? [String: Any] else {
            return nil
        }
        return map
    }

    private static func jsonString(fromJSONObject value: Any) -> String? {
        guard JSONSerialization.isValidJSONObject(value),
              let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]) else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    private static func appendQueryItem(_ name: String, value: String, to url: URL) -> URL? {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return nil
        }
        var items = components.queryItems ?? []
        items.append(URLQueryItem(name: name, value: value))
        components.queryItems = items
        return components.url
    }

    private static func isoString(_ date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }

    private static func parseISODate(_ value: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: value) {
            return date
        }
        return ISO8601DateFormatter().date(from: value)
    }

    private static func urlEncode(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? value
    }

    private static func randomHex(byteCount: Int) -> String {
        var bytes = [UInt8](repeating: 0, count: byteCount)
        let status = SecRandomCopyBytes(nil, byteCount, &bytes)
        if status != errSecSuccess {
            return (0..<byteCount).map { _ in String(format: "%02x", Int.random(in: 0...255)) }.joined()
        }
        return bytes.map { String(format: "%02x", $0) }.joined()
    }

    private static func failedActionResultJSON(requestId: String, message: String) -> String {
        jsonString(fromJSONObject: [
            "request_id": requestId,
            "status": "failed",
            "result": [:],
            "error": message,
            "completed_at": isoString(Date()),
        ]) ?? "{}"
    }

    private static func canonicalJSON(_ value: NapaxiJSONValue) -> String {
        switch value {
        case .null:
            return "null"
        case .bool(let value):
            return value ? "true" : "false"
        case .number(let value):
            if value.rounded() == value {
                return String(Int64(value))
            }
            return String(value)
        case .string(let value):
            return jsonFragmentString(value)
        case .array(let values):
            return "[\(values.map(canonicalJSON).joined(separator: ","))]"
        case .object(let object):
            let entries = object.keys.sorted().map { key -> String in
                "\(jsonFragmentString(key)):\(canonicalJSON(object[key] ?? .null))"
            }
            return "{\(entries.joined(separator: ","))}"
        }
    }

    private static func jsonFragmentString(_ value: String) -> String {
        let options: JSONSerialization.WritingOptions
        if #available(iOS 13.0, macOS 10.15, *) {
            options = [.fragmentsAllowed, .withoutEscapingSlashes]
        } else {
            options = [.fragmentsAllowed]
        }
        let data = try? JSONSerialization.data(withJSONObject: value, options: options)
        return data.flatMap { String(data: $0, encoding: .utf8) } ?? "\"\""
    }

    private static func sha256Base64NoPad(_ value: String) -> String {
        let digest = SHA256.hash(data: Data(value.utf8))
        return Data(digest).base64EncodedString().replacingOccurrences(of: "=", with: "")
    }

    private static func hmacSHA256Base64NoPad(secret: String, payload: String) -> String {
        let key = SymmetricKey(data: Data(secret.utf8))
        let code = HMAC<SHA256>.authenticationCode(for: Data(payload.utf8), using: key)
        return Data(code).base64EncodedString().replacingOccurrences(of: "=", with: "")
    }

    private struct PendingInstall {
        var provider: NapaxiAgentProviderDescriptor
        var request: NapaxiAgentInstallRequest
        var continuation: CheckedContinuation<NapaxiAgentProviderInstallResponse, Error>
    }

    private struct PendingAction {
        var requestId: String
        var continuation: CheckedContinuation<String, Never>
    }
}

private extension Dictionary where Key == String, Value == NapaxiJSONValue {
    func string(_ key: String) -> String? {
        self[key]?.stringValue
    }

    func bool(_ key: String) -> Bool? {
        self[key]?.boolValue
    }

    func int(_ key: String) -> Int? {
        guard case .number(let number)? = self[key], number.isFinite else { return nil }
        return Int(number)
    }

    func object(_ key: String) -> [String: NapaxiJSONValue]? {
        if case .object(let object)? = self[key] {
            return object
        }
        return nil
    }

    mutating func setNonEmpty(_ key: String, _ value: String?) {
        guard let value, !value.isEmpty else { return }
        self[key] = .string(value)
    }
}
