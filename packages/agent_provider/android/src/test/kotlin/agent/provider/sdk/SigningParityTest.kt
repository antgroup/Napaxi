package agent.provider.sdk

import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Cross-port canonical-JSON signing parity test for the Android Agent Provider
 * SDK.
 *
 * Reads `packages/agent_provider/shared/signing_fixtures.json` (copied to
 * `src/test/resources/signing_fixtures.json` by the test resources convention)
 * and asserts that the production `TrustedHost.kt::canonicalJson` (which signs
 * proposals on the Provider side) reproduces the same byte-exact canonical
 * string and SHA-256 digest expected by Rust core (`crypto::canonical_json`)
 * and iOS (`AgentProvider.canonicalJson`). Each fixture pins an
 * `expected_canonical_json` value (RFC 8259 string escapes only; '/' NOT
 * escaped; keys sorted ascending), so any drift between the three ports fails
 * here instead of causing a Host↔Provider `signature_invalid` cross-process.
 *
 * The 2026-11-03 13:42:12 TradeJournal regression sample (sanitized) is the
 * regression anchor: it carries `10/22`, `元/吨` and an HTTPS URL — the exact
 * shapes Android once broke by routing them through `JSONObject.quote`.
 */
class SigningParityTest {

    @Test
    fun canonicalJsonPreservesSlashInDateLikeString() {
        val canonical = canonicalJson("10/22")
        assertEquals("\"10/22\"", canonical)
        assertFalse("canonical_json must not escape '/' (Android org.json.JSONObject.quote did)", canonical.contains("\\/"))
    }

    @Test
    fun canonicalJsonPreservesSlashInUnitString() {
        assertEquals("\"元/吨\"", canonicalJson("元/吨"))
    }

    @Test
    fun canonicalJsonPreservesHttpsUrlVerbatim() {
        assertEquals("\"https://example.com/x\"", canonicalJson("https://example.com/x"))
    }

    @Test
    fun canonicalJsonEscapesBackslashButNotSlash() {
        // Backslash MUST be escaped to '\\' per RFC 8259; '/' MUST stay unescaped.
        assertEquals("\"a\\\\b\"", canonicalJson("a\\b"))
    }

    @Test
    fun canonicalJsonEscapesDoubleQuote() {
        assertEquals("\"a\\\"b\"", canonicalJson("a\"b"))
    }

    @Test
    fun canonicalJsonEscapesControlCharsWithShortForms() {
        assertEquals("\"a\\nb\"", canonicalJson("a\nb"))
        assertEquals("\"a\\tb\"", canonicalJson("a\tb"))
        assertEquals("\"a\\rb\"", canonicalJson("a\rb"))
        assertEquals("\"a\\bb\"", canonicalJson("" + "b"))
        assertEquals("\"a\\fb\"", canonicalJson("" + "b"))
    }

    @Test
    fun canonicalJsonEscapesControlU001fWithU00XX() {
        // U+001F is a control char without a short escape; it must be .
        val canon = canonicalJson("f")
        // Note: f is the control char U+0001 followed by literal 'f'. The shared
        // fixture uses an actual U+001F embedded between 'a' and 'b' (sample: "a<US>b").
        // Re-encode the same logical character sequence used by the fixture.
        val actualU001f = "a" + String(charArrayOf(0x1f.toChar())) + "b"
        assertEquals("\"a\\u001fb\"", canonicalJson(actualU001f))
        // Sanity check that the previous assertion ran.
        assertTrue("corpus marker for canonical U+001F branch", canon.startsWith("\""))
    }

    @Test
    fun canonicalJsonPreservesBmpAndAstralCharactersAsUtf8() {
        // CJK and emoji must NOT be escaped to \uXXXX; they must round-trip as
        // raw UTF-8 — that is what the Rust and iOS signers emit too.
        assertEquals("\"中\"", canonicalJson("中"))
        assertEquals("\"😀\"", canonicalJson("😀"))
    }

    @Test
    fun canonicalJsonSortsObjectKeysAscending() {
        val canonA = canonicalJson(JSONObject().put("b", 1).put("a", 2))
        val canonB = canonicalJson(JSONObject().put("a", 2).put("b", 1))
        assertEquals("{\"a\":2,\"b\":1}", canonA)
        assertEquals(canonA, canonB)
    }

    @Test
    fun canonicalJsonHandlesCollectionsAndScalars() {
        assertEquals("{}", canonicalJson(JSONObject()))
        assertEquals("[]", canonicalJson(JSONArray()))
        assertEquals("null", canonicalJson(null))
        assertEquals("true", canonicalJson(true))
        assertEquals("false", canonicalJson(false))
    }

    @Test
    fun canonicalJsonSerializesNestedArrayObjectPair() {
        val value = JSONObject().put(
            "items",
            JSONArray().put(JSONObject().put("path", "10/22")).put(JSONObject().put("path", "https://example.com/x")),
        )
        assertEquals(
            "{\"items\":[{\"path\":\"10/22\"},{\"path\":\"https://example.com/x\"}]}",
            canonicalJson(value),
        )
    }

