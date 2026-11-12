import CryptoKit
import Foundation

private let signatureAlgorithmHmacSha256V1 = "hmac-sha256-v1"

public enum AgentProvider {
    public static func packageToJson(_ packageDef: AgentPackage) throws -> String {
        try encodeJson(packageDef)
    }

    public static func packageFromJson(_ json: String) throws -> AgentPackage {
        try decodeJson(AgentPackage.self, json)
    }

    public static func parseInstallRequest(url: URL) -> AgentInstallRequest? {
        guard let json = queryValue("install_request", in: url) else { return nil }
        return try? decodeJson(AgentInstallRequest.self, json)
    }

    public static func buildInstallCallbackURL(
        packageDef: AgentPackage,
        request: AgentInstallRequest,
        callbackURL: URL? = nil
    ) throws -> URL {
        let result = AgentInstallResult(
            status: "succeeded",
            requestId: request.requestId,
            nonce: request.nonce,
            package: packageDef,
            completedAt: isoNow()
        )
        return try appendJsonQueryItem(
            name: "install_result",
            value: encodeJson(result),
            to: callbackURL ?? URL(string: request.callbackUrl)!
        )
    }

    public static func buildInstallFailureCallbackURL(
        request: AgentInstallRequest,
        code: String,
        message: String,
        callbackURL: URL? = nil
    ) throws -> URL {
        let result = AgentInstallResult(
            status: "failed",
            requestId: request.requestId,
            nonce: request.nonce,
            package: nil,
            error: ["code": .string(code), "message": .string(message)],
            completedAt: isoNow()
        )
        return try appendJsonQueryItem(
            name: "install_result",
            value: encodeJson(result),
            to: callbackURL ?? URL(string: request.callbackUrl)!
        )
    }

    public static func parseProposal(url: URL) -> ActionProposal? {
        guard let json = queryValue("proposal", in: url) else { return nil }
        return try? decodeJson(ActionProposal.self, json)
    }

    public static func buildHostTriggerURL(
        request: AgentTriggerRequest,
        hostURL: URL
    ) throws -> URL {
        try appendJsonQueryItem(
            name: "trigger_request",
            value: encodeJson(request),
            to: hostURL
        )
    }

    public static func signTriggerRequest(
        _ request: AgentTriggerRequest,
        binding: TrustedHostBinding
    ) -> AgentTriggerRequest {
        var signed = request
        signed.hostInstanceId = binding.hostInstanceId
        signed.signatureAlgorithm = signatureAlgorithmHmacSha256V1
        signed.signature = nil
        signed.signature = hmacSha256Base64NoPad(
            secret: Data(binding.hostSharedSecret.utf8),
            payload: Data(triggerSignaturePayload(signed).utf8)
        )
        return signed
    }

