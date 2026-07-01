import Foundation

final class NapaxiSessionRunBroadcaster: @unchecked Sendable {
    private let lock = NSLock()
    private var continuations: [UUID: AsyncStream<NapaxiSessionRunInfo>.Continuation] = [:]

    func stream() -> AsyncStream<NapaxiSessionRunInfo> {
        AsyncStream { continuation in
            let id = UUID()
            lock.lock()
            continuations[id] = continuation
            lock.unlock()
            continuation.onTermination = { [weak self] _ in
                self?.lock.lock()
                self?.continuations.removeValue(forKey: id)
                self?.lock.unlock()
            }
        }
    }

    func emit(_ value: NapaxiSessionRunInfo) {
        lock.lock()
        let sinks = Array(continuations.values)
        lock.unlock()
        for sink in sinks {
            sink.yield(value)
        }
    }

    func finish() {
        lock.lock()
        let sinks = Array(continuations.values)
        continuations.removeAll()
        lock.unlock()
        for sink in sinks {
            sink.finish()
        }
    }
}

final class NapaxiSessionRunTracker: @unchecked Sendable {
    private let lock = NSLock()
    private var active: [String: NapaxiSessionRunInfo] = [:]
    private var locallyCancelled: [String: Date] = [:]
    private let broadcaster = NapaxiSessionRunBroadcaster()

    var updates: AsyncStream<NapaxiSessionRunInfo> {
        broadcaster.stream()
    }

    var activeRuns: [NapaxiSessionRunInfo] {
        lock.lock()
        defer { lock.unlock() }
        return Array(active.values)
    }

    func activeRun(agentId: String, key: NapaxiSessionKey) -> NapaxiSessionRunInfo? {
        lock.lock()
        defer { lock.unlock() }
        return active[id(agentId: agentId, key: key)]
    }

    func hasActiveRun(agentId: String, key: NapaxiSessionKey) -> Bool {
        activeRun(agentId: agentId, key: key) != nil
    }

    func start(agentId: String, key: NapaxiSessionKey, now: Date = Date()) throws -> NapaxiSessionRunInfo {
        let run = NapaxiSessionRunInfo(
            key: key,
            agentId: agentId,
            status: .running,
            activity: "Starting",
            startedAt: now,
            updatedAt: now
        )
        lock.lock()
        if active[run.id] != nil {
            lock.unlock()
            throw NapaxiError.invalidState("Session is already running: \(key.threadId)")
        }
        locallyCancelled.removeValue(forKey: run.id)
        active[run.id] = run
        lock.unlock()
        broadcaster.emit(run)
        return run
    }

    func apply(event: NapaxiChatEvent, to run: NapaxiSessionRunInfo) -> NapaxiSessionRunInfo {
        guard !run.isTerminal else { return run }
        if isLocallyCancelled(run) {
            return cancelled(run)
        }
        let next: NapaxiSessionRunInfo
        switch event.type {
        case "tool_call":
            next = update(run, status: .running, activity: "Running: \(event.string("name") ?? "")", clearHumanRequest: true, clearError: true)
        case "tool_call_delta":
            let name = event.string("name")?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            next = update(run, status: .running, activity: name.isEmpty ? "Preparing tool call" : "Preparing: \(name)", clearHumanRequest: true, clearError: true)
        case "agent_tool_call":
            let name = event.string("name") ?? ""
            let agentId = event.string("agent_id") ?? ""
            next = update(run, status: .running, activity: "Agent \(agentId): \(name)", clearHumanRequest: true, clearError: true)
        case "agent_tool_call_delta":
            let name = event.string("name")?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let agentId = event.string("agent_id") ?? ""
            next = update(run, status: .running, activity: name.isEmpty ? "Agent \(agentId): preparing tool call" : "Agent \(agentId): preparing \(name)", clearHumanRequest: true, clearError: true)
        case "tool_output_chunk":
            let stream = event.string("stream") ?? ""
            next = update(run, status: .running, activity: stream == "stderr" ? "Reading stderr" : "Reading output", clearHumanRequest: true, clearError: true)
        case "reasoning_delta", "thinking":
            next = update(run, status: .running, activity: "Thinking", clearHumanRequest: true, clearError: true)
        case "response_delta", "response":
            next = update(run, status: .running, activity: "Writing response", clearHumanRequest: true, clearError: true)
        case "asking_human":
            next = update(run, status: .waitingForInput, activity: "Waiting for input", humanRequestId: event.string("request_id"), clearError: true)
        case "human_response", "message_injected":
            next = update(run, status: .running, activity: "Continuing", clearHumanRequest: true, clearError: true)
        case "stream_reset":
            next = update(run, status: .running, activity: "Reconnecting", clearHumanRequest: true, clearError: true)
        case "error":
            let message = event.string("message") ?? "Error"
            next = update(run, status: .failed, activity: message, error: message)
        case "evolution_queued":
            next = update(run, status: .completed, activity: "Queued learning", clearHumanRequest: true)
        case "skill_activated":
            next = update(run, status: .running, activity: skillActivity(event), clearHumanRequest: true, clearError: true)
        default:
            return run
        }
        return next
    }

