import XCTest
@testable import Napaxi

final class A2APairingTests: XCTestCase {
    func testPairingHelpersDeriveSymmetricNonPublicSecret() {
        XCTAssertEqual(
            NapaxiA2APairing.pairingKey(peerId: "phone-a", publicKey: "public-a"),
            "phone-a|public-a"
        )
        XCTAssertEqual(
            NapaxiA2APairing.normalizePairingSecret(" a1b2-c3d4 ef00 "),
            "A1B2C3D4EF00"
        )
        XCTAssertEqual(
            NapaxiA2APairing.formatPairingSecret("a1b2c3d4ef00"),
            "A1B2 C3D4 EF00"
        )
        XCTAssertEqual(
            NapaxiA2APairing.pairingCodeFromIdentity(peerId: "phone-a", publicKey: "public-a").count,
            9
        )

        let aToB = NapaxiA2APairing.deriveLocalSharedSecret(
            localPeerId: "phone-a",
            localPublicKey: "public-a",
            localPairingSecret: "AAAA BBBB CCCC DDDD",
            remotePeerId: "phone-b",
            remotePublicKey: "public-b",
            remotePairingSecret: "1111-2222-3333-4444"
        )
        let bToA = NapaxiA2APairing.deriveLocalSharedSecret(
            localPeerId: "phone-b",
            localPublicKey: "public-b",
            localPairingSecret: "1111-2222-3333-4444",
            remotePeerId: "phone-a",
            remotePublicKey: "public-a",
            remotePairingSecret: "AAAA BBBB CCCC DDDD"
        )
        let withoutRemoteSecret = NapaxiA2APairing.deriveLocalSharedSecret(
            localPeerId: "phone-a",
            localPublicKey: "public-a",
            localPairingSecret: "AAAA BBBB CCCC DDDD",
            remotePeerId: "phone-b",
            remotePublicKey: "public-b",
            remotePairingSecret: ""
        )

        XCTAssertEqual(
            aToB,
            "tofu-hmac-v2:2F4C67A6913CE598670024D0F63C64C26DE3D8B6CDED86ED376EB0A9F02979DF"
        )
        XCTAssertEqual(aToB, bToA)
        XCTAssertTrue(aToB.hasPrefix("tofu-hmac-v2:"))
        XCTAssertEqual(aToB.count, "tofu-hmac-v2:".count + 64)
        XCTAssertNotEqual(aToB, withoutRemoteSecret)
        XCTAssertFalse(aToB.contains("public-a"))
        XCTAssertFalse(aToB.contains("public-b"))
        XCTAssertFalse(aToB.contains("AAAA"))
        XCTAssertFalse(aToB.contains("1111"))
    }

    func testFlutterAliasTargetsPairingHelper() {
        XCTAssertEqual(
            A2APairing.pairingKey(peerId: "phone-a", publicKey: ""),
            "phone-a|phone-a"
        )
    }

    // Adapter-parity guard: the iOS invite codec must agree with the shared
    // wire contract. The values below mirror the cross-adapter fixture at
    // packages/api_contract/fixtures/a2a/local_pairing_invite.json. If the
    // fixture changes, this test must change with it (and so must the Flutter
    // and Android codecs).
    func testInviteCodecMatchesSharedContract() {
        let invite = NapaxiA2AInvite(
            peerId: "peer-fixture-001",
            agentId: "agent.fixture",
            displayName: "Fixture Phone",
            publicKey: "pubkey-fixture-abc123",
            pairingSecret: "secret-fixture-xyz789",
            endpoint: "lan://192.168.1.20:7100",
            transport: "lan_tcp_jsonl",
            createdAt: "2026-06-08T00:00:00Z"
        )

        let payload = invite.toQrPayload()
        XCTAssertTrue(payload.hasPrefix(NapaxiA2AInvite.qrPrefix))
        XCTAssertEqual(NapaxiA2AInvite.qrPrefix, "napaxi-a2a-invite:")

        guard let decoded = NapaxiA2AInvite.tryDecodePayload(payload) else {
            return XCTFail("shared-shape invite must decode")
        }
        XCTAssertEqual(decoded.version, 1)
        XCTAssertEqual(decoded.peerId, "peer-fixture-001")
        XCTAssertEqual(decoded.publicKey, "pubkey-fixture-abc123")
        XCTAssertEqual(decoded.pairingSecret, "secret-fixture-xyz789")
        XCTAssertEqual(decoded.endpoint, "lan://192.168.1.20:7100")
        XCTAssertEqual(decoded.transport, "lan_tcp_jsonl")

        // A /a2a join line and a bare code both decode.
        XCTAssertEqual(
            NapaxiA2AInvite.tryDecodePayload("/a2a join \(invite.toCode())")?.peerId,
            "peer-fixture-001"
        )
        XCTAssertEqual(NapaxiA2AInvite.tryDecodePayload(invite.toCode())?.peerId, "peer-fixture-001")
    }

    func testInviteCodecRejectsMalformedAndIncompleteInvites() {
        XCTAssertNil(NapaxiA2AInvite.tryDecodeCode(""))
        XCTAssertNil(NapaxiA2AInvite.tryDecodeCode("!!!not base64!!!"))
        XCTAssertNil(NapaxiA2AInvite.tryDecodePayload("   "))

        // Each required identity field, when missing, must be rejected.
        for missing in ["peerId", "publicKey", "pairingSecret"] {
            var map: [String: Any] = [
                "v": 1,
                "peerId": "p",
                "publicKey": "k",
                "pairingSecret": "s",
            ]
            map.removeValue(forKey: missing)
            let data = try! JSONSerialization.data(withJSONObject: map)
            let code = data.base64EncodedString()
                .replacingOccurrences(of: "+", with: "-")
                .replacingOccurrences(of: "/", with: "_")
                .replacingOccurrences(of: "=", with: "")
            XCTAssertNil(
                NapaxiA2AInvite.tryDecodeCode(code),
                "invite missing \(missing) must be rejected"
            )
        }
    }
}
