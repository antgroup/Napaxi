import Foundation

public struct NapaxiChannelProviderManifest: Equatable, Sendable {
    public var providerId: String
    public var channelName: String
    public var displayName: String
    public var description: String
    public var accountId: String
    public var surfaceKind: String
    public var endpointKinds: [String]
    public var modalities: [String]
    public var contentFormats: [String]
    public var transport: String
    public var authRequirements: [String]
    public var backgroundRequirements: [String]
    public var config: [String: NapaxiJSONValue]

    public init(
        providerId: String,
        channelName: String,
        displayName: String,
        description: String = "",
        accountId: String = "default",
        surfaceKind: String = NapaxiChannelSurfaceKind.custom,
        endpointKinds: [String] = [NapaxiChannelEndpointKind.direct],
        modalities: [String] = [NapaxiChannelModality.text],
        contentFormats: [String] = [NapaxiChannelContentFormat.plainText],
        transport: String = "host_adapter",
        authRequirements: [String] = [],
        backgroundRequirements: [String] = [],
        config: [String: NapaxiJSONValue] = [:]
    ) {
        self.providerId = providerId
        self.channelName = channelName
        self.displayName = displayName
        self.description = description
        self.accountId = accountId
        self.surfaceKind = surfaceKind
        self.endpointKinds = endpointKinds
        self.modalities = modalities
        self.contentFormats = contentFormats
        self.transport = transport
        self.authRequirements = authRequirements
        self.backgroundRequirements = backgroundRequirements
        self.config = config
    }

    public static func im(
        providerId: String,
        channelName: String,
        displayName: String,
        description: String = "",
        accountId: String = "default",
        endpointKinds: [String] = [NapaxiChannelEndpointKind.direct],
        modalities: [String] = [NapaxiChannelModality.text],
        contentFormats: [String] = [NapaxiChannelContentFormat.plainText],
        transport: String = "host_adapter",
        authRequirements: [String] = [],
        backgroundRequirements: [String] = [],
        config: [String: NapaxiJSONValue] = [:]
    ) -> Self {
        Self(
            providerId: providerId,
            channelName: channelName,
            displayName: displayName,
            description: description,
            accountId: accountId,
            surfaceKind: NapaxiChannelSurfaceKind.im,
            endpointKinds: endpointKinds,
            modalities: modalities,
            contentFormats: contentFormats,
            transport: transport,
            authRequirements: authRequirements,
            backgroundRequirements: backgroundRequirements,
            config: config
        )
    }

    public func toRegistration() -> NapaxiChannelRegistration {
        NapaxiChannelRegistration(
            name: channelName,
            type: channelName,
            accountId: accountId,
            surfaceKind: surfaceKind,
            endpointKind: endpointKinds.first,
            modalities: modalities,
            contentFormats: contentFormats,
            transport: transport,
            config: toJson()
        )
    }

    public func toJson() -> [String: NapaxiJSONValue] {
        var object: [String: NapaxiJSONValue] = [
            "provider_id": .string(providerId),
            "channel_name": .string(channelName),
            "display_name": .string(displayName),
            "account_id": .string(accountId),
            "surface_kind": .string(surfaceKind),
            "transport": .string(transport),
        ]
        if !description.isEmpty {
            object["description"] = .string(description)
        }
        if !endpointKinds.isEmpty {
            object["endpoint_kinds"] = .array(endpointKinds.map { .string($0) })
        }
        if !modalities.isEmpty {
            object["modalities"] = .array(modalities.map { .string($0) })
        }
        if !contentFormats.isEmpty {
            object["content_formats"] = .array(contentFormats.map { .string($0) })
        }
        if !authRequirements.isEmpty {
            object["auth_requirements"] = .array(authRequirements.map { .string($0) })
        }
        if !backgroundRequirements.isEmpty {
            object["background_requirements"] = .array(backgroundRequirements.map { .string($0) })
        }
        if !config.isEmpty {
            object["config"] = .object(config)
        }
        return object
    }
}

public struct NapaxiChannelOutboundDeliveryResult: Equatable, Sendable {
    public var delivered: Bool
    public var receipt: [String: NapaxiJSONValue]?
    public var error: String?

