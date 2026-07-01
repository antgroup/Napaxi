import XCTest
@testable import Napaxi

final class AutomationTests: XCTestCase {
    func testAutomationAPIMirrorsFlutterFacadeMethodNames() {
        let api = NapaxiAutomationAPI(rawAPI: NapaxiRawAPI(handle: 0))

        let create: (NapaxiAutomationJob) throws -> NapaxiAutomationJob = api.createAutomationJob
        let update: (String, [String: NapaxiJSONValue]) throws -> NapaxiAutomationJob = api.updateAutomationJob
        let delete: (String) throws -> Bool = api.deleteAutomationJob
        let list: (String?, String?, Bool?) throws -> [NapaxiAutomationJob] = api.listAutomationJobs
        let get: (String) throws -> NapaxiAutomationJob? = api.getAutomationJob
        let run: (String, String) throws -> NapaxiAutomationRun = api.runAutomationJob
        let runs: (String?, Int, Int) throws -> [NapaxiAutomationRun] = api.listAutomationRuns
        let nextWake: () throws -> NapaxiAutomationWake? = api.getNextAutomationWake
        let recordWake: (String, String) throws -> NapaxiAutomationRun = { try api.recordAutomationWake($0, $1) }

        XCTAssertNotNil(create)
        XCTAssertNotNil(update)
        XCTAssertNotNil(delete)
        XCTAssertNotNil(list)
        XCTAssertNotNil(get)
        XCTAssertNotNil(run)
        XCTAssertNotNil(runs)
        XCTAssertNotNil(nextWake)
        XCTAssertNotNil(recordWake)
    }

    func testAutomationJobEncodesFlutterCompatibleCamelCasePayload() throws {
        let job = NapaxiAutomationJob(
            name: "Morning brief",
            accountId: "user-1",
            agentId: "napaxi",
            trigger: .interval(everyMs: 3_600_000, anchorMs: 1_000),
            payload: .agentTurn(
                message: "Summarize overnight activity",
                sessionMode: "existing",
                modelProfileId: "primary",
                maxIterations: 4
            ),
            policy: NapaxiAutomationPolicy(
                requiresUserVisibleNotification: false,
                allowHighRiskTools: true,
                maxRunDurationMs: 120_000,
                maxRetries: 1,
                retryBackoffMs: [10_000],
                deleteAfterSuccess: true
            )
        )

        let decoded = try XCTUnwrap(decodeObject(try job.jsonString()))
        let trigger = try XCTUnwrap(decoded["trigger"] as? [String: Any])
        let payload = try XCTUnwrap(decoded["payload"] as? [String: Any])
        let policy = try XCTUnwrap(decoded["policy"] as? [String: Any])

        XCTAssertEqual(decoded["name"] as? String, "Morning brief")
        XCTAssertEqual(decoded["accountId"] as? String, "user-1")
        XCTAssertEqual(decoded["agentId"] as? String, "napaxi")
        XCTAssertEqual(trigger["kind"] as? String, "interval")
        XCTAssertEqual(trigger["everyMs"] as? Int, 3_600_000)
        XCTAssertEqual(trigger["anchorMs"] as? Int, 1_000)
        XCTAssertEqual(payload["kind"] as? String, "agentTurn")
        XCTAssertEqual(payload["message"] as? String, "Summarize overnight activity")
        XCTAssertEqual(payload["sessionMode"] as? String, "existing")
        XCTAssertEqual(payload["modelProfileId"] as? String, "primary")
        XCTAssertEqual(payload["maxIterations"] as? Int, 4)
        XCTAssertEqual(policy["requiresUserVisibleNotification"] as? Bool, false)
        XCTAssertEqual(policy["allowHighRiskTools"] as? Bool, true)
        XCTAssertEqual(policy["deleteAfterSuccess"] as? Bool, true)
    }

