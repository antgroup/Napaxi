package com.napaxi.android

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class RuntimeContractTest {
    // Adapter-parity guard: the Android codecs for capability status, session-run
    // records, and automation jobs must agree with the shared wire contract. The
    // values below mirror the cross-adapter fixtures under
    // packages/api_contract/fixtures/{capability,session_run,automation}/. If a
    // fixture changes, this test must change with it (and so must the Flutter and
    // iOS codecs).

    // mirrors: fixtures/capability/capability_status.json
    @Test
    fun capabilityStatusMatchesSharedContract() {
        val status = NapaxiCapabilityStatus(
            """
            {"definition":{"id":"napaxi.tool.custom_host","kind":"tool","version":"1",
            "platforms":["all"],"config_schema":{},"risk":"medium",
            "requirements":["host_tool_dispatcher"],"default_enabled":false,
            "activation":"host"},"registered":true,"available":true,"enabled":true}
            """.trimIndent(),
        )
        assertTrue(status.registered)
        assertTrue(status.available)
        assertTrue(status.enabled)
        assertEquals("napaxi.tool.custom_host", status.definition.id)
        assertEquals("tool", status.definition.kind)
        assertEquals("medium", status.definition.risk)
        assertEquals("host", status.definition.activation)
        assertFalse(status.definition.defaultEnabled)
    }

    // mirrors: fixtures/session_run/session_run_record.json
    @Test
    fun sessionRunRecordMatchesSharedContract() {
        val json = """
            {"runId":"run-fixture-001","status":"succeeded","agentId":"napaxi",
            "sessionKey":"{}","threadId":"thread-fixture-001","startedAt":1717800000000,
            "completedAt":1717800002500,"durationMs":2500,"evidenceKind":"tool_observed",
            "verification":"verified","toolCallCount":1,
            "evidence":[{"kind":"tool_observed","source":"home_light_set","isError":false}],
            "summary":"Turned on the kitchen light.","childRunIds":[]}
        """.trimIndent()
        val record = decodeSessionRunRecords("[$json]").single()

        assertEquals("run-fixture-001", record.runId)
        assertEquals(SessionRunRecordStatus.Succeeded, record.status)
        assertEquals("napaxi", record.agentId)
        assertEquals("thread-fixture-001", record.threadId)
        assertEquals(RunEvidenceKind.ToolObserved, record.evidenceKind)
        assertEquals(RunVerification.Verified, record.verification)
        assertEquals(1, record.toolCallCount)
        assertEquals(1, record.evidence.size)
        assertEquals("home_light_set", record.evidence.single().source)
        assertFalse(record.evidence.single().isError)
    }

    // mirrors: fixtures/automation/automation_job.json
    @Test
    fun automationJobMatchesSharedContract() {
        val job = AutomationJob.fromJson(
            """
            {"id":"job-fixture-001","name":"Morning briefing","enabled":true,
            "accountId":"user","agentId":"napaxi",
            "trigger":{"kind":"localTime","hour":8,"minute":30,
            "timezone":"America/New_York","daysOfWeek":[1,2,3,4,5]},
            "payload":{"kind":"agentTurn","message":"Give me my morning briefing.",
            "sessionMode":"isolated","maxIterations":4},
            "policy":{"requiresUserVisibleNotification":true,"allowHighRiskTools":false,
            "maxRunDurationMs":120000,"maxRetries":2,"retryBackoffMs":[1000,5000]},
            "state":{},"createdAt":1717800000000,"updatedAt":1717800000000}
            """.trimIndent(),
        )
        assertEquals("job-fixture-001", job.id)
        assertTrue(job.enabled)
        assertEquals("napaxi", job.agentId)
        assertEquals("localTime", job.trigger.kind)
        assertEquals("America/New_York", job.trigger.timezone)
        assertEquals("agentTurn", job.payload.kind)
        assertEquals("Give me my morning briefing.", job.payload.message)
        assertEquals(4, job.payload.maxIterations)
        assertTrue(job.policy.requiresUserVisibleNotification)
        assertEquals(2, job.policy.maxRetries)
    }
}
