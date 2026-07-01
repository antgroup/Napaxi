import CryptoKit
import Foundation
import XCTest
@testable import AgentProvider

final class AgentProviderTests: XCTestCase {
    func testPackageJsonRoundTrip() throws {
        let package = samplePackage()
        let json = try AgentProvider.packageToJson(package)
        let parsed = try AgentProvider.packageFromJson(json)

        XCTAssertEqual(parsed.providerId, "wallet.provider")
        XCTAssertEqual(parsed.actions.first?.toolName, "app_action_wallet_payment_pay")
    }

    func testInstallRequestAndResultUrlRoundTrip() throws {
        let request = sampleInstallRequest()
        let requestJson = try encodeJson(request)
        let installURL = URL(string: "https://wallet.example.com/agent/install?install_request=\(requestJson.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)!)")!

        let parsed = AgentProvider.parseInstallRequest(url: installURL)
        XCTAssertEqual(parsed?.requestId, "install-1")
        XCTAssertEqual(parsed?.hostInstanceId, "host-instance-1")

        let callback = try AgentProvider.buildInstallCallbackURL(
            packageDef: samplePackage(),
            request: request
        )
        let resultJson = queryValue("install_result", in: callback)
        let result = try decodeJson(AgentInstallResult.self, resultJson ?? "")

        XCTAssertEqual(result.status, "succeeded")
        XCTAssertEqual(result.requestId, request.requestId)
        XCTAssertEqual(result.nonce, request.nonce)
        XCTAssertEqual(result.package?.agentId, "wallet.agent")
    }

    func testProposalParseAndBasicValidation() throws {
        let proposal = sampleProposal(signature: nil)
        let proposalJson = try encodeJson(proposal)
        let actionURL = URL(string: "https://wallet.example.com/agent/action?proposal=\(proposalJson.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)!)")!

        let parsed = AgentProvider.parseProposal(url: actionURL)
        let validation = AgentProvider.validateProposal(
            proposal: parsed!,
            packageDef: samplePackage(),
            now: date("2026-05-27T00:00:00Z")
        )

        XCTAssertTrue(validation.isValid)
    }

    func testTrustedValidationAcceptsSignedProposalAndRejectsReplay() {
        let defaults = UserDefaults(suiteName: "AgentProviderTests.\(UUID().uuidString)")!
        let store = TrustedHostStore(defaults: defaults, namespace: "test")
        store.saveBinding(sampleBinding())
        let proposal = signedSampleProposal()

        let trusted = AgentProvider.validateTrustedProposal(
            proposal: proposal,
            packageDef: samplePackage(),
            store: store,
            now: date("2026-05-27T00:00:00Z")
        )
        XCTAssertTrue(trusted.isTrusted)

        AgentProvider.markProposalConsumed(store: store, proposal: proposal)
        let replayed = AgentProvider.validateTrustedProposal(
            proposal: proposal,
            packageDef: samplePackage(),
            store: store,
            now: date("2026-05-27T00:00:00Z")
        )
        XCTAssertEqual(replayed.status, TrustedProposalStatus.replayed)
    }

    func testTrustedValidationRejectsMissingAndInvalidSignature() {
        let defaults = UserDefaults(suiteName: "AgentProviderTests.\(UUID().uuidString)")!
        let store = TrustedHostStore(defaults: defaults, namespace: "test")
        store.saveBinding(sampleBinding())

        let missing = AgentProvider.validateTrustedProposal(
            proposal: sampleProposal(signature: nil),
            packageDef: samplePackage(),
            store: store,
            now: date("2026-05-27T00:00:00Z")
        )
        XCTAssertEqual(missing.status, TrustedProposalStatus.untrusted)

        var invalid = sampleProposal(signature: "bad")
        invalid.signatureAlgorithm = "hmac-sha256-v1"
        let invalidResult = AgentProvider.validateTrustedProposal(
            proposal: invalid,
            packageDef: samplePackage(),
            store: store,
            now: date("2026-05-27T00:00:00Z")
        )
        XCTAssertEqual(invalidResult.status, TrustedProposalStatus.signatureInvalid)
    }

    func testExpiredProposalRejected() {
        let expired = AgentProvider.validateProposal(
            proposal: sampleProposal(signature: nil),
            packageDef: samplePackage(),
            now: date("2026-05-28T00:00:00Z")
        )
        XCTAssertEqual(expired.code, "expired")
    }

    func testTriggerUrlRoundTripAndSigning() throws {
        let trigger = AgentProvider.signTriggerRequest(
            sampleTrigger(),
            binding: sampleBinding()
        )
        let url = try AgentProvider.buildHostTriggerURL(
            request: trigger,
            hostURL: URL(string: "agent-host://agent-provider/trigger")!
        )
        let triggerJson = queryValue("trigger_request", in: url) ?? ""
        let parsed = try decodeJson(AgentTriggerRequest.self, triggerJson)

        XCTAssertEqual(parsed.requestId, "trigger-1")
        XCTAssertEqual(parsed.agentId, "wallet.agent")
        XCTAssertEqual(parsed.hostInstanceId, "host-instance-1")
        XCTAssertEqual(parsed.signatureAlgorithm, "hmac-sha256-v1")
        XCTAssertFalse(parsed.signature?.isEmpty ?? true)
    }
}

