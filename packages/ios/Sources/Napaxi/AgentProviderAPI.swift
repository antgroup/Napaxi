import Foundation

#if canImport(UIKit)
import UIKit
#endif

public protocol NapaxiAgentProviderDiscovery: Sendable {
    func discoverAgentProviders() async throws -> [NapaxiAgentProviderDescriptor]
}

public struct NapaxiAgentProviderAPI: Sendable {
    public typealias RegisterPackage = @Sendable (String) throws -> NapaxiJSONValue
    public typealias GetPackage = @Sendable (String) throws -> NapaxiJSONValue?
    public typealias DiscoverProviders = @Sendable () async throws -> [NapaxiAgentProviderDescriptor]
    public static let defaultInstallTimeoutSeconds: UInt64 = NapaxiAgentProviderHost.defaultInstallTimeoutSeconds

    public let host: NapaxiAgentProviderHost

    private let registerPackage: RegisterPackage
    private let getPackage: GetPackage
    private let discoverProvidersHandler: DiscoverProviders
    private let openURL: NapaxiAgentProviderHost.URLOpener

    public init(
        host: NapaxiAgentProviderHost,
        registerPackage: @escaping RegisterPackage,
        getPackage: @escaping GetPackage,
        discoverProviders: @escaping DiscoverProviders = { [] },
        openURL: @escaping NapaxiAgentProviderHost.URLOpener = Self.defaultOpenURL
    ) {
        self.host = host
        self.registerPackage = registerPackage
        self.getPackage = getPackage
        self.discoverProvidersHandler = discoverProviders
        self.openURL = openURL
    }

    public init(
        host: NapaxiAgentProviderHost,
        registerPackage: @escaping RegisterPackage,
        getPackage: @escaping GetPackage,
        discovery: NapaxiAgentProviderDiscovery,
        openURL: @escaping NapaxiAgentProviderHost.URLOpener = Self.defaultOpenURL
    ) {
        self.init(
            host: host,
            registerPackage: registerPackage,
            getPackage: getPackage,
            discoverProviders: { try await discovery.discoverAgentProviders() },
            openURL: openURL
        )
    }

    @discardableResult
    public func handleOpenURL(_ url: URL) -> Bool {
        host.handleOpenURL(url)
    }

    public func discoverProviders() async throws -> [NapaxiAgentProviderDescriptor] {
        try await discoverProvidersHandler()
    }

    public func requestInstall(
        _ provider: NapaxiAgentProviderDescriptor,
        timeoutSeconds: UInt64 = NapaxiAgentProviderAPI.defaultInstallTimeoutSeconds
    ) async throws -> NapaxiAgentAppPackage {
        try await requestInstallJSON(provider, timeoutSeconds: timeoutSeconds)
            .decodedObject(of: NapaxiAgentAppPackage.self)
    }

    public func requestInstallJSON(
        _ provider: NapaxiAgentProviderDescriptor,
        timeoutSeconds: UInt64 = NapaxiAgentProviderAPI.defaultInstallTimeoutSeconds
    ) async throws -> NapaxiJSONValue {
        let response = try await host.requestInstall(
            provider: provider,
            timeoutSeconds: timeoutSeconds,
            openURL: openURL
        )
        return try registerInstallResponse(response)
    }

    public func requestInstallPackage(
        _ provider: NapaxiAgentProviderDescriptor,
        timeoutSeconds: UInt64 = NapaxiAgentProviderAPI.defaultInstallTimeoutSeconds
    ) async throws -> NapaxiAgentAppPackage {
        try await requestInstall(provider, timeoutSeconds: timeoutSeconds)
    }

    public func installFromLaunchIntent(
        timeoutSeconds: UInt64 = NapaxiAgentProviderAPI.defaultInstallTimeoutSeconds
    ) async throws -> NapaxiAgentAppPackage? {
        try await installFromLaunchIntentJSON(timeoutSeconds: timeoutSeconds)?
            .decodedObject(of: NapaxiAgentAppPackage.self)
    }

    public func installFromLaunchIntentJSON(
        timeoutSeconds: UInt64 = NapaxiAgentProviderAPI.defaultInstallTimeoutSeconds
    ) async throws -> NapaxiJSONValue? {
        guard let pending = host.pendingProviderInstall else {
            return nil
        }
        let provider = try await resolvedProvider(for: pending)
        let installed = try await requestInstallJSON(provider, timeoutSeconds: timeoutSeconds)
        _ = host.consumePendingProviderInstall()
        return installed
    }

    public func installPackageFromLaunchIntent(
        timeoutSeconds: UInt64 = NapaxiAgentProviderAPI.defaultInstallTimeoutSeconds
    ) async throws -> NapaxiAgentAppPackage? {
        try await installFromLaunchIntent(timeoutSeconds: timeoutSeconds)
    }

    public func consumePendingTriggerRequest() throws -> NapaxiAgentTriggerRequest? {
        guard let json = host.pendingTriggerRequestJSON, !json.isEmpty else {
            return nil
        }
        return try NapaxiAgentTriggerRequest(jsonString: json)
    }