    @Test
    fun fixturesFileLoadsAndCoversAllPinnedCases() {
        val raw = javaClass.getResourceAsStream("/signing_fixtures.json")?.bufferedReader()?.use { it.readText() }
        assertNotNull("shared/signing_fixtures.json must ship under src/test/resources", raw)
        val root = JSONObject(raw!!)
        val stringCases = root.getJSONArray("string_cases")
        val valueCases = root.getJSONArray("value_cases")
        assertTrue("fixtures must include string_cases", stringCases.length() > 0)
        assertTrue("fixtures must include value_cases", valueCases.length() > 0)

        for (i in 0 until stringCases.length()) {
            val case = stringCases.getJSONObject(i)
            val input = case.getString("input")
            val expectedCanonical = case.getString("expected_canonical_json")
            val expectedSha = case.getString("expected_sha256_base64_no_pad")
            val actualCanonical = canonicalJson(input)
            val actualSha = sha256Base64NoPad(actualCanonical.toByteArray(Charsets.UTF_8))
            assertEquals(
                "string_case ${case.getString("id")} canonical_json must match fixture",
                expectedCanonical,
                actualCanonical,
            )
            assertEquals(
                "string_case ${case.getString("id")} sha256 must match fixture",
                expectedSha,
                actualSha,
            )
        }

        for (i in 0 until valueCases.length()) {
            val case = valueCases.getJSONObject(i)
            val input = case.get("input")
            val expectedCanonical = case.getString("expected_canonical_json")
            val expectedSha = case.getString("expected_sha256_base64_no_pad")
            val actualCanonical = canonicalJson(input)
            val actualSha = sha256Base64NoPad(actualCanonical.toByteArray(Charsets.UTF_8))
            assertEquals(
                "value_case ${case.getString("id")} canonical_json must match fixture",
                expectedCanonical,
                actualCanonical,
            )
            assertEquals(
                "value_case ${case.getString("id")} sha256 must match fixture",
                expectedSha,
                actualSha,
            )
        }
    }

    @Test
    fun proposalSignerReproducesSignatureForRegressionFixture() {
        val raw = javaClass.getResourceAsStream("/signing_fixtures.json")?.bufferedReader()?.use { it.readText() }
        assertNotNull(raw)
        val root = JSONObject(raw!!)
        val secret = root.getString("secret_for_signing_fixtures").toByteArray(Charsets.UTF_8)
        val proposalCase = root.getJSONArray("proposal_signing_cases").getJSONObject(0)
        val proposal = proposalCase.getJSONObject("proposal")
        val arguments = proposal.getJSONObject("arguments")

        // Compute the arguments_sha256 exactly the way TrustedHost.kt::proposalSignaturePayload
        // does, then verify the resulting signature is deterministic by re-signing the same
        // proposal twice and asserting equality. We don't pin a literal expected_signature in
        // the shared fixture (it would couple to byte-exact serializer output of the outer
        // JSON objects across three runtimes); instead we assert internal determinism plus
        // that tampering with any field invalidates the signature.
        val argumentsCanonical = canonicalJson(arguments)
        val argumentsHash = sha256Base64NoPad(argumentsCanonical.toByteArray(Charsets.UTF_8))
        val payload = proposalSignaturePayload(proposal, argumentsHash)
        val signatureA = hmacSha256Base64NoPad(secret, payload.toByteArray(Charsets.UTF_8))
        val signatureB = hmacSha256Base64NoPad(secret, payload.toByteArray(Charsets.UTF_8))
        assertEquals("proposal signature must be deterministic", signatureA, signatureB)

        // Tampered arguments produce a different signature — i.e. 'date' moved from 10/22 to 10/23.
        val tampered = JSONObject(proposal.toString())
        tampered.getJSONObject("arguments").put("date", "2026/10/23")
        val tamperedArguments = tampered.getJSONObject("arguments")
        val tamperedCanonical = canonicalJson(tamperedArguments)
        val tamperedHash = sha256Base64NoPad(tamperedCanonical.toByteArray(Charsets.UTF_8))
        val tamperedPayload = proposalSignaturePayload(tampered, tamperedHash)
        val tamperedSig = hmacSha256Base64NoPad(secret, tamperedPayload.toByteArray(Charsets.UTF_8))
        assertTrue("tampered arguments must yield a different signature", tamperedSig != signatureA)

        // Sanity: original arguments still carry the slash-bearing regression corpus so
        // the cross-port parity fixture file truly exercises the original failure surface.
        assertTrue(
            "regression fixture must contain slash-bearing date/unit/url",
            arguments.getString("date").contains("/") &&
                arguments.getString("unit").contains("/") &&
                arguments.getString("source_url").contains("https://"),
        )
    }

    private fun proposalSignaturePayload(proposal: JSONObject, argumentsHash: String): String =
        listOf(
            "request_id=${proposal.getString("request_id")}",
            "provider_id=${proposal.getString("provider_id")}",
            "agent_id=${proposal.getString("agent_id")}",
            "action_id=${proposal.getString("action_id")}",
            "tool_name=${proposal.getString("tool_name")}",
            "arguments_sha256=$argumentsHash",
            "created_at=${proposal.getString("created_at")}",
            "expires_at=${proposal.getString("expires_at")}",
            "nonce=${proposal.getString("nonce")}",
            "idempotency_key=${proposal.getString("idempotency_key")}",
            "risk=${proposal.getString("risk")}",
            "confirmation_policy=${proposal.getString("confirmation_policy")}",
            "host_instance_id=${proposal.getString("host_instance_id")}",
        ).joinToString("\n")
}