    public init(delivered: Bool, receipt: [String: NapaxiJSONValue]? = nil, error: String? = nil) {
        self.delivered = delivered
        self.receipt = receipt
        self.error = error
    }

    public static func delivered(receipt: [String: NapaxiJSONValue] = [:]) -> Self {
        Self(delivered: true, receipt: receipt)
    }

    public static func failed(_ error: String) -> Self {
        Self(delivered: false, error: error)
    }
}

public struct NapaxiChannelProviderPumpResult: Equatable, Sendable {
    public var channelName: String
    public var leased: Int
    public var delivered: Int
    public var failed: Int

    public var hadWork: Bool { leased > 0 }
}

public enum NapaxiChannelProviderEventType {
    public static let registered = "registered"
    public static let unregistered = "unregistered"
    public static let outboundDelivered = "outbound_delivered"
    public static let outboundFailed = "outbound_failed"
}

public struct NapaxiChannelProviderEvent: Equatable, Sendable {
    public var channelName: String
    public var providerId: String
    public var type: String
    public var outboundId: String?
    public var error: String?
}

public protocol NapaxiChannelProvider: Sendable {
    var manifest: NapaxiChannelProviderManifest { get }
    func start(context: NapaxiChannelProviderContext) async throws
    func stop() async
    func deliverOutbound(_ message: NapaxiChannelOutboundMessage) async -> NapaxiChannelOutboundDeliveryResult
}

public extension NapaxiChannelProvider {
    func start(context: NapaxiChannelProviderContext) async throws {}
    func stop() async {}
}

public final class NapaxiChannelProviderContext: @unchecked Sendable {
    private let queue: NapaxiChannelAPI
    public let manifest: NapaxiChannelProviderManifest

    init(queue: NapaxiChannelAPI, manifest: NapaxiChannelProviderManifest) {
        self.queue = queue
        self.manifest = manifest
    }

    public func submitInbound(_ message: NapaxiChannelInboundMessage) throws -> NapaxiChannelAcceptedReceipt {
        try queue.submitInbound(message)
    }

    public func submitTextInbound(
        peer: NapaxiChannelPeer,
        sender: NapaxiChannelActor,
        text: String,
        platformMessageId: String? = nil,
        threadId: String? = nil,
        raw: [String: NapaxiJSONValue]? = nil
    ) throws -> NapaxiChannelAcceptedReceipt {
        try submitInbound(
            NapaxiChannelInboundMessage(
                channelName: manifest.channelName,
                accountId: manifest.accountId,
                peer: peer,
                sender: sender,
                platformMessageId: platformMessageId,
                threadId: threadId,
                text: text,
                raw: raw
            )
        )
    }

    public func leaseOutbound(limit: Int = 20) throws -> [NapaxiChannelOutboundMessage] {
        try queue.leaseOutboundMessages(
            channelName: manifest.channelName,
            accountId: manifest.accountId,
            limit: limit
        )
    }

    public func ackOutbound(_ outboundId: String, receipt: [String: NapaxiJSONValue] = [:]) throws -> Bool {
        let receiptJSON = try NapaxiRawJSON(.object(receipt)).jsonString()
        return try queue.ackOutboundMessage(outboundId, receiptJSON: receiptJSON)
    }

    public func failOutbound(_ outboundId: String, error: String) throws -> Bool {
        try queue.failOutboundMessage(outboundId, error: error)
    }
}

public final class NapaxiChannelProviderHost: @unchecked Sendable {
    private let queue: NapaxiChannelAPI
    private var providers: [String: RegisteredProvider] = [:]
    public let events: AsyncStream<NapaxiChannelProviderEvent>
    private let eventContinuation: AsyncStream<NapaxiChannelProviderEvent>.Continuation

    public init(channels queue: NapaxiChannelAPI) {
        self.queue = queue
        var continuation: AsyncStream<NapaxiChannelProviderEvent>.Continuation!
        self.events = AsyncStream { continuation = $0 }
        self.eventContinuation = continuation
    }

    public func listProviderManifests() -> [NapaxiChannelProviderManifest] {
        providers.values.map { $0.provider.manifest }
    }

    public func hasProvider(channelName: String) -> Bool {
        providers[channelName] != nil
    }

