import Foundation

// iOS adapter parity for the Flutter automation scheduler surface
// (`packages/flutter/lib/background/automation_scheduler.dart` and the
// scheduler models in `models/automation.dart`).
//
// Platform-level wake scheduling (Android's AlarmManager) is NOT supported on
// iOS: background execution is unavailable (see `isBackgroundExecutionSupported`
// and `NapaxiBackgroundPermissions.isSupported`). The scheduler therefore
// exposes the same API as the Flutter adapter but reports an explicit
// unsupported state for platform-scheduled wakes, while the core-backed
// catch-up path (driven through `NapaxiAutomationAPI`) still runs. This is the
// deliberate platform difference required by `docs/sdk-adapter-parity.md`.

/// Snapshot of the platform scheduler's state. Mirrors the Flutter
/// `AutomationSchedulerStatus`.
public struct NapaxiAutomationSchedulerStatus: Codable, Equatable, Sendable {
    public var supported: Bool
    public var platform: String
    public var pendingWakeCount: Int
    public var nextPendingWake: NapaxiAutomationPendingWake?
    public var reason: String?

    public init(
        supported: Bool,
        platform: String,
        pendingWakeCount: Int = 0,
        nextPendingWake: NapaxiAutomationPendingWake? = nil,
        reason: String? = nil
    ) {
        self.supported = supported
        self.platform = platform
        self.pendingWakeCount = pendingWakeCount
        self.nextPendingWake = nextPendingWake
        self.reason = reason
    }

    public static func fromJson(_ json: [String: NapaxiJSONValue]) -> Self {
        let next = json["nextPendingWake"] ?? json["next_pending_wake"]
        return Self(
            supported: json["supported"]?.boolValue ?? false,
            platform: json["platform"]?.stringValue ?? "",
            pendingWakeCount: json["pendingWakeCount"]?.napaxiIntValue
                ?? json["pending_wake_count"]?.napaxiIntValue ?? 0,
            nextPendingWake: next?.objectValue.map(NapaxiAutomationPendingWake.fromJson),
            reason: json["reason"]?.stringValue
        )
    }
}

/// A platform wake that fired and is waiting to be drained into a run. Mirrors
/// the Flutter `AutomationPendingWake`.
public struct NapaxiAutomationPendingWake: Codable, Equatable, Sendable {
    public var wakeId: String
    public var jobId: String
    public var atMs: Int
    public var firedAtMs: Int
    public var source: String

    public init(wakeId: String, jobId: String, atMs: Int, firedAtMs: Int, source: String) {
        self.wakeId = wakeId
        self.jobId = jobId
        self.atMs = atMs
        self.firedAtMs = firedAtMs
        self.source = source
    }

    public static func fromJson(_ json: [String: NapaxiJSONValue]) -> Self {
        let jobId = json["jobId"]?.stringValue ?? json["job_id"]?.stringValue ?? ""
        let firedAtMs = json["firedAtMs"]?.napaxiIntValue ?? json["fired_at_ms"]?.napaxiIntValue ?? 0
        let wakeId = json["wakeId"]?.stringValue
            ?? json["wake_id"]?.stringValue
            ?? "\(jobId):\(firedAtMs)"
        return Self(
            wakeId: wakeId,
            jobId: jobId,
            atMs: json["atMs"]?.napaxiIntValue ?? json["at_ms"]?.napaxiIntValue ?? 0,
            firedAtMs: firedAtMs,
            source: json["source"]?.stringValue ?? "platform_wake"
        )
    }

    public func toJson() -> [String: NapaxiJSONValue] {
        [
            "wakeId": .string(wakeId),
            "jobId": .string(jobId),
            "atMs": .number(Double(atMs)),
            "firedAtMs": .number(Double(firedAtMs)),
            "source": .string(source),
        ]
    }
}

/// Result of a scheduler `sync()`. Mirrors the Flutter
/// `AutomationSchedulerSyncResult`.
public struct NapaxiAutomationSchedulerSyncResult: Sendable {
    public var runs: [NapaxiAutomationRun]
    public var scheduledWake: NapaxiAutomationWake?
    public var platformWakeScheduled: Bool

    public init(
        runs: [NapaxiAutomationRun] = [],
        scheduledWake: NapaxiAutomationWake? = nil,
        platformWakeScheduled: Bool = false
    ) {
        self.runs = runs
        self.scheduledWake = scheduledWake
        self.platformWakeScheduled = platformWakeScheduled
    }
}

/// Host-carried scheduler for automation jobs. Mirrors the Flutter
/// `NapaxiAutomationScheduler`. On iOS the platform-scheduling seam is
/// unavailable, so `isSupported` is false and platform-pending-wake operations
/// are inert; the core-backed catch-up path still records due jobs.
public final class NapaxiAutomationScheduler: @unchecked Sendable {
    private let automation: NapaxiAutomationAPI

    public init(automation: NapaxiAutomationAPI) {
        self.automation = automation
    }

    /// iOS has no platform wake scheduler (no background execution).
    public var isSupported: Bool { false }

    public func status() -> NapaxiAutomationSchedulerStatus {
        NapaxiAutomationSchedulerStatus(
            supported: false,
            platform: "ios",
            reason: "platform scheduler is not available on iOS"
        )
    }

    /// Returns the next core-computed wake, if any. On iOS this cannot be
    /// handed to a platform scheduler, so the wake is informational only.
    @discardableResult
    public func rescheduleNextWake(exact: Bool = false) throws -> NapaxiAutomationWake? {
        try automation.getNextAutomationWake()
    }

    /// iOS has no platform pending-wake store.
    public func pendingWakes() -> [NapaxiAutomationPendingWake] {
        []
    }

    /// iOS has no platform pending wakes to drain.
    public func drainPendingWakes() -> [NapaxiAutomationRun] {
        []
    }

    /// Record runs for every enabled job whose next run time is due. This is
    /// core-backed and works on iOS even without a platform scheduler.
    public func catchUpDueJobs(nowMs: Int? = nil, limit: Int = 5) throws -> [NapaxiAutomationRun] {
        let now = nowMs ?? Int(Date().timeIntervalSince1970 * 1000)
        let jobs = try automation.listAutomationJobs(enabled: true)
        let due = jobs.filter { job in
            guard let next = job.state.nextRunAtMs else { return false }
            return next <= now
        }.prefix(min(limit, 50))
        var runs: [NapaxiAutomationRun] = []
        for job in due {
            runs.append(try automation.recordAutomationWake(jobId: job.id, source: "catch_up"))
        }
        return runs
    }

    @discardableResult
    public func sync(exact: Bool = false, catchUpLimit: Int = 5) throws -> NapaxiAutomationSchedulerSyncResult {
        let runs = drainPendingWakes() + (try catchUpDueJobs(limit: catchUpLimit))
        let wake = try rescheduleNextWake(exact: exact)
        return NapaxiAutomationSchedulerSyncResult(
            runs: runs,
            scheduledWake: wake,
            platformWakeScheduled: false
        )
    }

    /// No-op on iOS: there is no platform wake event channel to listen on.
    /// Mirrors the Flutter `startWakeListener` API for source parity.
    public func startWakeListener(exact: Bool = false, catchUpLimit: Int = 10, notify: Bool = true) {
        // Unsupported on iOS — see file header.
    }
}

// MARK: - Flutter migration aliases

public typealias AutomationSchedulerStatus = NapaxiAutomationSchedulerStatus
public typealias AutomationPendingWake = NapaxiAutomationPendingWake
public typealias AutomationSchedulerSyncResult = NapaxiAutomationSchedulerSyncResult