    func complete(_ run: NapaxiSessionRunInfo, activity: String = "Completed") -> NapaxiSessionRunInfo {
        if isLocallyCancelled(run) || run.status == .cancelling {
            return cancelled(run)
        }
        return update(run, status: .completed, activity: activity, clearHumanRequest: true)
    }

    func cancelling(agentId: String, key: NapaxiSessionKey) -> NapaxiSessionRunInfo? {
        guard let run = activeRun(agentId: agentId, key: key) else { return nil }
        return update(run, status: .cancelling, activity: "Stopping")
    }

    func cancelled(_ run: NapaxiSessionRunInfo) -> NapaxiSessionRunInfo {
        lock.lock()
        locallyCancelled[run.id] = run.startedAt
        lock.unlock()
        return update(run, status: .cancelled, activity: "Cancelled", clearHumanRequest: true)
    }

    func fail(_ run: NapaxiSessionRunInfo, error: Error) -> NapaxiSessionRunInfo {
        let message = String(describing: error)
        return update(run, status: .failed, activity: message, error: message)
    }

    func finish() {
        broadcaster.finish()
    }

    private func update(
        _ run: NapaxiSessionRunInfo,
        status: NapaxiSessionRunStatus? = nil,
        activity: String? = nil,
        humanRequestId: String? = nil,
        clearHumanRequest: Bool = false,
        error: String? = nil,
        clearError: Bool = false
    ) -> NapaxiSessionRunInfo {
        let updated = run.updated(
            status: status,
            activity: activity,
            humanRequestId: humanRequestId,
            clearHumanRequest: clearHumanRequest,
            error: error,
            clearError: clearError
        )
        lock.lock()
        if updated.isTerminal {
            let current = active[updated.id]
            if current == nil || current?.startedAt == updated.startedAt {
                active.removeValue(forKey: updated.id)
            }
        } else {
            active[updated.id] = updated
        }
        lock.unlock()
        broadcaster.emit(updated)
        return updated
    }

    private func isLocallyCancelled(_ run: NapaxiSessionRunInfo) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return locallyCancelled[run.id] == run.startedAt
    }

    private func id(agentId: String, key: NapaxiSessionKey) -> String {
        "\(agentId):\(key.channelType):\(key.accountId):\(key.threadId)"
    }

    private func skillActivity(_ event: NapaxiChatEvent) -> String {
        guard case .object(let object) = event.raw,
              case .array(let skills)? = object["skills"] else {
            return "Using skill"
        }
        if skills.count == 1,
           case .object(let skill)? = skills.first {
            let name = skill["name"]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return name.isEmpty ? "Using skill" : "Using skill: \(name)"
        }
        return "Using \(skills.count) skills"
    }
}
