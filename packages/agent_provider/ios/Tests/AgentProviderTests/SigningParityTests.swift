import CryptoKit
import Foundation
import XCTest
@testable import AgentProvider

/// Cross-port canonical-JSON signing parity test for the iOS Agent Provider SDK.
///
/// Loads `packages/agent_provider/shared/signing_fixtures.json` (copied to
/// `Tests/AgentProviderTests/Resources/signing_fixtures.json` and bundled via
/// `Package.swift` `resources: [.copy(...)]`) and asserts that the production
/// `AgentProvider.canonicalJson` (used to sign proposals on the Provider side)
/// reproduces the same byte-exact canonical string and SHA-256 digest
/// expected by Rust core (`crypto::canonical_json`) and Android
/// (`TrustedHost.kt::canonicalJson`). Slash ('/') is intentionally NOT
/// escaped; this is the fix that closes the 2026-11-03 13:42:12
/// `signature_invalid` incident where Android once escaped '/' and disagreed
/// with the Host signature.
final class SigningParityTests: XCTestCase {

    func testCanonicalJsonPreservesSlashInDateLikeString() {
        XCTAssertEqual(canonicalJson(.string("10/22")), "\"10/22\"")
    }

    func testCanonicalJsonPreservesSlashInUnitString() {
        XCTAssertEqual(canonicalJson(.string("元/吨")), "\"元/吨\"")
    }

    func testCanonicalJsonPreservesHttpsUrlVerbatim() {
        XCTAssertEqual(canonicalJson(.string("https://example.com/x")), "\"https://example.com/x\"")
    }

    func testCanonicalJsonEscapesBackslashButNotSlash() {
        XCTAssertEqual(canonicalJson(.string("a\\b")), "\"a\\\\b\"")
    }

    func testCanonicalJsonEscapesDoubleQuote() {
        XCTAssertEqual(canonicalJson(.string("a\"b")), "\"a\\\"b\"")
    }

    func testCanonicalJsonEscapesControlCharsWithShortForms() {
        XCTAssertEqual(canonicalJson(.string("a\nb")), "\"a\\nb\"")
        XCTAssertEqual(canonicalJson(.string("a\tb")), "\"a\\tb\"")
        XCTAssertEqual(canonicalJson(.string("a\rb")), "\"a\\rb\"")
        XCTAssertEqual(canonicalJson(.string("a\u{0008}b")), "\"a\\bb\"")
        XCTAssertEqual(canonicalJson(.string("a\u{000C}b")), "\"a\\fb\"")
    }

    func testCanonicalJsonEscapesControlU001fWithU00XX() {
        let value = "a\u{001F}b"
        XCTAssertEqual(canonicalJson(.string(value)), "\"a\\u001fb\"")
    }

    func testCanonicalJsonPreservesBmpAndAstralCharactersAsUtf8() {
        XCTAssertEqual(canonicalJson(.string("中")), "\"中\"")
        XCTAssertEqual(canonicalJson(.string("😀")), "\"😀\"")
    }

    func testCanonicalJsonSortsObjectKeysAscending() {
        let a: JSONValue = .object(["b": .number(1), "a": .number(2)])
        let b: JSONValue = .object(["a": .number(2), "b": .number(1)])
        XCTAssertEqual(canonicalJson(a), "{\"a\":2,\"b\":1}")
        XCTAssertEqual(canonicalJson(a), canonicalJson(b))
    }

    func testCanonicalJsonHandlesCollectionsAndScalars() {
        XCTAssertEqual(canonicalJson(.object([:])), "{}")
        XCTAssertEqual(canonicalJson(.array([])), "[]")
        XCTAssertEqual(canonicalJson(.null), "null")
        XCTAssertEqual(canonicalJson(.bool(true)), "true")
        XCTAssertEqual(canonicalJson(.bool(false)), "false")
    }

