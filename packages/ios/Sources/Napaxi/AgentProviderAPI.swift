import Foundation

#if canImport(UIKit)
import UIKit
#endif

/// Provider-owned failure details. iOS returns an unsupported snapshot in this release.
public struct AgentAppDiagnosticReport: Sendable, Equatable {
    public let id: String
    public let kind: String
    public let timestamp: String
    public let appPackage: String
    public let versionName: String
    public let versionCode: Int
    public let exceptionType: String
    public let message: String
    public let stackTrace: String
    public let description: String
    public let thread: String
    public let process: String
    public let breadcrumbs: [[String: String]]
    public let metadata: [String: String]
}

/// Provider-owned structured runtime event.
public struct AgentAppDiagnosticLogEntry: Sendable, Equatable {
    public let id: String
    public let timestamp: String
    public let level: String
    public let module: String
    public let event: String
    public let message: String
    public let traceId: String
    public let thread: String
    public let metadata: [String: String]
}

/// Typed diagnostics result with an explicit unsupported state.
public struct AgentAppDiagnosticsSnapshot: Sendable, Equatable {
    public let supported: Bool
    public let reports: [AgentAppDiagnosticReport]
    public let logs: [AgentAppDiagnosticLogEntry]
    public let detailedLoggingEnabled: Bool
    public let error: String