    public static func validateProposal(
        proposal: ActionProposal,
        packageDef: AgentPackage,
        now: Date = Date()
    ) -> ProposalValidationResult {
        guard proposal.providerId == packageDef.providerId else {
            return .failure("provider_mismatch", "Proposal provider_id does not match this package.")
        }
        guard proposal.agentId == packageDef.agentId else {
            return .failure("agent_mismatch", "Proposal agent_id does not match this package.")
        }
        guard let action = packageDef.actions.first(where: { $0.actionId == proposal.actionId }) else {
            return .failure("action_mismatch", "Proposal action_id is not declared by this package.")
        }
        if !proposal.toolName.isEmpty && proposal.toolName != action.toolName {
            return .failure("tool_mismatch", "Proposal tool_name does not match this action.")
        }
        guard !proposal.nonce.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return .failure("missing_nonce", "Proposal nonce is required.")
        }
        guard !proposal.idempotencyKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return .failure("missing_idempotency_key", "Proposal idempotency_key is required.")
        }
        guard let expiry = parseIsoDate(proposal.expiresAt), expiry > now else {
            return .failure("expired", "Proposal is expired.")
        }
        return .valid()
    }

    public static func validateTrustedProposal(
        proposal: ActionProposal,
        packageDef: AgentPackage,
        store: TrustedHostStore,
        now: Date = Date()
    ) -> TrustedProposalValidationResult {
        let basic = validateProposal(proposal: proposal, packageDef: packageDef, now: now)
        guard basic.isValid else {
            let status = basic.code == "expired"
                ? TrustedProposalStatus.expired
                : TrustedProposalStatus.untrusted
            return .failure(
                status: status,
                code: basic.code ?? "invalid_proposal",
                message: basic.message ?? "Invalid proposal."
            )
        }
        if store.isProposalConsumed(proposal.requestId) {
            return .failure(
                status: TrustedProposalStatus.replayed,
                code: "replayed",
                message: "Proposal request has already been consumed."
            )
        }
        guard
            !proposal.hostInstanceId.isEmpty,
            proposal.signatureAlgorithm == signatureAlgorithmHmacSha256V1,
            let signature = proposal.signature,
            !signature.isEmpty
        else {
            return .failure(
                status: TrustedProposalStatus.untrusted,
                code: "missing_trust_fields",
                message: "Proposal is missing trusted host signature fields."
            )
        }
        guard let binding = store.loadBinding(hostInstanceId: proposal.hostInstanceId) else {
            return .failure(
                status: TrustedProposalStatus.untrusted,
                code: "host_not_bound",
                message: "No trusted host binding exists for this proposal."
            )
        }
        let expected = hmacSha256Base64NoPad(
            secret: Data(binding.hostSharedSecret.utf8),
            payload: Data(proposalSignaturePayload(proposal).utf8)
        )
        guard expected == signature else {
            return .failure(
                status: TrustedProposalStatus.signatureInvalid,
                code: "signature_invalid",
                message: "Proposal signature is invalid."
            )
        }
        return .trusted()
    }

    public static func markProposalConsumed(
        store: TrustedHostStore,
        proposal: ActionProposal
    ) {
        store.markProposalConsumed(requestId: proposal.requestId)
    }

    public static func buildResultCallbackURL(
        result: ActionResult,
        callbackURL: URL
    ) throws -> URL {
        try appendJsonQueryItem(
            name: "result",
            value: encodeJson(result),
            to: callbackURL
        )
    }
}

public final class TrustedHostStore {
    private let defaults: UserDefaults
    private let namespace: String

    public init(defaults: UserDefaults = .standard, namespace: String = "agent_provider_trust") {
        self.defaults = defaults
        self.namespace = namespace
    }

    @discardableResult
    public func saveBinding(_ binding: TrustedHostBinding) -> Bool {
        guard let json = try? encodeJson(binding) else { return false }
        defaults.set(json, forKey: key("binding_\(binding.hostInstanceId)"))
        defaults.set(binding.hostInstanceId, forKey: key("latest_host_instance_id"))
        return loadBinding(hostInstanceId: binding.hostInstanceId) == binding
    }

    public func loadBinding(hostInstanceId: String) -> TrustedHostBinding? {
        guard !hostInstanceId.isEmpty else { return nil }
        guard let json = defaults.string(forKey: key("binding_\(hostInstanceId)")) else {
            return nil
        }
        return try? decodeJson(TrustedHostBinding.self, json)
    }

    public func loadLatestBinding() -> TrustedHostBinding? {
        guard let hostInstanceId = defaults.string(forKey: key("latest_host_instance_id")) else {
            return nil
        }
        return loadBinding(hostInstanceId: hostInstanceId)
    }

    public func isProposalConsumed(_ requestId: String) -> Bool {
        consumedRequestIds().contains(requestId)
    }

    public func markProposalConsumed(requestId: String) {
        guard !requestId.isEmpty else { return }
        var ids = consumedRequestIds()
        ids.insert(requestId)
        defaults.set(Array(ids), forKey: key("consumed_request_ids"))
    }

    private func consumedRequestIds() -> Set<String> {
        Set(defaults.stringArray(forKey: key("consumed_request_ids")) ?? [])
    }

    private func key(_ value: String) -> String {
        "\(namespace).\(value)"
    }
}

func encodeJson<T: Encodable>(_ value: T) throws -> String {
    let encoder = JSONEncoder()
    encoder.keyEncodingStrategy = .convertToSnakeCase
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    let data = try encoder.encode(value)
    return String(decoding: data, as: UTF8.self)
}

func decodeJson<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    return try decoder.decode(type, from: Data(json.utf8))
}