private func samplePackage() -> AgentPackage {
    AgentPackage(
        providerId: "wallet.provider",
        agentId: "wallet.agent",
        displayName: "Wallet Agent",
        actions: [
            AgentAction(
                actionId: "wallet.payment.pay",
                toolName: "app_action_wallet_payment_pay",
                description: "Create a virtual payment."
            ),
        ]
    )
}

private func sampleInstallRequest() -> AgentInstallRequest {
    AgentInstallRequest(
        requestId: "install-1",
        nonce: "nonce-1",
        createdAt: "2026-05-27T00:00:00Z",
        expiresAt: "2026-05-27T00:10:00Z",
        hostInstanceId: "host-instance-1",
        hostSharedSecret: "secret-1",
        hostBundleId: "host.app",
        hostTeamId: "HOST123456",
        hostCallbackScheme: "agent-host",
        callbackUrl: "agent-host://agent-provider/install-callback"
    )
}

private func sampleBinding() -> TrustedHostBinding {
    TrustedHostBinding(
        hostBundleId: "host.app",
        hostTeamId: "HOST123456",
        hostCallbackScheme: "agent-host",
        hostInstanceId: "host-instance-1",
        hostSharedSecret: "secret-1",
        installedAt: "2026-05-27T00:00:00Z"
    )
}

private func sampleProposal(signature: String?) -> ActionProposal {
    ActionProposal(
        requestId: "request-1",
        providerId: "wallet.provider",
        agentId: "wallet.agent",
        actionId: "wallet.payment.pay",
        toolName: "app_action_wallet_payment_pay",
        arguments: ["amount": .number(12.5), "merchant": .string("Coffee")],
        createdAt: "2026-05-27T00:00:00Z",
        expiresAt: "2026-05-27T00:10:00Z",
        nonce: "nonce-1",
        idempotencyKey: "request-1",
        risk: "high",
        confirmationPolicy: "provider_required",
        hostInstanceId: "host-instance-1",
        signatureAlgorithm: signature == nil ? "" : "hmac-sha256-v1",
        signature: signature
    )
}

private func sampleTrigger() -> AgentTriggerRequest {
    AgentTriggerRequest(
        requestId: "trigger-1",
        providerId: "wallet.provider",
        agentId: "wallet.agent",
        message: "Review today spending.",
        source: "virtual_wallet",
        eventType: "review_spending_requested",
        payload: ["view": .string("today_spending")],
        createdAt: "2026-05-27T00:00:00Z",
        expiresAt: "2026-05-27T00:10:00Z",
        nonce: "nonce-trigger",
        idempotencyKey: "trigger-1"
    )
}

private func signedSampleProposal() -> ActionProposal {
    var proposal = sampleProposal(signature: nil)
    proposal.signatureAlgorithm = "hmac-sha256-v1"
    proposal.signature = sign(proposal, secret: "secret-1")
    return proposal
}

private func sign(_ proposal: ActionProposal, secret: String) -> String {
    let argumentsHash = Data(SHA256.hash(data: Data(canonicalJson(.object(proposal.arguments)).utf8)))
        .base64EncodedString()
        .replacingOccurrences(of: "=", with: "")
    let payload = [
        "request_id=\(proposal.requestId)",
        "provider_id=\(proposal.providerId)",
        "agent_id=\(proposal.agentId)",
        "action_id=\(proposal.actionId)",
        "tool_name=\(proposal.toolName)",
        "arguments_sha256=\(argumentsHash)",
        "created_at=\(proposal.createdAt)",
        "expires_at=\(proposal.expiresAt)",
        "nonce=\(proposal.nonce)",
        "idempotency_key=\(proposal.idempotencyKey)",
        "risk=\(proposal.risk)",
        "confirmation_policy=\(proposal.confirmationPolicy)",
        "host_instance_id=\(proposal.hostInstanceId)",
    ].joined(separator: "\n")
    let key = SymmetricKey(data: Data(secret.utf8))
    let code = HMAC<SHA256>.authenticationCode(for: Data(payload.utf8), using: key)
    return Data(code).base64EncodedString().replacingOccurrences(of: "=", with: "")
}

private func canonicalJson(_ value: JSONValue) -> String {
    switch value {
    case .null:
        return "null"
    case .bool(let value):
        return value ? "true" : "false"
    case .number(let value):
        return String(value)
    case .string(let value):
        let data = try! JSONSerialization.data(withJSONObject: [value], options: [])
        return String(data: data, encoding: .utf8)!.dropFirst().dropLast().description
    case .array(let values):
        return "[" + values.map(canonicalJson).joined(separator: ",") + "]"
    case .object(let values):
        return "{" + values.keys.sorted().map { key in
            "\(canonicalJson(.string(key))):\(canonicalJson(values[key] ?? .null))"
        }.joined(separator: ",") + "}"
    }
}

private func queryValue(_ name: String, in url: URL) -> String? {
    URLComponents(url: url, resolvingAgainstBaseURL: false)?
        .queryItems?
        .first(where: { $0.name == name })?
        .value
}

private func date(_ value: String) -> Date {
    ISO8601DateFormatter().date(from: value)!
}