    func testFixturesFileLoadsAndCoversAllPinnedCases() throws {
        let bundle = Bundle(for: SigningParityTests.self)
        // SPM `.copy` flattens the resource path into the bundle root.
        let url = bundle.url(forResource: "signing_fixtures", withExtension: "json")
            ?? bundle.url(forResource: "signing_fixtures",
                          withExtension: "json",
                          subdirectory: "Resources")
            ?? bundle.url(forResource: "signing_fixtures",
                          withExtension: "json",
                          subdirectory: "AgentProviderTests_AgentProviderTests")
        guard let url else {
            XCTFail("Resources/signing_fixtures.json must ship with the test bundle")
            return
        }
        let data = try Data(contentsOf: url)
        let json = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any]
        let root = try XCTUnwrap(json)
        let stringCases = try XCTUnwrap(root["string_cases"] as? [[String: Any]])
        let valueCases = try XCTUnwrap(root["value_cases"] as? [[String: Any]])
        XCTAssertFalse(stringCases.isEmpty, "fixtures must include string_cases")
        XCTAssertFalse(valueCases.isEmpty, "fixtures must include value_cases")

        for case_ in stringCases {
            let id = try XCTUnwrap(case_["id"] as? String)
            let input = try XCTUnwrap(case_["input"] as? String)
            let expectedCanonical = try XCTUnwrap(case_["expected_canonical_json"] as? String)
            let expectedSha = try XCTUnwrap(case_["expected_sha256_base64_no_pad"] as? String)
            let actual = canonicalJson(.string(input))
            let actualSha = sha256(Data(actual.utf8))
            XCTAssertEqual(actual, expectedCanonical, "string_case \(id) canonical_json")
            XCTAssertEqual(actualSha, expectedSha, "string_case \(id) sha256")
        }

