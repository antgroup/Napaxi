package com.napaxi.android

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class ChatEventContractTest {
    // Adapter-parity guard: the Android ChatEvent codec must agree with the
    // shared wire contract. The values below mirror the cross-adapter fixtures
    // under packages/api_contract/fixtures/chat_event/. If a fixture changes,
    // this test must change with it (and so must the Flutter and iOS codecs).
    //
    // mirrors: fixtures/chat_event/tool_call.json
    @Test
    fun toolCallMatchesSharedContract() {
        val event = ChatEvent.fromJson(
            """{"type":"tool_call","call_id":"call-fixture-001",""" +
                """"name":"home_light_set","arguments":"{\"room\":\"kitchen\",\"on\":true}"}""",
        )
        assertTrue(event is ChatEvent.ToolCallEvent)
        event as ChatEvent.ToolCallEvent
        assertEquals("call-fixture-001", event.callId)
        assertEquals("home_light_set", event.name)
        assertEquals("""{"room":"kitchen","on":true}""", event.arguments)
    }

    // mirrors: fixtures/chat_event/tool_result.json
    @Test
    fun toolResultMatchesSharedContract() {
        val event = ChatEvent.fromJson(
            """{"type":"tool_result","call_id":"call-fixture-001",""" +
                """"name":"home_light_set","output":"{\"ok\":true}","is_error":false}""",
        )
        assertTrue(event is ChatEvent.ToolResultEvent)
        event as ChatEvent.ToolResultEvent
        assertEquals("call-fixture-001", event.callId)
        assertEquals("home_light_set", event.name)
        assertEquals("""{"ok":true}""", event.output)
        assertFalse(event.isError)
    }

    // mirrors: fixtures/chat_event/response_delta.json
    @Test
    fun responseDeltaMatchesSharedContract() {
        val event = ChatEvent.fromJson(
            """{"type":"response_delta","content":"Turning on the kitchen light."}""",
        )
        assertTrue(event is ChatEvent.ResponseDeltaEvent)
        assertEquals(
            "Turning on the kitchen light.",
            (event as ChatEvent.ResponseDeltaEvent).content,
        )
    }

    // mirrors: fixtures/chat_event/run_started.json
    @Test
    fun runStartedMatchesSharedContract() {
        val event = ChatEvent.fromJson(
            """{"type":"run_started","run_id":"run-fixture-001",""" +
                """"session_key":"{\"channel_type\":\"app\",\"account_id\":\"user\",""" +
                """\"thread_id\":\"thread-fixture-001\"}","agent_id":"napaxi"}""",
        )
        assertTrue(event is ChatEvent.RunStartedEvent)
        event as ChatEvent.RunStartedEvent
        assertEquals("run-fixture-001", event.runId)
        assertEquals("napaxi", event.agentId)
        assertTrue(event.sessionKey.contains("thread-fixture-001"))
    }
}
