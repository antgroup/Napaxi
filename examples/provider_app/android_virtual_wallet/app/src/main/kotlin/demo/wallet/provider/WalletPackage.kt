package demo.wallet.provider

import agent.provider.sdk.AgentAction
import agent.provider.sdk.AgentPackage
import agent.provider.sdk.ConfirmationPolicy
import agent.provider.sdk.ExecutionMode

object WalletPackage {
    const val PROVIDER_ID = "demo.virtual_wallet_provider"
    const val AGENT_ID = "demo.virtual_wallet.agent"

    const val ACTION_PAY = "wallet.payment.pay"
    const val ACTION_LIST_RECORDS = "wallet.records.list"
    const val ACTION_CONFIGURE_QUIET_PAY = "wallet.quiet_pay.configure"

    val packageDef: AgentPackage
        get() = AgentPackage(
            providerId = PROVIDER_ID,
            agentId = AGENT_ID,
            displayName = "Virtual Wallet Agent",
            description = "A local demo wallet for provider-confirmed and quiet small payments.",
            systemPrompt = """
                You help the user operate a virtual wallet through provider-owned actions.
                Use app_action_wallet_payment_pay when the user asks to pay a merchant.
                Use app_action_wallet_quiet_pay_configure when the user asks to enable, disable, or change small no-interruption payments.
                Use app_action_wallet_records_list when the user asks about recent spending.
                Payment is virtual demo data only, but still route payment proposals through the provider app.
            """.trimIndent(),
            actions = listOf(
                AgentAction(
                    actionId = ACTION_PAY,
                    toolName = "app_action_wallet_payment_pay",
                    description = "Create a virtual payment record after provider policy and confirmation.",
                    parametersJson = paymentParameters,
                    resultSchemaJson = resultSchema,
                    risk = "high",
                    confirmationPolicy = ConfirmationPolicy.PROVIDER_REQUIRED,
                    executionModes = executionModes,
                    timeoutSeconds = 300,
                ),
                AgentAction(
                    actionId = ACTION_LIST_RECORDS,
                    toolName = "app_action_wallet_records_list",
                    description = "List recent virtual wallet payment records.",
                    parametersJson = """{"type":"object","properties":{"limit":{"type":"integer","minimum":1,"maximum":20}}}""",
                    resultSchemaJson = resultSchema,
                    risk = "low",
                    confirmationPolicy = ConfirmationPolicy.NONE,
                    executionModes = executionModes,
                    timeoutSeconds = 120,
                ),
                AgentAction(
                    actionId = ACTION_CONFIGURE_QUIET_PAY,
                    toolName = "app_action_wallet_quiet_pay_configure",
                    description = "Configure small no-interruption virtual payments.",
                    parametersJson = quietPayParameters,
                    resultSchemaJson = resultSchema,
                    risk = "high",
                    confirmationPolicy = ConfirmationPolicy.PROVIDER_REQUIRED,
                    executionModes = executionModes,
                    timeoutSeconds = 300,
                ),
            ),
            handoffJson = """{"mode":"android_activity_result","display":"wallet_confirmation"}""",
            resultJson = """{"mode":"activity_result","schema":"wallet_result"}""",
        )

    private val executionModes = listOf(
        ExecutionMode.APP_HANDOFF,
        ExecutionMode.ANDROID_ACTIVITY_RESULT,
    )

    private const val paymentParameters =
        """{"type":"object","properties":{"merchant":{"type":"string"},"amount":{"type":"number","exclusiveMinimum":0},"currency":{"type":"string","default":"CNY"},"note":{"type":"string"}},"required":["merchant","amount"]}"""

    private const val quietPayParameters =
        """{"type":"object","properties":{"enabled":{"type":"boolean"},"limit":{"type":"number","minimum":0}}}"""

    private const val resultSchema =
        """{"type":"object","properties":{"status":{"type":"string"},"record":{"type":"object"},"records":{"type":"array"},"balance":{"type":"number"},"balance_display":{"type":"string"},"remaining_balance_text":{"type":"string"},"quiet_pay_applied":{"type":"boolean"},"message":{"type":"string"}}}"""
}
