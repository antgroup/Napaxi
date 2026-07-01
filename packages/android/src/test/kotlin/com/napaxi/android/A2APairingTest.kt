package com.napaxi.android

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class A2APairingTest {
    // Adapter-parity guard: the Android invite codec must agree with the shared
    // wire contract. The values below mirror the cross-adapter fixture at
    // packages/api_contract/fixtures/a2a/local_pairing_invite.json. If the
    // fixture changes, this test must change with it (and so must the Flutter
    // and iOS codecs).
    @Test
    fun inviteCodecMatchesSharedContract() {
        val invite = A2AInvite(
            peerId = "peer-fixture-001",
            publicKey = "pubkey-fixture-abc123",
            pairingSecret = "secret-fixture-xyz789",
            agentId = "agent.fixture",
            displayName = "Fixture Phone",
            endpoint = "lan://192.168.1.20:7100",
            transport = "lan_tcp_jsonl",
            createdAt = "2026-06-08T00:00:00Z",
        )

        val payload = invite.toQrPayload()
        assertTrue(payload.startsWith(A2AInvite.QR_PREFIX))
        assertEquals("napaxi-a2a-invite:", A2AInvite.QR_PREFIX)

        val decoded = A2AInvite.tryDecodePayload(payload)
            ?: error("shared-shape invite must decode")
        assertEquals(1, decoded.version)
        assertEquals("peer-fixture-001", decoded.peerId)
        assertEquals("pubkey-fixture-abc123", decoded.publicKey)
        assertEquals("secret-fixture-xyz789", decoded.pairingSecret)
        assertEquals("lan://192.168.1.20:7100", decoded.endpoint)
        assertEquals("lan_tcp_jsonl", decoded.transport)

        // A /a2a join line and a bare code both decode.
        assertEquals(
            "peer-fixture-001",
            A2AInvite.tryDecodePayload("/a2a join ${invite.toCode()}")?.peerId,
        )
        assertEquals(
            "peer-fixture-001",
            A2AInvite.tryDecodePayload(invite.toCode())?.peerId,
        )
    }

    @Test
    fun inviteCodecRejectsMalformedAndIncompleteInvites() {
        assertNull(A2AInvite.tryDecodeCode(""))
        assertNull(A2AInvite.tryDecodeCode("!!!not base64!!!"))
        assertNull(A2AInvite.tryDecodePayload("   "))

        for (missing in listOf("peerId", "publicKey", "pairingSecret")) {
            val map = mutableMapOf(
                "v" to 1,
                "peerId" to "p",
                "publicKey" to "k",
                "pairingSecret" to "s",
            )
            map.remove(missing)
            val json = org.json.JSONObject(map as Map<*, *>).toString()
            val code = java.util.Base64.getUrlEncoder().withoutPadding()
                .encodeToString(json.toByteArray(Charsets.UTF_8))
            assertNull("invite missing $missing must be rejected", A2AInvite.tryDecodeCode(code))
        }
    }
}