    public static let unsupported = AgentAppDiagnosticsSnapshot(
        supported: false,
        reports: [],
        logs: [],
        detailedLoggingEnabled: false,
        error: "unsupported_platform"
    )
}

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

    /// Finds an installed Provider by its package or bundle identifier.
    public func discoverProviderForPackage(
        _ packageName: String
    ) async throws -> NapaxiAgentProviderDescriptor? {
        let expected = packageName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !expected.isEmpty else { return nil }
        return try await discoverProviders().first {
            $0.packageName == expected || $0.iosBundleId == expected
        }
    }

    public func requestInstall(
        _ provider: NapaxiAgentProviderDescriptor,
        timeoutSeconds: UInt64 = NapaxiAgentProviderAPI.defaultInstallTimeoutSeconds
    ) async throws -> NapaxiAgentAppPackage {
        try await requestInstallJSON(provider, timeoutSeconds: timeoutSeconds)
            .decodedObject(of: NapaxiAgentAppPackage.self)
    }

    /// Discovers and runs the trusted enable handshake for an installed app.
    public func enableInstalledProvider(
        _ packageName: String,
        timeoutSeconds: UInt64 = NapaxiAgentProviderAPI.defaultInstallTimeoutSeconds
    ) async throws -> NapaxiAgentAppPackage {
        guard let provider = try await discoverProviderForPackage(packageName) else {
            throw NapaxiError.invalidState("Installed Agent App Provider not found: \(packageName)")
        }
        return try await requestInstall(provider, timeoutSeconds: timeoutSeconds)
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

    /// Restores provider-side trusted state without rotating the binding used
    /// to sign an already-created action proposal.
    public func restoreBinding(
        _ installed: NapaxiAgentAppPackage,
        timeoutSeconds: UInt64 = NapaxiAgentProviderAPI.defaultInstallTimeoutSeconds
    ) async throws -> NapaxiAgentAppPackage {
        guard let binding = installed.installBinding,
              !binding.hostInstanceId.isEmpty,
              !binding.hostSharedSecret.isEmpty else {
            throw NapaxiError.invalidState("Agent App has no restorable trusted binding")
        }
        guard binding.platform == "ios", !binding.installUrl.isEmpty else {
            throw NapaxiError.invalidState("Agent App is not installed with an iOS binding")
        }
        if !binding.hostBundleId.isEmpty, binding.hostBundleId != host.hostInfo.bundleId {
            throw NapaxiError.invalidState("Host identity changed; explicit reconnect is required")
        }
        let provider = NapaxiAgentProviderDescriptor(
            platform: "ios",
            label: installed.displayName,
            installUrl: binding.installUrl,
            actionUrl: binding.actionUrl,
            universalLinkDomain: binding.universalLinkDomain,
            iosBundleId: binding.iosBundleId,
            iosTeamId: binding.iosTeamId
        )
        var request = host.createInstallRequest()
        request.hostInstanceId = binding.hostInstanceId
        request.hostSharedSecret = binding.hostSharedSecret
        let response = try await host.requestInstall(
            provider: provider,
            request: request,
            timeoutSeconds: timeoutSeconds,
            openURL: openURL
        )
        let restored = try package(from: response)
        guard restored.providerId == installed.providerId,
              restored.agentId == installed.agentId else {
            throw NapaxiError.invalidState("Restored Agent App identity does not match installation")
        }
        return restored
    }

    /// Refreshes Core's manifest after a trusted in-place Provider update.
    public func refreshBinding(
        _ installed: NapaxiAgentAppPackage,
        timeoutSeconds: UInt64 = NapaxiAgentProviderAPI.defaultInstallTimeoutSeconds
    ) async throws -> NapaxiAgentAppPackage {
        let restored = try await restoreBinding(
            installed,
            timeoutSeconds: timeoutSeconds
        )
        return try registerPackage(restored.jsonString())
            .decodedObject(of: NapaxiAgentAppPackage.self)
    }

    /// Agent App runtime diagnostics are Android-only in this release.
    public func listAgentAppDiagnostics(
        _ installed: NapaxiAgentAppPackage
    ) -> AgentAppDiagnosticsSnapshot {
        _ = installed
        return .unsupported
    }

    /// Agent App detailed-log configuration is Android-only in this release.
    public func setDetailedDiagnostics(
        _ installed: NapaxiAgentAppPackage,
        enabled: Bool
    ) -> AgentAppDiagnosticsSnapshot {
        _ = installed
        _ = enabled
        return .unsupported
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
        try registerPackage(package(from: response).jsonString())
    }

    private func package(from response: NapaxiAgentProviderInstallResponse) throws -> NapaxiAgentAppPackage {
        let result = try NapaxiAgentInstallResult(jsonString: response.installResultJSON)
        guard var package = result.packageRaw else {
            throw NapaxiError.invalidState("Provider did not return an Agent package")
        }
        package["install_binding"] = .object(response.installBinding)
        return NapaxiAgentAppPackage(raw: package)
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
public typealias AgentProviderBindingRepair = @Sendable (NapaxiAgentAppActionRequest) async throws -> Bool

public final class NapaxiAgentProviderActionExecutor: NapaxiAgentAppActionExecutor, AgentAppActionExecutor, @unchecked Sendable {
    private let host: NapaxiAgentProviderHost
    private let openURL: NapaxiAgentProviderHost.URLOpener
    private let repairBinding: AgentProviderBindingRepair?

    public init(
        host: NapaxiAgentProviderHost,
        openURL: @escaping NapaxiAgentProviderHost.URLOpener = NapaxiAgentProviderAPI.defaultOpenURL
    ) {
        self.host = host
        self.openURL = openURL
        self.repairBinding = nil
    }

    public init(
        repairingBindingsFor host: NapaxiAgentProviderHost,
        repairBinding: @escaping AgentProviderBindingRepair,
        openURL: @escaping NapaxiAgentProviderHost.URLOpener = NapaxiAgentProviderAPI.defaultOpenURL
    ) {
        self.host = host
        self.openURL = openURL
        self.repairBinding = repairBinding
    }

    public func executeAgentAppAction(requestJSON: String) async -> String {
        await host.executeProviderAction(requestJSON: requestJSON, openURL: openURL)
    }

    public func execute(_ request: NapaxiAgentAppActionRequest) async throws -> NapaxiAgentAppActionResult {
        let requestJSON = try agentProviderRequestToJson(request)
        let resultJSON = await executeAgentAppAction(requestJSON: requestJSON)
        let first = try NapaxiRawJSON(jsonString: resultJSON).value.decodedObject(of: NapaxiAgentAppActionResult.self)
        guard first.isHostBindingMissing, let repairBinding else { return first }
        guard try await repairBinding(request) else { return first }
        let retriedJSON = await executeAgentAppAction(requestJSON: requestJSON)
        return try NapaxiRawJSON(jsonString: retriedJSON).value.decodedObject(of: NapaxiAgentAppActionResult.self)
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