    func testAutomationMapHelpersMirrorFlutterToJsonFromJson() throws {
        let trigger = NapaxiAutomationTrigger.fromJson([
            "kind": .string("hostEvent"),
            "event_type": .string("calendar.changed"),
            "source": .string("host"),
        ])
        let payload = NapaxiAutomationPayload.fromJson([
            "kind": .string("agentTurn"),
            "message": .string("Handle it"),
            "session_mode": .string("existing"),
            "model_profile_id": .string("primary"),
            "max_iterations": .string("5"),
        ])
        let policy = NapaxiAutomationPolicy.fromJson([
            "allow_high_risk_tools": .bool(true),
            "retry_backoff_ms": .array([.string("1000"), .number(2000)]),
            "delete_after_success": .bool(true),
        ])
        let state = NapaxiAutomationJobState.fromJson([
            "next_run_at_ms": .string("123"),
            "running_run_id": .string("run-1"),
        ])
        let job = NapaxiAutomationJob.fromJson([
            "id": .string("job-1"),
            "name": .string("Wake"),
            "account_id": .string("user-1"),
            "agent_id": .string("napaxi"),
            "trigger": .object(trigger.toJson()),
            "payload": .object(payload.toJson()),
            "policy": .object(policy.toJson()),
            "state": .object(state.toJson()),
            "created_at": .number(10),
        ])

        XCTAssertEqual(trigger.toJson()["eventType"], .string("calendar.changed"))
        XCTAssertEqual(payload.toJson()["sessionMode"], .string("existing"))
        XCTAssertEqual(payload.toJson()["maxIterations"], .number(5))
        XCTAssertEqual(policy.toJson()["allowHighRiskTools"], .bool(true))
        XCTAssertEqual(policy.toJson()["retryBackoffMs"], .array([.number(1_000), .number(2_000)]))
        XCTAssertEqual(state.toJson()["nextRunAtMs"], .number(123))
        XCTAssertEqual(job.accountId, "user-1")
        XCTAssertEqual(job.agentId, "napaxi")
        XCTAssertEqual(job.trigger.eventType, "calendar.changed")
        XCTAssertEqual(job.payload.maxIterations, 5)
        XCTAssertEqual(job.policy.retryBackoffMs, [1_000, 2_000])
        XCTAssertEqual(job.state.runningRunId, "run-1")
        XCTAssertEqual(job.toJson()["accountId"], .string("user-1"))
        XCTAssertNil(job.toJson()["state"])
    }

