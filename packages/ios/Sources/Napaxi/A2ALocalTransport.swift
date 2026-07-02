import Darwin
import Foundation
import Network

public final class NapaxiA2ALocalTransport: NSObject, NetServiceBrowserDelegate, NetServiceDelegate, @unchecked Sendable {
    public static let serviceType = "_napaxi-a2a._tcp."
    public static let serviceDomain = "local."
    public static let transport = "lan_tcp_jsonl"
    private static let preferredListenerPort: UInt16 = 54509
    private static let sendTimeoutMs = 3000

    private static let registryLock = NSLock()
    private static var registry: [Int64: NapaxiA2ALocalTransport] = [:]

    static func shared(for rawAPI: NapaxiRawAPI) -> NapaxiA2ALocalTransport {
        registryLock.lock()
        defer { registryLock.unlock() }
        if let existing = registry[rawAPI.handle] {
            return existing
        }
        let created = NapaxiA2ALocalTransport(rawAPI: rawAPI)
        registry[rawAPI.handle] = created
        return created
    }

    static func clearInstance(handle: Int64) {
        registryLock.lock()
        let existing = registry.removeValue(forKey: handle)
        registryLock.unlock()
        _ = existing?.stop()
    }

    private let rawAPI: NapaxiRawAPI
    private let queue = DispatchQueue(label: "com.napaxi.ios.a2a.local")
    private let stateLock = NSLock()
    private var listener: NWListener?
    private var service: NetService?
    private var browser: NetServiceBrowser?
    private var services: [String: NetService] = [:]
    private var discoveredPeers: [String: [String: NapaxiJSONValue]] = [:]
    private var servicePeerIds: [String: String] = [:]
    private var serviceGenerations: [String: Int64] = [:]
    private var events: [NapaxiA2ALocalTransportEvent] = []
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

    init(rawAPI: NapaxiRawAPI) {
        self.rawAPI = rawAPI
        super.init()
    }

    public func status() -> NapaxiA2ALocalTransportStatus {
        NapaxiA2ALocalTransportStatus(json: statusJSON())
    }

    public func checkPermission() -> Bool {
        localNetworkWarnings().isEmpty
    }

    public func requestPermission() async -> Bool {
        checkPermission()
    }

