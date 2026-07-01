import AgentProvider
import Foundation

enum WalletPackage {
    static let providerId = "demo.virtual_wallet_provider"
    static let agentId = "demo.virtual_wallet.agent"

    static let actionPay = "wallet.payment.pay"
    static let actionListRecords = "wallet.records.list"
    static let actionConfigureQuietPay = "wallet.quiet_pay.configure"

    static let installURL = "wallet-provider://agent/install"
    static let actionURL = "wallet-provider://agent/action"
    static let hostInstallURL = "agent-host://agent-provider/add"
    static let hostTriggerURL = "agent-host://agent-provider/trigger"

    static let packageDef = AgentPackage(
        providerId: providerId,
        agentId: agentId,
        displayName: "Virtual Wallet Agent",
        description: "A local demo wallet for provider-confirmed and quiet small payments.",
        systemPrompt: """
        You help the user operate a virtual wallet through provider-owned actions.
        Use app_action_wallet_payment_pay when the user asks to pay a merchant.
        Use app_action_wallet_quiet_pay_configure when the user asks to enable, disable, or change small no-interruption payments.
        Use app_action_wallet_records_list when the user asks about recent spending.
        Payment is virtual demo data only, but still route payment proposals through the provider app.
        """,
        actions: [
            AgentAction(
                actionId: actionPay,
                toolName: "app_action_wallet_payment_pay",
                description: "Create a virtual payment record after provider policy and confirmation.",
                parameters: [
                    "type": .string("object"),
                    "properties": .object([
                        "merchant": .object(["type": .string("string")]),
                        "amount": .object([
                            "type": .string("number"),
                            "exclusiveMinimum": .number(0),
                        ]),
                        "currency": .object([
                            "type": .string("string"),
                            "default": .string("CNY"),
                        ]),
                        "note": .object(["type": .string("string")]),
                    ]),
                    "required": .array([.string("merchant"), .string("amount")]),
                ],
                resultSchema: resultSchema,
                risk: "high",
                confirmationPolicy: "provider_required",
                executionModes: ["app_handoff"],
                timeoutSeconds: 300
            ),
            AgentAction(
                actionId: actionListRecords,
                toolName: "app_action_wallet_records_list",
                description: "List recent virtual wallet payment records.",
                parameters: [
                    "type": .string("object"),
                    "properties": .object([
                        "limit": .object([
                            "type": .string("integer"),
                            "minimum": .number(1),
                            "maximum": .number(20),
                        ]),
                    ]),
                ],
                resultSchema: resultSchema,
                risk: "low",
                confirmationPolicy: "none",
                executionModes: ["app_handoff"],
                timeoutSeconds: 120
            ),
            AgentAction(
                actionId: actionConfigureQuietPay,
                toolName: "app_action_wallet_quiet_pay_configure",
                description: "Configure small no-interruption virtual payments.",
                parameters: [
                    "type": .string("object"),
                    "properties": .object([
                        "enabled": .object(["type": .string("boolean")]),
                        "limit": .object([
                            "type": .string("number"),
                            "minimum": .number(0),
                        ]),
                    ]),
                ],
                resultSchema: resultSchema,
                risk: "high",
                confirmationPolicy: "provider_required",
                executionModes: ["app_handoff"],
                timeoutSeconds: 300
            ),
        ],
        handoff: ["mode": .string("ios_url_handoff"), "display": .string("wallet_confirmation")],
        result: ["mode": .string("callback_url"), "schema": .string("wallet_result")]
    )

    private static let resultSchema: [String: JSONValue] = [
        "type": .string("object"),
        "properties": .object([
            "status": .object(["type": .string("string")]),
            "record": .object(["type": .string("object")]),
            "records": .object(["type": .string("array")]),
            "balance": .object(["type": .string("number")]),
            "balance_display": .object(["type": .string("string")]),
            "remaining_balance_text": .object(["type": .string("string")]),
            "quiet_pay_applied": .object(["type": .string("boolean")]),
            "message": .object(["type": .string("string")]),
        ]),
    ]
}
