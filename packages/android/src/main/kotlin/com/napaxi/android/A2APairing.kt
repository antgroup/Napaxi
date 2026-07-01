package com.napaxi.android

import java.security.MessageDigest
import java.security.SecureRandom
import java.util.Base64
import java.util.Locale
import org.json.JSONObject

public object A2APairing {
    private val random = SecureRandom()

    public fun generateLocalPairingSecret(byteLength: Int = 16): String {
        val length = byteLength.coerceIn(16, 64)
        val bytes = ByteArray(length)
        random.nextBytes(bytes)
        return bytes.toHex()
    }

    public fun normalizePairingSecret(value: String): String =
        value.filter { it in '0'..'9' || it in 'A'..'F' || it in 'a'..'f' }
            .uppercase(Locale.US)

    public fun formatPairingSecret(value: String): String {
        val normalized = normalizePairingSecret(value)
        if (normalized.isEmpty()) return ""
        return normalized.chunked(4).joinToString(" ")
    }

    public fun pairingCodeFromIdentity(peerId: String, publicKey: String): String {
        val hex = sha256Hex(identityMaterial(peerId, publicKey))
        return "${hex.substring(0, 4)} ${hex.substring(4, 8)}"
    }

    public fun pairingKey(peerId: String, publicKey: String): String =
        identityMaterial(peerId, publicKey)

    public fun deriveLocalSharedSecret(
        localPeerId: String,
        localPublicKey: String,
        localPairingSecret: String,
        remotePeerId: String,
        remotePublicKey: String,
        remotePairingSecret: String,
    ): String {
        val identities = listOf(
            identityMaterial(localPeerId, localPublicKey),
            identityMaterial(remotePeerId, remotePublicKey),
        ).sorted()
        val secrets = listOf(
            normalizePairingSecret(localPairingSecret),
            normalizePairingSecret(remotePairingSecret),
        ).sorted()
        return "tofu-hmac-v2:${sha256Hex((identities + secrets).joinToString("|"))}"
    }

    private fun identityMaterial(peerId: String, publicKey: String): String {
        val material = publicKey.trim().ifEmpty { peerId }
        return "$peerId|$material"
    }

    private fun sha256Hex(value: String): String =
        MessageDigest.getInstance("SHA-256")
            .digest(value.toByteArray(Charsets.UTF_8))
            .toHex()

    private fun ByteArray.toHex(): String =
        joinToString(separator = "") { byte -> "%02X".format(byte) }
}

/**
 * Decoded local A2A pairing invite — the Android binding of the shared wire
 * contract pinned in Rust core (`napaxi_core::api::a2a::local_pairing_contract`)
 * and mirrored by the Flutter `A2AInvite` and iOS `NapaxiA2AInvite` codecs.
 * Field names, the QR prefix, and the required identity fields must match the
 * cross-adapter fixture at
 * `packages/api_contract/fixtures/a2a/local_pairing_invite.json`.
 */
public data class A2AInvite(
    val peerId: String,
    val publicKey: String,
    val pairingSecret: String,
    val agentId: String = "",
    val displayName: String = "",
    val endpoint: String = "",
    val transport: String = "",
    val createdAt: String = "",
    val version: Int = CURRENT_VERSION,
) {
    public fun toJsonObject(): JSONObject = JSONObject().apply {
        put("v", version)
        put("peerId", peerId)
        put("agentId", agentId)
        put("displayName", displayName)
        put("publicKey", publicKey)
        put("pairingSecret", pairingSecret)
        put("endpoint", endpoint)
        put("transport", transport)
        put("createdAt", createdAt)
    }

    /** The bare invite code (base64url, no padding). */
    public fun toCode(): String =
        Base64.getUrlEncoder().withoutPadding()
            .encodeToString(toJsonObject().toString().toByteArray(Charsets.UTF_8))

    /** The full QR / deep-link payload (with the prefix). */
    public fun toQrPayload(): String = "$QR_PREFIX${toCode()}"

    public companion object {
        public const val QR_PREFIX: String = "napaxi-a2a-invite:"
        public const val CURRENT_VERSION: Int = 1

        private val JOIN_REGEX =
            Regex("""(?:^|\s)/a2a\s+join\s+([A-Za-z0-9_-]+)""", RegexOption.IGNORE_CASE)

        /**
         * Decode a bare invite code (base64url JSON). Returns null on malformed
         * input or when a required identity field is missing — never throws.
         */
        public fun tryDecodeCode(code: String): A2AInvite? {
            val normalized = code.trim()
            if (normalized.isEmpty()) return null
            val obj = try {
                val bytes = Base64.getUrlDecoder().decode(addPadding(normalized))
                JSONObject(String(bytes, Charsets.UTF_8))
            } catch (_: Exception) {
                return null
            }
            val peerId = obj.optString("peerId").trim()
            val pairingSecret = obj.optString("pairingSecret").trim()
            val publicKey = obj.optString("publicKey").trim()
            // An invite without a peer id, public key, or pairing secret cannot
            // drive a handshake — reject rather than return a half-built record.
            if (peerId.isEmpty() || pairingSecret.isEmpty() || publicKey.isEmpty()) {
                return null
            }
            return A2AInvite(
                peerId = peerId,
                publicKey = publicKey,
                pairingSecret = pairingSecret,
                agentId = obj.optString("agentId"),
                displayName = obj.optString("displayName"),
                endpoint = obj.optString("endpoint"),
                transport = obj.optString("transport"),
                createdAt = obj.optString("createdAt"),
                version = if (obj.has("v")) obj.optInt("v", CURRENT_VERSION) else CURRENT_VERSION,
            )
        }

        /**
         * Decode a full QR payload (with prefix), a `/a2a join <code>` line, or a
         * bare code. Returns null when nothing decodes — never throws.
         */
        public fun tryDecodePayload(rawValue: String): A2AInvite? {
            val value = rawValue.trim()
            if (value.isEmpty()) return null
            if (value.startsWith(QR_PREFIX)) {
                return tryDecodeCode(value.substring(QR_PREFIX.length))
            }
            JOIN_REGEX.find(value)?.groupValues?.getOrNull(1)?.let { return tryDecodeCode(it) }
            return tryDecodeCode(value)
        }

        private fun addPadding(value: String): String {
            val remainder = value.length % 4
            return if (remainder == 0) value else value + "=".repeat(4 - remainder)
        }
    }
}