    public func start(
        peerId: String = "",
        agentId: String = "",
        displayName: String = "",
        publicKey: String = ""
    ) -> NapaxiA2ALocalTransportStatus {
        stateLock.lock()
        if running {
            let json = statusJSONLocked()
            stateLock.unlock()
            return NapaxiA2ALocalTransportStatus(json: json)
        }
        localPeerId = peerId.isEmpty ? stableLocalPeerId() : peerId
        localAgentId = agentId
        localDisplayName = displayName.isEmpty ? "Napaxi" : displayName
        localPublicKey = publicKey
        stateLock.unlock()

        do {
            let listener = try makeListener()
            listener.newConnectionHandler = { [weak self] connection in
                self?.accept(connection)
            }
            listener.stateUpdateHandler = { [weak self, weak listener] state in
                guard let self else { return }
                switch state {
                case .ready:
                    self.stateLock.lock()
                    if let port = listener?.port?.rawValue {
                        self.localPort = port
                    }
                    self.running = true
                    self.stateLock.unlock()
                    self.publishService()
                    self.emit("a2aLocalTransportStarted", payload: self.statusJSON())
                case .failed(let error):
                    self.setLastError("listener_failed:\(error)")
                    self.emit("a2aLocalTransportError", payload: [
                        "code": .string("listener_failed"),
                        "error": .string("\(error)"),
                    ])
                    _ = self.stop()
                case .cancelled:
                    self.stateLock.lock()
                    self.running = false
                    self.stateLock.unlock()
                    self.emit("a2aLocalTransportStopped", payload: self.statusJSON())
                default:
                    break
                }
            }
            stateLock.lock()
            self.listener = listener
            stateLock.unlock()
            listener.start(queue: queue)
        } catch {
            setLastError("ios_network_listener_unavailable:\(error)")
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

    public func stop() -> NapaxiA2ALocalTransportStatus {
        stateLock.lock()
        running = false
        let browser = self.browser
        self.browser = nil
        services.removeAll()
        discoveredPeers.removeAll()
        servicePeerIds.removeAll()
        serviceGenerations.removeAll()
        let service = self.service
        self.service = nil
        let listener = self.listener
        self.listener = nil
        localPort = 0
        registeredName = ""
        stateLock.unlock()
        browser?.stop()
        service?.stop()
        listener?.cancel()
        emit("a2aLocalTransportStopped", payload: statusJSON())
        return status()
    }

    public func discover(timeoutMs: Int = 5000) -> [NapaxiA2ALocalPeerAdvertisement] {
        let timeout = max(500, min(timeoutMs, 30000))
        let browser = NetServiceBrowser()
        browser.delegate = self
        stateLock.lock()
        self.browser?.stop()
        discoveryGeneration += 1
        let generation = discoveryGeneration
        services.removeAll()
        discoveredPeers.removeAll()
        servicePeerIds.removeAll()
        serviceGenerations.removeAll()
        self.browser = browser
        stateLock.unlock()
        browser.searchForServices(ofType: Self.serviceType, inDomain: Self.serviceDomain)
        emit("a2aLocalDiscoveryStarted", payload: [
            "serviceType": .string(Self.serviceType),
            "generation": .number(Double(generation)),
        ])
        queue.asyncAfter(deadline: .now() + .milliseconds(timeout)) { [weak self] in
            guard let self else { return }
            self.stateLock.lock()
            guard self.discoveryGeneration == generation else {
                self.stateLock.unlock()
                return
            }
            self.browser?.stop()
            self.browser = nil
            self.stateLock.unlock()
            self.emit("a2aLocalDiscoveryStopped", payload: [
                "serviceType": .string(Self.serviceType),
                "generation": .number(Double(generation)),
            ])
        }
        return discoveredPeerModels()
    }

    public func send(_ message: NapaxiA2APeerMessage, endpoint: String) -> Bool {
        guard !endpoint.isEmpty, let target = parseEndpoint(endpoint) else {
            setLastError("unsupported endpoint: \(endpoint)")
            return false
        }
        guard let port = NWEndpoint.Port(rawValue: target.port),
              let messageJSON = try? message.jsonString() else {
            setLastError("invalid peer message or endpoint")
            return false
        }

        let connection = NWConnection(host: NWEndpoint.Host(target.host), port: port, using: .tcp)
        let semaphore = DispatchSemaphore(value: 0)
        var sent = false
        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                connection.send(content: Data((messageJSON + "\n").utf8), completion: .contentProcessed { error in
                    if let error {
                        self?.setLastError("send_failed:\(error)")
                        self?.emit("a2aLocalSendFailed", payload: [
                            "endpoint": .string(endpoint),
                            "error": .string("send_failed:\(error)"),
                        ])
                    } else {
                        self?.incrementSentCount()
                        self?.emit("a2aLocalMessageSent", payload: ["endpoint": .string(endpoint)])
                        sent = true
                    }
                    connection.cancel()
                    semaphore.signal()
                })
            case .failed(let error):
                self?.setLastError("send_failed:\(error)")
                self?.emit("a2aLocalSendFailed", payload: [
                    "endpoint": .string(endpoint),
                    "error": .string("send_failed:\(error)"),
                ])
                connection.cancel()
                semaphore.signal()
            default:
                break
            }
        }
        connection.start(queue: queue)
        if semaphore.wait(timeout: .now() + .milliseconds(Self.sendTimeoutMs)) == .timedOut {
            setLastError("send_timeout")
            emit("a2aLocalSendFailed", payload: [
                "endpoint": .string(endpoint),
                "error": .string("send_timeout"),
            ])
            connection.cancel()
        }
        return sent
    }

    public func localTransportEvents() -> [NapaxiA2ALocalTransportEvent] {
        stateLock.lock()
        defer { stateLock.unlock() }
        return events
    }

    public func clearLocalTransportEvents() {
        stateLock.lock()
        events.removeAll()
        stateLock.unlock()
    }

    public func netServiceBrowser(_ browser: NetServiceBrowser, didFind service: NetService, moreComing: Bool) {
        service.delegate = self
        stateLock.lock()
        services[service.name] = service
        serviceGenerations[service.name] = discoveryGeneration
        stateLock.unlock()
        service.resolve(withTimeout: 5)
    }

