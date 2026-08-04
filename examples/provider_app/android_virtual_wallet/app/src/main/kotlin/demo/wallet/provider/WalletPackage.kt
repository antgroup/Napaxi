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
                    displayName = "Make payment",
                    localizedDisplayNames = names("Make payment", "虚拟支付"),
                    localizedDescriptions = descriptions("Create a virtual payment record after provider policy and confirmation.", "在应用确认后创建一笔虚拟支付记录。"),
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
                    displayName = "View payment records",
                    localizedDisplayNames = names("View payment records", "查看支付记录"),
                    localizedDescriptions = descriptions("List recent virtual wallet payment records.", "查看最近的虚拟钱包支付记录。"),
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
                    displayName = "Configure quiet pay",
                    localizedDisplayNames = names("Configure quiet pay", "配置小额免打扰支付"),
                    localizedDescriptions = descriptions("Configure small no-interruption virtual payments.", "启用、关闭或调整小额免打扰支付额度。"),
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

    private fun names(english: String, chinese: String) =
        mapOf("en" to english, "zh-CN" to chinese)

    private fun descriptions(english: String, chinese: String) =
        mapOf("en" to english, "zh-CN" to chinese)
}