    public func consumePendingTrigger() throws -> NapaxiAgentTriggerRequest? {
        try consumePendingTriggerRequest()
    }

    @discardableResult
    public func validateTrigger(_ request: NapaxiAgentTriggerRequest, now: Date = Date()) throws -> [String: NapaxiJSONValue] {
        let package = try installedPackage(for: request.agentId)
        return try host.validateTrigger(request, installedPackage: package, now: now)
    }

    public func validateTriggerPackage(_ request: NapaxiAgentTriggerRequest, now: Date = Date()) throws -> NapaxiAgentAppPackage {
        let package = try validateTrigger(request, now: now)
        return NapaxiAgentAppPackage(raw: package)
    }

    public func acceptTrigger(_ request: NapaxiAgentTriggerRequest, now: Date = Date()) throws -> NapaxiAcceptedAgentTrigger {
        let package = try installedPackage(for: request.agentId)
        let accepted = try host.acceptTrigger(request, installedPackage: package, now: now)
        clearPendingTriggerIfMatching(request)
        return accepted
    }

    public static let defaultOpenURL: NapaxiAgentProviderHost.URLOpener = { url in
        #if canImport(UIKit)
        return await withCheckedContinuation { continuation in
            Task { @MainActor in
                UIApplication.shared.open(url, options: [:]) { opened in
                    continuation.resume(returning: opened)
                }
            }
        }
        #else
        return false
        #endif
    }

    private func registerInstallResponse(_ response: NapaxiAgentProviderInstallResponse) throws -> NapaxiJSONValue {
        let result = try NapaxiAgentInstallResult(jsonString: response.installResultJSON)
        guard var package = result.packageRaw else {
            throw NapaxiError.invalidState("Provider did not return an Agent package")
        }
        package["install_binding"] = .object(response.installBinding)
        return try registerPackage(package.jsonString())
    }

    private func installedPackage(for agentId: String) throws -> [String: NapaxiJSONValue] {
        guard let value = try getPackage(agentId) else {
            throw NapaxiError.invalidState("Triggered Agent is not installed")
        }
        guard case .object(let package) = value else {
            throw NapaxiError.invalidJSON("Installed Agent package must be a JSON object")
        }
        return package
    }

    private func clearPendingTriggerIfMatching(_ request: NapaxiAgentTriggerRequest) {
        guard let pendingJSON = host.pendingTriggerRequestJSON, !pendingJSON.isEmpty else {
            return
        }
        guard let pending = try? NapaxiAgentTriggerRequest(jsonString: pendingJSON) else {
            return
        }
        if pending.requestId == request.requestId {
            host.clearPendingAgentTriggerRequest()
        }
    }

    private func resolvedProvider(for pending: NapaxiAgentProviderDescriptor) async throws -> NapaxiAgentProviderDescriptor {
        if !pending.installUrl.isEmpty && !pending.actionUrl.isEmpty {
            return pending
        }
        let discovered = try await discoverProviders()
        return discovered.first { candidate in
            candidate.packageName == pending.packageName && !pending.packageName.isEmpty ||
            candidate.iosBundleId == pending.iosBundleId && !pending.iosBundleId.isEmpty ||
            candidate.universalLinkDomain == pending.universalLinkDomain && !pending.universalLinkDomain.isEmpty
        } ?? pending
    }
}

public typealias AgentProviderInstallApi = NapaxiAgentProviderAPI
public typealias AgentProviderTriggerApi = NapaxiAgentProviderAPI

public final class NapaxiAgentProviderActionExecutor: NapaxiAgentAppActionExecutor, AgentAppActionExecutor, @unchecked Sendable {
    private let host: NapaxiAgentProviderHost
    private let openURL: NapaxiAgentProviderHost.URLOpener

    public init(
        host: NapaxiAgentProviderHost,
        openURL: @escaping NapaxiAgentProviderHost.URLOpener = NapaxiAgentProviderAPI.defaultOpenURL
    ) {
        self.host = host
        self.openURL = openURL
    }

    public func executeAgentAppAction(requestJSON: String) async -> String {
        await host.executeProviderAction(requestJSON: requestJSON, openURL: openURL)
    }

    public func execute(_ request: NapaxiAgentAppActionRequest) async throws -> NapaxiAgentAppActionResult {
        let resultJSON = await executeAgentAppAction(requestJSON: try agentProviderRequestToJson(request))
        return try NapaxiRawJSON(jsonString: resultJSON).value.decodedObject(of: NapaxiAgentAppActionResult.self)
    }
}

public typealias IosAgentProviderActionExecutor = NapaxiAgentProviderActionExecutor

public func agentProviderRequestToJSON(_ request: NapaxiAgentAppActionRequest) -> NapaxiJSONValue {
    .object([
        "proposal": .object(request.proposal.raw),
        "action": .object(request.action.raw),
        "package": .object(request.package),
    ])
}

public func agentProviderRequestToJson(_ request: NapaxiAgentAppActionRequest) throws -> String {
    try NapaxiRawJSON(agentProviderRequestToJSON(request)).jsonString()
}