    public func netServiceBrowser(_ browser: NetServiceBrowser, didRemove service: NetService, moreComing: Bool) {
        stateLock.lock()
        services.removeValue(forKey: service.name)
        serviceGenerations.removeValue(forKey: service.name)
        if let peerId = servicePeerIds.removeValue(forKey: service.name) {
            discoveredPeers.removeValue(forKey: peerId)
        }
        let generation = discoveryGeneration
        stateLock.unlock()
        emit("a2aLocalPeerLost", payload: [
            "serviceName": .string(service.name),
            "generation": .number(Double(generation)),
        ])
    }

    public func netServiceDidResolveAddress(_ sender: NetService) {
        stateLock.lock()
        let generation = serviceGenerations[sender.name] ?? discoveryGeneration
        let currentGeneration = discoveryGeneration
        stateLock.unlock()
        guard generation == currentGeneration else { return }
        guard var peer = peer(from: sender),
              let peerId = peer["peerId"]?.stringValue,
              !peerId.isEmpty else {
            return
        }
        stateLock.lock()
        let local = localPeerId
        if peerId != local {
            peer["generation"] = .number(Double(generation))
            peer["serviceName"] = .string(sender.name)
            servicePeerIds[sender.name] = peerId
            discoveredPeers[peerId] = peer
        }
        stateLock.unlock()
        if peerId != local {
            emit("a2aLocalPeerFound", payload: peer, peer: peer)
        }
    }

    public func netService(_ sender: NetService, didNotResolve errorDict: [String: NSNumber]) {
        setLastError("resolve_failed:\(errorDict)")
        emit("a2aLocalDiscoveryError", payload: [
            "code": .string("resolve_failed"),
            "serviceName": .string(sender.name),
            "generation": .number(Double(serviceGenerations[sender.name] ?? discoveryGeneration)),
            "error": .string("\(errorDict)"),
        ])
    }

    private func publishService() {
        stateLock.lock()
        let port = localPort
        let name = safeServiceName(localDisplayName, localPeerId)
        let peerId = localPeerId
        let agentId = localAgentId
        let displayName = localDisplayName
        let publicKey = localPublicKey
        stateLock.unlock()
        guard port > 0 else { return }
        let service = NetService(domain: Self.serviceDomain, type: Self.serviceType, name: name, port: Int32(port))
        service.delegate = self
        service.setTXTRecord(NetService.data(fromTXTRecord: [
            "peerId": Data(peerId.utf8),
            "agentId": Data(agentId.utf8),
            "displayName": Data(displayName.utf8),
            "publicKey": Data(publicKey.utf8),
            "transport": Data(Self.transport.utf8),
        ]))
        stateLock.lock()
        self.service = service
        registeredName = service.name
        stateLock.unlock()
        service.publish()
    }

    private func accept(_ connection: NWConnection) {
        connection.start(queue: queue)
        receive(connection, buffer: Data())
    }

