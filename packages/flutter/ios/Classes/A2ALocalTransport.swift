import Flutter
import Darwin
import Foundation
import Network

final class A2ALocalTransport: NSObject, NetServiceBrowserDelegate, NetServiceDelegate {
    private static let serviceType = "_napaxi-a2a._tcp."
    private static let serviceDomain = "local."
    private static let transport = "lan_tcp_jsonl"
    private static let preferredListenerPort: UInt16 = 54509
    private static let sendTimeoutMs = 3000

    private let queue = DispatchQueue(label: "com.napaxi.flutter.a2a.local")
    private let eventSinkProvider: () -> FlutterEventSink?
    private var listener: NWListener?
    private var service: NetService?
    private var browser: NetServiceBrowser?
    private var services: [String: NetService] = [:]
    private var discoveredPeers: [String: [String: Any]] = [:]
    private var servicePeerIds: [String: String] = [:]
    private var serviceGenerations: [String: Int64] = [:]
    private var pendingEvents: [[String: Any]] = []
    private let pendingEventsLock = NSLock()
    private var localPeerId = ""
    private var localAgentId = ""
    private var localDisplayName = ""
    private var localPublicKey = ""
    private var localPort: UInt16 = 0
    private var registeredName = ""
    private var sentMessageCount = 0
    private var receivedMessageCount = 0
    private var lastError = ""
    private var running = false
    private var discoveryGeneration: Int64 = 0

    init(eventSinkProvider: @escaping () -> FlutterEventSink?) {
        self.eventSinkProvider = eventSinkProvider
        super.init()
    }

    func status() -> [String: Any] {
        let warnings = localNetworkWarnings()
        return [
            "supported": true,
            "running": running,
            "transport": Self.transport,
            "serviceType": Self.serviceType,
            "peerId": localPeerId,
            "agentId": localAgentId,
            "displayName": localDisplayName,
            "endpoint": localEndpoint(),
            "listenerPort": Int(localPort),
            "registeredName": registeredName,
            "discoveredPeerCount": discoveredPeers.count,
            "activeDiscoveryCount": browser == nil ? 0 : 1,
            "discoveryGeneration": discoveryGeneration,
            "sentMessageCount": sentMessageCount,
            "receivedMessageCount": receivedMessageCount,
            "multicastLockHeld": false,
            "permissionWarnings": warnings,
            "lastError": lastError,
            "reason": warnings.joined(separator: ","),
        ]
    }

    func start(args: [String: Any]?) -> [String: Any] {
        if running { return status() }
        localPeerId = stringArg(args, "peerId")
        if localPeerId.isEmpty { localPeerId = stableLocalPeerId() }
        localAgentId = stringArg(args, "agentId")
        localDisplayName = stringArg(args, "displayName")
        if localDisplayName.isEmpty { localDisplayName = "Napaxi" }
        localPublicKey = stringArg(args, "publicKey")

        do {
            let listener = try makeListener()
            listener.newConnectionHandler = { [weak self] connection in
                self?.accept(connection)
            }
            listener.stateUpdateHandler = { [weak self] state in
                guard let self else { return }
                switch state {
                case .ready:
                    if let port = listener.port?.rawValue {
                        self.localPort = port
                    }
                    self.running = true
                    self.publishService()
                    self.emit("a2aLocalTransportStarted", self.status())
                case .failed(let error):
                    self.lastError = "listener_failed:\(error)"
                    self.emit("a2aLocalTransportError", [
                        "code": "listener_failed",
                        "error": "\(error)",
                    ])
                    _ = self.stop()
                case .cancelled:
                    self.running = false
                    self.emit("a2aLocalTransportStopped", self.status())
                default:
                    break
                }
            }
            self.listener = listener
            listener.start(queue: queue)
        } catch {
            return unsupported("ios_network_listener_unavailable:\(error)")
        }
        return status()
    }

    private func makeListener() throws -> NWListener {
        if let preferredPort = NWEndpoint.Port(rawValue: Self.preferredListenerPort),
           let listener = try? NWListener(using: .tcp, on: preferredPort) {
            return listener
        }
        return try NWListener(using: .tcp)
    }

    func stop() -> [String: Any] {
        running = false
        browser?.stop()
        browser = nil
        services.removeAll()
        discoveredPeers.removeAll()
        servicePeerIds.removeAll()
        serviceGenerations.removeAll()
        service?.stop()
        service = nil
        listener?.cancel()
        listener = nil
        localPort = 0
        registeredName = ""
        emit("a2aLocalTransportStopped", status())
        return status()
    }