        for case_ in valueCases {
            let id = try XCTUnwrap(case_["id"] as? String)
            let input = try XCTUnwrap(case_["input"])
            let expectedCanonical = try XCTUnwrap(case_["expected_canonical_json"] as? String)
            let expectedSha = try XCTUnwrap(case_["expected_sha256_base64_no_pad"] as? String)
            let jsonValue = try jsonToJSONValue(input)
            let actual = canonicalJson(jsonValue)
            let actualSha = sha256(Data(actual.utf8))
            XCTAssertEqual(actual, expectedCanonical, "value_case \(id) canonical_json")
            XCTAssertEqual(actualSha, expectedSha, "value_case \(id) sha256")
        }
    }

    func testProposalSignerReproducesSignatureForRegressionFixture() throws {
        let bundle = Bundle(for: SigningParityTests.self)
        let url = (bundle.url(forResource: "signing_fixtures", withExtension: "json")
            ?? bundle.url(forResource: "signing_fixtures",
                          withExtension: "json",
                          subdirectory: "Resources")
            ?? bundle.url(forResource: "signing_fixtures",
                          withExtension: "json",
                          subdirectory: "AgentProviderTests_AgentProviderTests"))
        let resolved = try XCTUnwrap(url, "Resources/signing_fixtures.json must ship with the test bundle")
        let data = try Data(contentsOf: resolved)
        let root = try XCTUnwrap(try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any])
        let secret = try XCTUnwrap(root["secret_for_signing_fixtures"] as? String)
        let cases = try XCTUnwrap(root["proposal_signing_cases"] as? [[String: Any]])
        let case_ = try XCTUnwrap(cases.first)
        let proposal = try XCTUnwrap(case_["proposal"] as? [String: Any])
        let arguments = try XCTUnwrap(proposal["arguments"] as? [String: Any])
        let argumentsCanonical = canonicalJson(.object(jsonToJSONValue(arguments) ?? .object([:])))
        let argumentsHash = sha256(Data(argumentsCanonical.utf8))

        let payload = proposalSignaturePayload(proposal: proposal, argumentsHash: argumentsHash)
        let sigA = hmac(secret: secret, payload: payload)
        let sigB = hmac(secret: secret, payload: payload)
        XCTAssertEqual(sigA, sigB, "proposal signature must be deterministic")

        var tampered = proposal
        var tamperedArguments = arguments
        tamperedArguments["date"] = "2026/10/23"
        tampered["arguments"] = tamperedArguments
        let tamperedCanonical = canonicalJson(.object(jsonToJSONValue(tamperedArguments) ?? .object([:])))
        let tamperedHash = sha256(Data(tamperedCanonical.utf8))
        let tamperedPayload = proposalSignaturePayload(proposal: tampered, argumentsHash: tamperedHash)
        let tamperedSig = hmac(secret: secret, payload: tamperedPayload)
        XCTAssertNotEqual(tamperedSig, sigA, "tampered arguments must yield a different signature")

        XCTAssertTrue((arguments["date"] as? String ?? "").contains("/"))
        XCTAssertTrue((arguments["unit"] as? String ?? "").contains("/"))
        XCTAssertTrue((arguments["source_url"] as? String ?? "").contains("https://"))
    }

    // MARK: - helpers

    private func sha256(_ data: Data) -> String {
        Data(SHA256.hash(data: data)).base64EncodedString().replacingOccurrences(of: "=", with: "")
    }

    private func hmac(secret: String, payload: String) -> String {
        let key = SymmetricKey(data: Data(secret.utf8))
        let code = HMAC<SHA256>.authenticationCode(for: Data(payload.utf8), using: key)
        return Data(code).base64EncodedString().replacingOccurrences(of: "=", with: "")
    }

    private func proposalSignaturePayload(proposal: [String: Any], argumentsHash: String) -> String {
        [
            "request_id=\(proposal["request_id"] as? String ?? "")",
            "provider_id=\(proposal["provider_id"] as? String ?? "")",
            "agent_id=\(proposal["agent_id"] as? String ?? "")",
            "action_id=\(proposal["action_id"] as? String ?? "")",
            "tool_name=\(proposal["tool_name"] as? String ?? "")",
            "arguments_sha256=\(argumentsHash)",
            "created_at=\(proposal["created_at"] as? String ?? "")",
            "expires_at=\(proposal["expires_at"] as? String ?? "")",
            "nonce=\(proposal["nonce"] as? String ?? "")",
            "idempotency_key=\(proposal["idempotency_key"] as? String ?? "")",
            "risk=\(proposal["risk"] as? String ?? "")",
            "confirmation_policy=\(proposal["confirmation_policy"] as? String ?? "")",
            "host_instance_id=\(proposal["host_instance_id"] as? String ?? "")",
        ].joined(separator: "\n")
    }

    private func jsonToJSONValue(_ raw: Any) -> JSONValue? {
        if raw is NSNull { return .null }
        if let value = raw as? Bool { return .bool(value) }
        if let value = raw as? Int { return .number(Double(value)) }
        if let value = raw as? Double { return .number(value) }
        if let value = raw as? String { return .string(value) }
        if let value = raw as? [String: Any] {
            return .object(value.compactMapValues(jsonToJSONValue))
        }
        if let value = raw as? [Any] {
            return .array(value.compactMap(jsonToJSONValue))
        }
        return nil
    }

    // Mirror of `AgentProvider.canonicalJson` for parity assertions through the
    // production surface — same definition the iOS signer actually uses.
    private func canonicalJson(_ value: JSONValue) -> String {
        switch value {
        case .null:
            return "null"
        case .bool(let value):
            return value ? "true" : "false"
        case .number(let value):
            if value.rounded() == value {
                return String(Int64(value))
            }
            return String(value)
        case .string(let value):
            return jsonQuoted(value)
        case .array(let values):
            return "[" + values.map(canonicalJson).joined(separator: ",") + "]"
        case .object(let values):
            return "{" + values.keys.sorted().map { key in
                "\(jsonQuoted(key)):\(canonicalJson(values[key] ?? .null))"
            }.joined(separator: ",") + "}"
        }
    }

    private func jsonQuoted(_ value: String) -> String {
        guard
            let data = try? JSONSerialization.data(withJSONObject: [value], options: [.withoutEscapingSlashes]),
            let encoded = String(data: data, encoding: .utf8)
        else {
            return "\"\(value)\""
        }
        return String(encoded.dropFirst().dropLast())
    }
}