    private func receive(_ connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 4096) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            if let error {
                self.setLastError("receive_failed:\(error)")
                self.emit("a2aLocalTransportError", payload: [
                    "code": .string("receive_failed"),
                    "error": .string("\(error)"),
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
                        self.handleInboundMessage(message, remoteAddress: self.remoteAddress(connection))
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

    private func handleInboundMessage(_ messageJSON: String, remoteAddress: String) {
        incrementReceivedCount()
        var payload: [String: NapaxiJSONValue] = [
            "messageJson": .string(messageJSON),
            "source": .string(Self.transport),
            "remoteAddress": .string(remoteAddress),
        ]
        var messageObject: [String: NapaxiJSONValue]?
        if let decoded = try? decodeJsonObject(messageJSON) {
            messageObject = decoded
            payload["message"] = .object(decoded)
            let message = NapaxiA2APeerMessage(json: decoded)
            do {
                let record = try NapaxiA2AAPI(rawAPI: rawAPI).recordPeerMessage(message, source: Self.transport)
                payload["deliveryStatus"] = .string(record.status)
                if let taskId = record.taskId {
                    payload["taskId"] = .string(taskId)
                }
            } catch {
                payload["recordError"] = .string("\(error)")
                setLastError("record_failed:\(error)")
            }
        } else {
            payload["recordError"] = .string("invalid_message_json")
            setLastError("invalid_message_json")
        }
        emit("a2aLocalPeerMessage", payload: payload, message: messageObject)
    }

    private func discoveredPeerModels() -> [NapaxiA2ALocalPeerAdvertisement] {
        stateLock.lock()
        let peers = Array(discoveredPeers.values)
        stateLock.unlock()
        return peers.map(NapaxiA2ALocalPeerAdvertisement.init(json:))
    }

    private func statusJSON() -> [String: NapaxiJSONValue] {
        stateLock.lock()
        defer { stateLock.unlock() }
        return statusJSONLocked()
    }

    private func statusJSONLocked() -> [String: NapaxiJSONValue] {
        let warnings = localNetworkWarnings()
        return [
            "supported": .bool(true),
            "running": .bool(running),
            "transport": .string(Self.transport),
            "serviceType": .string(Self.serviceType),
            "peerId": .string(localPeerId),
            "agentId": .string(localAgentId),
            "displayName": .string(localDisplayName),
            "endpoint": .string(localEndpointLocked()),
            "listenerPort": .number(Double(localPort)),
            "registeredName": .string(registeredName),
            "discoveredPeerCount": .number(Double(discoveredPeers.count)),
            "activeDiscoveryCount": .number(browser == nil ? 0 : 1),
            "discoveryGeneration": .number(Double(discoveryGeneration)),
            "sentMessageCount": .number(Double(sentMessageCount)),
            "receivedMessageCount": .number(Double(receivedMessageCount)),
            "multicastLockHeld": .bool(false),
            "permissionWarnings": .array(warnings.map { .string($0) }),
            "lastError": .string(lastError),
            "reason": .string(warnings.joined(separator: ",")),
        ]
    }

    private func localEndpointLocked() -> String {
        guard running, localPort > 0, let host = reachableLocalHostLocked() else { return "" }
        return "tcp://\(formatEndpointHost(host)):\(localPort)/a2a"
    }

    private func emit(
        _ action: String,
        payload: [String: NapaxiJSONValue],
        peer: [String: NapaxiJSONValue]? = nil,
        message: [String: NapaxiJSONValue]? = nil
    ) {
        var event: [String: NapaxiJSONValue] = [
            "action": .string(action),
            "payload": .object(payload),
        ]
        if let peer {
            event["peer"] = .object(peer)
        }
        if let message {
            event["message"] = .object(message)
            if let messageString = try? message.jsonString() {
                event["messageJson"] = .string(messageString)
            }
        } else if let messageJson = payload["messageJson"]?.stringValue {
            event["messageJson"] = .string(messageJson)
        }
        stateLock.lock()
        events.append(NapaxiA2ALocalTransportEvent(fromEvent: event))
        if events.count > 200 {
            events.removeFirst(events.count - 200)
        }
        stateLock.unlock()
    }

    private func peer(from service: NetService) -> [String: NapaxiJSONValue]? {
        let txt = service.txtRecordData().map(NetService.dictionary(fromTXTRecord:)) ?? [:]
        let peerId = txtString(txt, "peerId")
        let host = service.hostName ?? ""
        let port = service.port
        guard !peerId.isEmpty, port > 0 else { return nil }
        return [
            "peerId": .string(peerId),
            "agentId": .string(txtString(txt, "agentId")),
            "displayName": .string(txtString(txt, "displayName").isEmpty ? service.name : txtString(txt, "displayName")),
            "publicKey": .string(txtString(txt, "publicKey")),
            "transport": .string(Self.transport),
            "endpoint": .string("tcp://\(formatEndpointHost(host)):\(port)/a2a"),
            "host": .string(host),
            "port": .number(Double(port)),
            "serviceName": .string(service.name),
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

    private func reachableLocalHostLocked() -> String? {
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
        return String("\(String(base))-\(peerId.suffix(8))".prefix(40))
    }

    private func setLastError(_ value: String) {
        stateLock.lock()
        lastError = value
        stateLock.unlock()
    }

    private func incrementSentCount() {
        stateLock.lock()
        sentMessageCount += 1
        stateLock.unlock()
    }

    private func incrementReceivedCount() {
        stateLock.lock()
        receivedMessageCount += 1
        stateLock.unlock()
    }
}