    func discover(args: [String: Any]?) -> [String: Any] {
        let timeoutMs = max(500, min(intArg(args, "timeoutMs", defaultValue: 5000), 30000))
        browser?.stop()
        discoveryGeneration += 1
        let generation = discoveryGeneration
        services.removeAll()
        discoveredPeers.removeAll()
        servicePeerIds.removeAll()
        serviceGenerations.removeAll()
        let browser = NetServiceBrowser()
        browser.delegate = self
        self.browser = browser
        browser.searchForServices(ofType: Self.serviceType, inDomain: Self.serviceDomain)
        emit("a2aLocalDiscoveryStarted", [
            "serviceType": Self.serviceType,
            "generation": generation,
        ])
        queue.asyncAfter(deadline: .now() + .milliseconds(timeoutMs)) { [weak self] in
            guard let self else { return }
            guard self.discoveryGeneration == generation else { return }
            self.browser?.stop()
            self.browser = nil
            self.emit("a2aLocalDiscoveryStopped", [
                "serviceType": Self.serviceType,
                "generation": generation,
            ])
        }
        return [
            "started": true,
            "timeoutMs": timeoutMs,
            "serviceType": Self.serviceType,
            "generation": generation,
            "peers": Array(discoveredPeers.values),
        ]
    }

    func send(args: [String: Any]?) -> [String: Any] {
        let endpoint = stringArg(args, "endpoint")
        let messageJson = stringArg(args, "messageJson")
        guard !endpoint.isEmpty, !messageJson.isEmpty else {
            return ["sent": false, "error": "endpoint and messageJson are required"]
        }
        guard let target = parseEndpoint(endpoint) else {
            return ["sent": false, "error": "unsupported endpoint: \(endpoint)"]
        }
        let connection = NWConnection(host: NWEndpoint.Host(target.host), port: NWEndpoint.Port(rawValue: target.port)!, using: .tcp)
        let semaphore = DispatchSemaphore(value: 0)
        var sendResult: [String: Any] = [
            "sent": false,
            "endpoint": endpoint,
            "error": "send_timeout",
        ]
        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                let data = Data((messageJson + "\n").utf8)
                connection.send(content: data, completion: .contentProcessed { error in
                    if let error {
                        let message = "send_failed:\(error)"
                        self?.lastError = message
                        self?.emit("a2aLocalSendFailed", [
                            "endpoint": endpoint,
                            "error": message,
                        ])
                        sendResult = ["sent": false, "endpoint": endpoint, "error": message]
                    } else {
                        self?.sentMessageCount += 1
                        self?.emit("a2aLocalMessageSent", ["endpoint": endpoint])
                        sendResult = ["sent": true, "endpoint": endpoint]
                    }
                    connection.cancel()
                    semaphore.signal()
                })
            case .failed(let error):
                let message = "send_failed:\(error)"
                self?.lastError = message
                self?.emit("a2aLocalSendFailed", [
                    "endpoint": endpoint,
                    "error": message,
                ])
                sendResult = ["sent": false, "endpoint": endpoint, "error": message]
                connection.cancel()
                semaphore.signal()
            default:
                break
            }
        }
        connection.start(queue: queue)
        if semaphore.wait(timeout: .now() + .milliseconds(Self.sendTimeoutMs)) == .timedOut {
            lastError = "send_timeout"
            emit("a2aLocalSendFailed", ["endpoint": endpoint, "error": lastError])
            connection.cancel()
        }
        return sendResult
    }

    func drainEvents() -> [[String: Any]] {
        pendingEventsLock.lock()
        defer { pendingEventsLock.unlock() }
        let drained = pendingEvents
        pendingEvents.removeAll()
        return drained
    }

    func hasRequiredLocalNetworkDeclarations() -> Bool {
        localNetworkWarnings().isEmpty
    }

    func netServiceBrowser(_ browser: NetServiceBrowser, didFind service: NetService, moreComing: Bool) {
        service.delegate = self
        services[service.name] = service
        serviceGenerations[service.name] = discoveryGeneration
        service.resolve(withTimeout: 5)
    }

    func netServiceBrowser(_ browser: NetServiceBrowser, didRemove service: NetService, moreComing: Bool) {
        services.removeValue(forKey: service.name)
        serviceGenerations.removeValue(forKey: service.name)
        if let peerId = servicePeerIds.removeValue(forKey: service.name) {
            discoveredPeers.removeValue(forKey: peerId)
        }
        emit("a2aLocalPeerLost", [
            "serviceName": service.name,
            "generation": discoveryGeneration,
        ])
    }

    func netServiceDidResolveAddress(_ sender: NetService) {
        let generation = serviceGenerations[sender.name] ?? discoveryGeneration
        guard generation == discoveryGeneration else { return }
        guard var peer = peer(from: sender) else { return }
        guard let peerId = peer["peerId"] as? String, !peerId.isEmpty, peerId != localPeerId else { return }
        peer["generation"] = generation
        peer["serviceName"] = sender.name
        servicePeerIds[sender.name] = peerId
        discoveredPeers[peerId] = peer
        emit("a2aLocalPeerFound", peer)
    }

    func netService(_ sender: NetService, didNotResolve errorDict: [String: NSNumber]) {
        lastError = "resolve_failed:\(errorDict)"
        emit("a2aLocalDiscoveryError", [
            "code": "resolve_failed",
            "serviceName": sender.name,
            "generation": serviceGenerations[sender.name] ?? discoveryGeneration,
            "error": "\(errorDict)",
        ])
    }

    private func publishService() {
        guard localPort > 0 else { return }
        let service = NetService(
            domain: Self.serviceDomain,
            type: Self.serviceType,
            name: safeServiceName(localDisplayName, localPeerId),
            port: Int32(localPort)
        )
        service.delegate = self
        service.setTXTRecord(NetService.data(fromTXTRecord: [
            "peerId": Data(localPeerId.utf8),
            "agentId": Data(localAgentId.utf8),
            "displayName": Data(localDisplayName.utf8),
            "publicKey": Data(localPublicKey.utf8),
            "transport": Data(Self.transport.utf8),
        ]))
        self.service = service
        service.publish()
        registeredName = service.name
    }

    private func accept(_ connection: NWConnection) {
        connection.start(queue: queue)
        receive(connection, buffer: Data())
    }

    private func receive(_ connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 4096) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            if let error {
                self.lastError = "receive_failed:\(error)"
                self.emit("a2aLocalTransportError", [
                    "code": "receive_failed",
                    "error": "\(error)",
                ])
                connection.cancel()
                return
            }
            var nextBuffer = buffer
            if let data {
                nextBuffer.append(data)
                while let newline = nextBuffer.firstIndex(of: 0x0A) {
                    let line = nextBuffer[..<newline]
                    nextBuffer.removeSubrange(...newline)
                    if let message = String(data: Data(line), encoding: .utf8),
                       !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        self.receivedMessageCount += 1
                        self.emit("a2aLocalPeerMessage", [
                            "messageJson": message,
                            "source": Self.transport,
                            "remoteAddress": self.remoteAddress(connection),
                        ])
                    }
                }
            }
            if isComplete {
                connection.cancel()
            } else {
                self.receive(connection, buffer: nextBuffer)
            }
        }
    }

    private func peer(from service: NetService) -> [String: Any]? {
        let txt = service.txtRecordData().map(NetService.dictionary(fromTXTRecord:)) ?? [:]
        let peerId = txtString(txt, "peerId")
        let host = service.hostName ?? ""
        let port = service.port
        guard !peerId.isEmpty, port > 0 else { return nil }
        return [
            "peerId": peerId,
            "agentId": txtString(txt, "agentId"),
            "displayName": txtString(txt, "displayName").isEmpty ? service.name : txtString(txt, "displayName"),
            "publicKey": txtString(txt, "publicKey"),
            "transport": Self.transport,
            "endpoint": "tcp://\(formatEndpointHost(host)):\(port)/a2a",
            "host": host,
            "port": port,
        ]
    }

    private func localEndpoint() -> String {
        guard running, localPort > 0, let host = reachableLocalHost() else { return "" }
        return "tcp://\(formatEndpointHost(host)):\(localPort)/a2a"
    }

    private func emit(_ action: String, _ payload: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: payload),
              let payloadString = String(data: data, encoding: .utf8) else {
            return
        }
        let event: [String: Any] = [
            "action": action,
            "payload": payloadString,
        ]
        pendingEventsLock.lock()
        pendingEvents.append(event)
        if pendingEvents.count > 200 {
            pendingEvents.removeFirst(pendingEvents.count - 200)
        }
        pendingEventsLock.unlock()
        DispatchQueue.main.async { [eventSinkProvider] in
            eventSinkProvider()?(event)
        }
    }

    private func unsupported(_ reason: String) -> [String: Any] {
        [
            "supported": false,
            "running": false,
            "transport": Self.transport,
            "serviceType": Self.serviceType,
            "listenerPort": 0,
            "registeredName": "",
            "discoveredPeerCount": 0,
            "activeDiscoveryCount": 0,
            "sentMessageCount": sentMessageCount,
            "receivedMessageCount": receivedMessageCount,
            "multicastLockHeld": false,
            "permissionWarnings": [],
            "lastError": reason,
            "reason": reason,
        ]
    }

    private func parseEndpoint(_ endpoint: String) -> (host: String, port: UInt16)? {
        let clean = endpoint
            .replacingOccurrences(of: "tcp://", with: "")
            .replacingOccurrences(of: "jsonl://", with: "")
            .replacingOccurrences(of: "/a2a", with: "")
        if clean.hasPrefix("["),
           let hostEnd = clean.firstIndex(of: "]") {
            let afterHost = clean.index(after: hostEnd)
            guard afterHost < clean.endIndex, clean[afterHost] == ":" else { return nil }
            let portStart = clean.index(after: afterHost)
            guard portStart < clean.endIndex,
                  let port = UInt16(clean[portStart...]) else { return nil }
            return (String(clean[clean.index(after: clean.startIndex)..<hostEnd]), port)
        }
        guard let separator = clean.lastIndex(of: ":"),
              separator > clean.startIndex,
              separator < clean.index(before: clean.endIndex),
              let port = UInt16(clean[clean.index(after: separator)...]) else {
            return nil
        }
        return (String(clean[..<separator]), port)
    }

    private func formatEndpointHost(_ host: String) -> String {
        host.contains(":") && !host.hasPrefix("[") ? "[\(host)]" : host
    }

    private func reachableLocalHost() -> String? {
        var interfaces: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&interfaces) == 0, let first = interfaces else {
            return nil
        }
        defer { freeifaddrs(interfaces) }

        var fallback: String?
        var pointer: UnsafeMutablePointer<ifaddrs>? = first
        while let current = pointer {
            defer { pointer = current.pointee.ifa_next }
            let interface = current.pointee
            guard let address = interface.ifa_addr,
                  address.pointee.sa_family == UInt8(AF_INET) else {
                continue
            }
            let flags = Int32(interface.ifa_flags)
            guard flags & IFF_UP != 0, flags & IFF_LOOPBACK == 0 else {
                continue
            }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            let result = getnameinfo(
                address,
                socklen_t(address.pointee.sa_len),
                &host,
                socklen_t(host.count),
                nil,
                0,
                NI_NUMERICHOST
            )
            guard result == 0 else { continue }
            let value = String(cString: host)
            guard !value.isEmpty, value != "0.0.0.0" else { continue }
            let name = String(cString: interface.ifa_name)
            if name == "en0" {
                return value
            }
            if fallback == nil {
                fallback = value
            }
        }
        return fallback
    }

    private func remoteAddress(_ connection: NWConnection) -> String {
        switch connection.endpoint {
        case .hostPort(let host, let port):
            return "\(host):\(port)"
        default:
            return ""
        }
    }

    private func txtString(_ txt: [String: Data], _ key: String) -> String {
        guard let data = txt[key] else { return "" }
        return String(data: data, encoding: .utf8) ?? ""
    }

    private func stableLocalPeerId() -> String {
        let defaults = UserDefaults.standard
        if let existing = defaults.string(forKey: "napaxi_a2a_local.peer_id"), !existing.isEmpty {
            return existing
        }
        let created = "ios-\(UUID().uuidString)"
        defaults.set(created, forKey: "napaxi_a2a_local.peer_id")
        return created
    }

    private func localNetworkWarnings() -> [String] {
        var warnings: [String] = []
        let usage = Bundle.main.object(forInfoDictionaryKey: "NSLocalNetworkUsageDescription") as? String
        if usage?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false {
            warnings.append("ios_local_network_usage_description_missing")
        }
        let services = Bundle.main.object(forInfoDictionaryKey: "NSBonjourServices") as? [String] ?? []
        let normalized = Set(services.map { service in
            service.hasSuffix(".") ? service : "\(service)."
        })
        if !normalized.contains(Self.serviceType) {
            warnings.append("ios_bonjour_service_missing")
        }
        return warnings
    }

    private func safeServiceName(_ displayName: String, _ peerId: String) -> String {
        let base = (displayName.isEmpty ? "Napaxi" : displayName)
            .map { char -> Character in
                char.isLetter || char.isNumber || char == "-" || char == "_" ? char : "-"
            }
        let safe = String(base)
        return String("\(safe)-\(peerId.suffix(8))".prefix(40))
    }

    private func stringArg(_ args: [String: Any]?, _ key: String) -> String {
        args?[key] as? String ?? ""
    }

    private func intArg(_ args: [String: Any]?, _ key: String, defaultValue: Int) -> Int {
        if let value = args?[key] as? Int { return value }
        if let value = args?[key] as? NSNumber { return value.intValue }
        if let value = args?[key] as? String, let parsed = Int(value) { return parsed }
        return defaultValue
    }
}