    func testAutomationJobDecodesSnakeCaseCoreFieldsWithFlutterDefaults() throws {
        let json = """
        {
          "id": "job-1",
          "name": "Wake",
          "account_id": "user-1",
          "agent_id": "napaxi",
          "trigger": {"kind": "oneShotAt", "at_ms": 123, "timezone": "UTC"},
          "payload": {"kind": "systemEvent", "text": "hello", "session_key": "{\\"thread_id\\":\\"t\\"}"},
          "policy": {"retry_backoff_ms": ["30000", 300000]},
          "state": {"next_run_at_ms": "456", "consecutive_errors": 2},
          "created_at": 10,
          "updated_at": 20
        }
        """

        let job = try JSONDecoder().decode(NapaxiAutomationJob.self, from: Data(json.utf8))

        XCTAssertEqual(job.id, "job-1")
        XCTAssertEqual(job.accountId, "user-1")
        XCTAssertEqual(job.agentId, "napaxi")
        XCTAssertTrue(job.enabled)
        XCTAssertEqual(job.trigger.atMs, 123)
        XCTAssertEqual(job.trigger.timezone, "UTC")
        XCTAssertEqual(job.payload.text, "hello")
        XCTAssertEqual(job.payload.sessionKeyJSON, #"{"thread_id":"t"}"#)
        XCTAssertEqual(job.payload.sessionKeyJson, #"{"thread_id":"t"}"#)
        XCTAssertEqual(job.payload.wakeMode, "next_foreground_or_host_wake")
        XCTAssertEqual(job.policy.retryBackoffMs, [30_000, 300_000])
        XCTAssertEqual(job.state.nextRunAtMs, 456)
        XCTAssertEqual(job.state.consecutiveErrors, 2)
        XCTAssertEqual(job.createdAt, 10)
        XCTAssertEqual(job.updatedAt, 20)
    }

    func testAutomationRunAndWakeDecodeFlutterCompatibleKeys() throws {
        let runJSON = """
        {
          "run_id": "run-1",
          "job_id": "job-1",
          "status": "succeeded",
          "trigger_source": "manual",
          "started_at": 100,
          "completed_at": 200,
          "duration_ms": 100,
          "session_key": "{\\"thread_id\\":\\"t\\"}",
          "tool_call_count": 3,
          "delivery_status": "delivered"
        }
        """
        let wakeJSON = """
        {
          "jobId": "job-1",
          "atMs": 500,
          "trigger": {"kind": "manual"}
        }
        """

        let run = try JSONDecoder().decode(NapaxiAutomationRun.self, from: Data(runJSON.utf8))
        let wake = try JSONDecoder().decode(NapaxiAutomationWake.self, from: Data(wakeJSON.utf8))

        XCTAssertEqual(run.runId, "run-1")
        XCTAssertEqual(run.jobId, "job-1")
        XCTAssertEqual(run.status, "succeeded")
        XCTAssertEqual(run.triggerSource, "manual")
        XCTAssertEqual(run.startedAt, 100)
        XCTAssertEqual(run.completedAt, 200)
        XCTAssertEqual(run.durationMs, 100)
        XCTAssertEqual(run.sessionKeyJSON, #"{"thread_id":"t"}"#)
        XCTAssertEqual(run.sessionKeyJson, #"{"thread_id":"t"}"#)
        XCTAssertEqual(run.toolCallCount, 3)
        XCTAssertEqual(run.deliveryStatus, "delivered")
        XCTAssertEqual(wake.jobId, "job-1")
        XCTAssertEqual(wake.atMs, 500)
        XCTAssertEqual(wake.trigger.kind, "manual")
    }

    func testAutomationRunWakeAndObjectDecodeHelpersMirrorFlutter() throws {
        let object = try decodeJsonObjectOrNull(#"{"id":"job-1","enabled":true}"#)
        let error = try decodeJsonObjectOrNull(#"{"error":"missing"}"#)
        let run = NapaxiAutomationRun.fromJson([
            "run_id": .string("run-1"),
            "job_id": .string("job-1"),
            "status": .string("succeeded"),
            "trigger_source": .string("manual"),
            "started_at": .string("100"),
            "tool_call_count": .number(2),
        ])
        let wake = NapaxiAutomationWake.fromJson([
            "job_id": .string("job-1"),
            "at_ms": .number(200),
            "trigger": .object(["kind": .string("manual")]),
        ])

        XCTAssertEqual(object?["id"], .string("job-1"))
        XCTAssertNil(error)
        XCTAssertThrowsError(try decodeJsonObjectOrNull("not json"))
        XCTAssertEqual(run.runId, "run-1")
        XCTAssertEqual(run.deliveryStatus, "unknown")
        XCTAssertEqual(run.startedAt, 100)
        XCTAssertEqual(run.toolCallCount, 2)
        XCTAssertEqual(wake.jobId, "job-1")
        XCTAssertEqual(wake.atMs, 200)
        XCTAssertEqual(wake.trigger.kind, "manual")
    }

    func testAutomationTypedDecodersMirrorFlutterErrorHandling() throws {
        let job = try NapaxiAutomationAPI.decodeJob(from: .object([
            "id": .string("job-1"),
            "name": .string("Morning brief"),
            "trigger": .object(["kind": .string("manual")]),
            "payload": .object(["kind": .string("systemEvent")]),
        ]))
        XCTAssertEqual(job.id, "job-1")

        XCTAssertNil(try NapaxiAutomationAPI.decodeJobOrNil(from: .object([
            "error": .string("missing"),
        ])))
        XCTAssertNil(try NapaxiAutomationAPI.decodeJobOrNil(from: .array([])))

        let wake = try XCTUnwrap(NapaxiAutomationAPI.decodeWakeOrNil(from: .object([
            "job_id": .string("job-1"),
            "at_ms": .number(123),
            "trigger": .object(["kind": .string("manual")]),
        ])))
        XCTAssertEqual(wake.jobId, "job-1")
        XCTAssertEqual(wake.atMs, 123)
        XCTAssertNil(try NapaxiAutomationAPI.decodeWakeOrNil(from: .null))
        XCTAssertNil(try NapaxiAutomationAPI.decodeWakeOrNil(from: .array([])))
        XCTAssertNil(try NapaxiAutomationAPI.decodeWakeOrNil(from: .string("bad")))

        let errorWake = try XCTUnwrap(NapaxiAutomationAPI.decodeWakeOrNil(from: .object([
            "error": .string("missing"),
        ])))
        XCTAssertEqual(errorWake.jobId, "")
        XCTAssertEqual(errorWake.atMs, 0)
        XCTAssertThrowsError(try NapaxiAutomationAPI.decodeWakeOrNil(from: .object([
            "job_id": .string("job-1"),
            "trigger": .string("manual"),
        ]))) { error in
            XCTAssertEqual(error as? NapaxiError, .invalidJSON("Expected automation wake trigger object"))
        }

        XCTAssertThrowsError(try NapaxiAutomationAPI.decodeJob(from: .object([
            "error": .string("create failed"),
        ]))) { error in
            XCTAssertEqual(error as? NapaxiError, .invalidState("create failed"))
        }
        XCTAssertThrowsError(try NapaxiAutomationAPI.decodeJob(from: .array([]))) { error in
            XCTAssertEqual(error as? NapaxiError, .invalidJSON("Expected automation job object"))
        }
        let nullNestedJob = try NapaxiAutomationAPI.decodeJob(from: .object([
            "name": .string("Null defaults"),
            "trigger": .null,
            "payload": .null,
            "policy": .null,
            "state": .null,
        ]))
        XCTAssertEqual(nullNestedJob.trigger.kind, "manual")
        XCTAssertEqual(nullNestedJob.payload.kind, "systemEvent")
        XCTAssertEqual(nullNestedJob.policy.maxRetries, 2)
        XCTAssertEqual(nullNestedJob.state.consecutiveErrors, 0)
        XCTAssertThrowsError(try NapaxiAutomationAPI.decodeJob(from: .object([
            "name": .string("Bad trigger"),
            "trigger": .string("manual"),
        ]))) { error in
            XCTAssertEqual(error as? NapaxiError, .invalidJSON("Expected automation job trigger object"))
        }
        XCTAssertThrowsError(try NapaxiAutomationAPI.decodeJob(from: .object([
            "name": .string("Bad payload"),
            "payload": .array([]),
        ]))) { error in
            XCTAssertEqual(error as? NapaxiError, .invalidJSON("Expected automation job payload object"))
        }

        let run = try NapaxiAutomationAPI.decodeRun(from: .object([
            "run_id": .string("run-1"),
            "job_id": .string("job-1"),
            "status": .string("succeeded"),
        ]))
        XCTAssertEqual(run.runId, "run-1")

        XCTAssertThrowsError(try NapaxiAutomationAPI.decodeRun(from: .object([
            "error": .string("run failed"),
        ]))) { error in
            XCTAssertEqual(error as? NapaxiError, .invalidState("run failed"))
        }
        XCTAssertThrowsError(try NapaxiAutomationAPI.decodeRun(from: .string("bad"))) { error in
            XCTAssertEqual(error as? NapaxiError, .invalidJSON("Expected automation run object"))
        }
    }

    func testAutomationDecodeHelpersMirrorFlutterHelpers() throws {
        let jobs = try decodeAutomationJobs("""
        [
          {
            "id": "job-1",
            "name": "Morning brief",
            "account_id": "default",
            "agent_id": "napaxi",
            "trigger": {"kind": "manual"},
            "payload": {"kind": "systemEvent", "text": "hello"}
          },
          "ignored"
        ]
        """)
        let runs = try decodeAutomationRuns("""
        [
          {
            "run_id": "run-1",
            "job_id": "job-1",
            "status": "succeeded",
            "trigger_source": "manual",
            "started_at": "100",
            "tool_call_count": 2
          },
          false
        ]
        """)

        XCTAssertEqual(jobs.map(\.id), ["job-1"])
        XCTAssertEqual(jobs.first?.payload.text, "hello")
        XCTAssertEqual(runs.map(\.runId), ["run-1"])
        XCTAssertEqual(runs.first?.startedAt, 100)
        XCTAssertEqual(runs.first?.toolCallCount, 2)
        XCTAssertEqual(try NapaxiAutomationAPI.decodeJobs(from: .object(["error": .string("ignored")])).count, 0)
        XCTAssertEqual(try NapaxiAutomationAPI.decodeRuns(from: .string("ignored")).count, 0)
        XCTAssertEqual(try decodeAutomationJobs(#"{"id":"not-array"}"#), [])
        XCTAssertThrowsError(try decodeAutomationRuns("not json"))
    }
}

private func decodeObject(_ value: String) throws -> [String: Any]? {
    let decoded = try JSONSerialization.jsonObject(with: Data(value.utf8))
    return decoded as? [String: Any]
}