private func queryValue(_ name: String, in url: URL) -> String? {
    URLComponents(url: url, resolvingAgainstBaseURL: false)?
        .queryItems?
        .first(where: { $0.name == name })?
        .value
}

private func appendJsonQueryItem(name: String, value: String, to url: URL) throws -> URL {
    guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
        throw AgentProviderError.invalidURL
    }
    var items = components.queryItems ?? []
    items.append(URLQueryItem(name: name, value: value))
    components.queryItems = items
    guard let output = components.url else {
        throw AgentProviderError.invalidURL
    }
    return output
}

private enum AgentProviderError: Error {
    case invalidURL
}

private func parseIsoDate(_ value: String) -> Date? {
    let fractional = ISO8601DateFormatter()
    fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let date = fractional.date(from: value) {
        return date
    }
    return ISO8601DateFormatter().date(from: value)
}

private func isoNow() -> String {
    ISO8601DateFormatter().string(from: Date())
}

private func proposalSignaturePayload(_ proposal: ActionProposal) -> String {
    let argumentsHash = sha256Base64NoPad(Data(canonicalJson(.object(proposal.arguments)).utf8))
    return [
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
}

private func triggerSignaturePayload(_ request: AgentTriggerRequest) -> String {
    let payloadHash = sha256Base64NoPad(Data(canonicalJson(.object(request.payload)).utf8))
    return [
        "request_id=\(request.requestId)",
        "provider_id=\(request.providerId)",
        "agent_id=\(request.agentId)",
        "message=\(request.message)",
        "source=\(request.source)",
        "event_type=\(request.eventType)",
        "payload_sha256=\(payloadHash)",
        "created_at=\(request.createdAt)",
        "expires_at=\(request.expiresAt)",
        "nonce=\(request.nonce)",
        "idempotency_key=\(request.idempotencyKey)",
        "host_instance_id=\(request.hostInstanceId)",
    ].joined(separator: "\n")
}

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

/// String escaping per `canonical-json-minv1` (mirrors AOSP
/// `org.json.JSONObject.quote` byte-for-byte). The previous implementation
/// relied on `JSONSerialization`, which neither escapes `/` nor handles
/// the JSON-invisible control code points (`U+0000`-`U+001F`) using the
/// lowercase `\u00xx` form the shared `canonical_fixtures.json` contract
/// pins. Hand-written escape keeps the business string intact — `10/22`,
/// `元/吨`, URLs and Markdown round-trip unchanged — and matches the Rust
/// core (see `crates/core/src/crypto/mod.rs`) and the Android provider
/// (`org.json.JSONObject.quote`) byte-for-byte.
///
/// `encodeJson` (separate function) builds the wire request body and is
/// intentionally *not* used for signing — `JSONEncoder.withoutEscapingSlashes`
/// is fine for transport because the request body does not participate in
/// the HMAC payload.
private func jsonQuoted(_ value: String) -> String {
    var out = "\""
    for scalar in value.unicodeScalars {
        switch scalar.value {
        case 0x22: // "
            out += "\\\""
        case 0x5C: // backslash
            out += "\\\\"
        case 0x2F: // /
            out += "\\/"
        case 0x08: // backspace
            out += "\\b"
        case 0x0C: // form feed
            out += "\\f"
        case 0x0A: // line feed
            out += "\\n"
        case 0x0D: // carriage return
            out += "\\r"
        case 0x09: // horizontal tab
            out += "\\t"
        case let code where code < 0x20:
            // Lowercase 4-hex `\u00xx` for the remaining control range.
            // Code points beyond U+007F (DEL, line/par separators, BOM,
            // ZWJ, CJK, …) remain raw UTF-8, matching the fixture contract.
            out += String(format: "\\u%04x", code)
        default:
            out.unicodeScalars.append(scalar)
        }
    }
    out += "\""
    return out
}

private func sha256Base64NoPad(_ data: Data) -> String {
    Data(SHA256.hash(data: data)).base64EncodedString().replacingOccurrences(of: "=", with: "")
}

private func hmacSha256Base64NoPad(secret: Data, payload: Data) -> String {
    let key = SymmetricKey(data: secret)
    let code = HMAC<SHA256>.authenticationCode(for: payload, using: key)
    return Data(code).base64EncodedString().replacingOccurrences(of: "=", with: "")
}