    public func providerManifest(channelName: String) -> NapaxiChannelProviderManifest? {
        providers[channelName]?.provider.manifest
    }

    public func registerProvider(
        _ provider: any NapaxiChannelProvider,
        autoPump: Bool = false,
        pollInterval: TimeInterval = 2
    ) async throws {
        let manifest = provider.manifest
        guard !manifest.channelName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw NapaxiError.invalidState("channelName must not be blank")
        }
        guard providers[manifest.channelName] == nil else {
            throw NapaxiError.invalidState("channel provider already registered: \(manifest.channelName)")
        }
        guard try queue.register(manifest.toRegistration()) else {
            throw NapaxiError.invalidState("failed to register channel: \(manifest.channelName)")
        }
        let context = NapaxiChannelProviderContext(queue: queue, manifest: manifest)
        do {
            try await provider.start(context: context)
        } catch {
            _ = try? queue.unregisterChannel(manifest.channelName)
            throw error
        }
        let task = autoPump ? makeAutoPumpTask(channelName: manifest.channelName, pollInterval: pollInterval) : nil
        providers[manifest.channelName] = RegisteredProvider(provider: provider, context: context, task: task)
        emit(
            NapaxiChannelProviderEvent(
                channelName: manifest.channelName,
                providerId: manifest.providerId,
                type: NapaxiChannelProviderEventType.registered
            )
        )
    }

    public func pump(channelName: String, limit: Int = 20) async throws -> NapaxiChannelProviderPumpResult {
        guard let registered = providers[channelName] else {
            throw NapaxiError.invalidState("channel provider is not registered: \(channelName)")
        }
        let outbound = try registered.context.leaseOutbound(limit: limit)
        var delivered = 0
        var failed = 0
        for message in outbound {
            let result = await registered.provider.deliverOutbound(message)
            if result.delivered {
                _ = try registered.context.ackOutbound(message.id, receipt: result.receipt ?? [:])
                delivered += 1
                emit(
                    NapaxiChannelProviderEvent(
                        channelName: channelName,
                        providerId: registered.provider.manifest.providerId,
                        type: NapaxiChannelProviderEventType.outboundDelivered,
                        outboundId: message.id
                    )
                )
            } else {
                _ = try registered.context.failOutbound(message.id, error: result.error ?? "delivery_failed")
                failed += 1
                emit(
                    NapaxiChannelProviderEvent(
                        channelName: channelName,
                        providerId: registered.provider.manifest.providerId,
                        type: NapaxiChannelProviderEventType.outboundFailed,
                        outboundId: message.id,
                        error: result.error
                    )
                )
            }
        }
        return NapaxiChannelProviderPumpResult(
            channelName: channelName,
            leased: outbound.count,
            delivered: delivered,
            failed: failed
        )
    }

    public func unregisterProvider(channelName: String) async {
        guard let registered = providers.removeValue(forKey: channelName) else { return }
        registered.task?.cancel()
        await registered.provider.stop()
        _ = try? queue.unregisterChannel(channelName)
        emit(
            NapaxiChannelProviderEvent(
                channelName: channelName,
                providerId: registered.provider.manifest.providerId,
                type: NapaxiChannelProviderEventType.unregistered
            )
        )
    }

    public func dispose() {
        let registered = Array(providers.values)
        providers.removeAll()
        for item in registered {
            item.task?.cancel()
            Task { await item.provider.stop() }
        }
        eventContinuation.finish()
    }

    private func makeAutoPumpTask(channelName: String, pollInterval: TimeInterval) -> Task<Void, Never> {
        let interval = UInt64(max(pollInterval, 0.1) * 1_000_000_000)
        return Task { [weak self] in
            while !Task.isCancelled {
                _ = try? await self?.pump(channelName: channelName)
                try? await Task.sleep(nanoseconds: interval)
            }
        }
    }

    private func emit(_ event: NapaxiChannelProviderEvent) {
        eventContinuation.yield(event)
    }

    private struct RegisteredProvider: Sendable {
        var provider: any NapaxiChannelProvider
        var context: NapaxiChannelProviderContext
        var task: Task<Void, Never>?
    }
}
