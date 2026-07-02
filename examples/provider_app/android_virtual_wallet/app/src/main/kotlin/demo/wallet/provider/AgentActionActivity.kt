package demo.wallet.provider

import android.app.Activity
import android.graphics.Color
import android.os.Bundle
import android.view.Gravity
import android.view.ViewGroup
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.TextView
import agent.provider.sdk.ActionError
import agent.provider.sdk.ActionProposal
import agent.provider.sdk.ActionResult
import agent.provider.sdk.ActionResultStatus
import agent.provider.sdk.AgentProvider
import agent.provider.sdk.AgentProviderSecurity
import agent.provider.sdk.TrustedHostStore
import agent.provider.sdk.TrustedProposalStatus
import agent.provider.sdk.TrustedProposalValidationResult
import org.json.JSONObject
import java.time.Instant

class AgentActionActivity : Activity() {
    private var proposal: ActionProposal? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        overridePendingTransition(0, 0)
        val parsed = AgentProvider.parseProposal(intent)
        if (parsed == null) {
            setResult(RESULT_CANCELED)
            finish()
            return
        }
        proposal = parsed

        val trust = AgentProviderSecurity.validateTrustedProposal(
            this,
            parsed,
            WalletPackage.packageDef,
            trustStore(),
            System.currentTimeMillis(),
        )
        if (!canContinueWithTrustResult(trust)) {
            finishFailure(trust.code ?: "invalid_proposal", trust.message ?: "Invalid proposal")
            return
        }

        when (parsed.actionId) {
            WalletPackage.ACTION_PAY -> handlePay(parsed, trust)
            WalletPackage.ACTION_LIST_RECORDS -> finishRecords(parsed, trust)
            WalletPackage.ACTION_CONFIGURE_QUIET_PAY -> showConfigureConfirmation(parsed, trust)
            else -> finishFailure("unsupported_action", "Unsupported action: ${parsed.actionId}")
        }
    }

    private fun handlePay(proposal: ActionProposal, trust: TrustedProposalValidationResult) {
        val draft = WalletStore.parsePaymentDraft(proposal.argumentsJson)
        if (!draft.isValid) {
            finishFailure("invalid_payment", "Payment requires a merchant and positive amount")
            return
        }
        val state = WalletStore.load(this)
        val quietPay = trust.isTrusted && state.quietPayEnabled && draft.amount <= state.quietPayLimit
        if (quietPay) {
            val (next, record) = WalletStore.addPayment(
                this,
                draft,
                proposal.requestId,
                confirmedByUser = false,
                quietPay = true,
            )
            finishSuccess(
                WalletStore.resultJson(
                    next,
                    paymentMessage(draft, next, "with quiet pay"),
                    record = record,
                    quietPayApplied = true,
                ),
            )
            markConsumedIfTrusted(proposal, trust)
            return
        }
        showPaymentConfirmation(proposal, draft, state, trust)
    }

    private fun showPaymentConfirmation(
        proposal: ActionProposal,
        draft: PaymentDraft,
        state: WalletState,
        trust: TrustedProposalValidationResult,
    ) {
        setContentView(confirmationLayout(
            title = "Confirm payment",
            lines = listOf(
                "Merchant" to draft.merchant,
                "Amount" to "¥${money(draft.amount)} ${draft.currency}",
                "Note" to draft.note.ifBlank { "-" },
                "Quiet pay" to if (state.quietPayEnabled) "Enabled under ¥${money(state.quietPayLimit)}" else "Disabled",
                "Source" to if (trust.isTrusted) "Trusted host" else "Untrusted, confirmation required",
            ),
            confirmText = "Pay",
            onConfirm = {
                val (next, record) = WalletStore.addPayment(
                    this,
                    draft,
                    proposal.requestId,
                    confirmedByUser = true,
                    quietPay = false,
                )
                finishSuccess(
                    WalletStore.resultJson(
                        next,
                        paymentMessage(draft, next, "after provider confirmation"),
                        record = record,
                    ),
                )
                markConsumedIfTrusted(proposal, trust)
            },
        ))
    }

    private fun showConfigureConfirmation(proposal: ActionProposal, trust: TrustedProposalValidationResult) {
        val state = WalletStore.load(this)
        val args = runCatching { JSONObject(proposal.argumentsJson) }.getOrElse { JSONObject() }
        val enabled = if (args.has("enabled")) args.optBoolean("enabled") else state.quietPayEnabled
        val limit = if (args.has("limit")) args.optDouble("limit") else state.quietPayLimit
        setContentView(confirmationLayout(
            title = "Update quiet pay",
            lines = listOf(
                "New status" to if (enabled) "Enabled" else "Disabled",
                "New limit" to "¥${money(limit)}",
                "Current limit" to "¥${money(state.quietPayLimit)}",
                "Source" to if (trust.isTrusted) "Trusted host" else "Untrusted, confirmation required",
            ),
            confirmText = "Update",
            onConfirm = {
                val next = WalletStore.updateQuietPay(this, enabled, limit)
                finishSuccess(
                    WalletStore.resultJson(
                        next,
                        "Quiet pay ${if (next.quietPayEnabled) "enabled" else "disabled"} under ¥${money(next.quietPayLimit)}.",
                    ),
                )
                markConsumedIfTrusted(proposal, trust)
            },
        ))
    }

    private fun finishRecords(proposal: ActionProposal, trust: TrustedProposalValidationResult) {
        val args = runCatching { JSONObject(proposal.argumentsJson) }.getOrElse { JSONObject() }
        val limit = args.optInt("limit", 10).coerceIn(1, 20)
        val state = WalletStore.load(this)
        finishSuccess(
            WalletStore.resultJson(
                state,
                "Returned ${state.records.take(limit).size} payment records.",
                records = state.records.take(limit),
            ),
        )
        markConsumedIfTrusted(proposal, trust)
    }

    private fun confirmationLayout(
        title: String,
        lines: List<Pair<String, String>>,
        confirmText: String,
        onConfirm: () -> Unit,
    ): ScrollView {
        val scroll = ScrollView(this).apply {
            setBackgroundColor(Color.rgb(245, 247, 250))
        }
        val root = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(28, 42, 28, 28)
        }
        scroll.addView(root)

        root.addView(label(title, 26f, Color.rgb(23, 32, 46), bold = true))
        root.addView(label("Virtual Wallet Provider", 14f, Color.rgb(101, 113, 132)))
        root.addGap(22)

        val card = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(24, 24, 24, 24)
            cardBackground()
        }
        lines.forEachIndexed { index, row ->
            if (index > 0) card.addGap(16)
            card.addView(detailRow(row.first, row.second))
        }
        root.addView(card)
        root.addGap(18)

        val actions = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER
        }
        actions.addView(actionButton("Cancel") {
            finishCanceled()
        }, weightParams(1f))
        actions.addView(actionButton(confirmText) {
            onConfirm()
        }, weightParams(1f))
        root.addView(actions)
        return scroll
    }

    private fun detailRow(name: String, value: String): LinearLayout =
        LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            addView(label(name, 12f, Color.rgb(111, 123, 142)))
            addGap(6)
            addView(label(value, 18f, Color.rgb(31, 42, 58), bold = true))
        }

    private fun actionButton(text: String, block: () -> Unit): TextView =
        buttonLabel(text).apply {
            setOnClickListener { block() }
        }

    private fun weightParams(weight: Float): LinearLayout.LayoutParams =
        LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, weight).apply {
            leftMargin = 5
            rightMargin = 5
        }

    private fun finishSuccess(resultJson: String) {
        finishWithResult(ActionResultStatus.SUCCEEDED, resultJson)
    }

    private fun finishCanceled() {
        finishWithResult(
            ActionResultStatus.CANCELED,
            WalletStore.resultJson(
                WalletStore.load(this),
                "Payment canceled by provider user.",
                status = "canceled",
            ),
            ActionError("user_canceled", "Action was canceled by the provider user."),
        )
    }

    private fun finishFailure(code: String, message: String) {
        finishWithResult(
            ActionResultStatus.FAILED,
            WalletStore.resultJson(WalletStore.load(this), message, status = "failed"),
            ActionError(code, message),
        )
    }

    private fun finishWithResult(
        status: String,
        resultJson: String,
        error: ActionError? = null,
    ) {
        val result = ActionResult(
            requestId = proposal?.requestId ?: "",
            status = status,
            resultJson = resultJson,
            error = error,
            providerTraceId = "wallet-${System.currentTimeMillis()}",
            completedAt = Instant.now().toString(),
        )
        setResult(Activity.RESULT_OK, AgentProvider.buildResultIntent(result))
        finish()
        overridePendingTransition(0, 0)
    }

    private fun trustStore(): TrustedHostStore =
        TrustedHostStore(this, WalletPackage.PROVIDER_ID)

    private fun canContinueWithTrustResult(result: TrustedProposalValidationResult): Boolean {
        if (result.isValid) return true
        return when (result.status) {
            TrustedProposalStatus.UNTRUSTED -> true
            else -> false
        }
    }

    private fun markConsumedIfTrusted(
        proposal: ActionProposal,
        trust: TrustedProposalValidationResult,
    ) {
        if (trust.isTrusted) {
            AgentProviderSecurity.markProposalConsumed(trustStore(), proposal)
        }
    }

    private fun paymentMessage(
        draft: PaymentDraft,
        state: WalletState,
        suffix: String,
    ): String =
        "Paid ¥${money(draft.amount)} ${draft.currency} to ${draft.merchant} $suffix. " +
            "Remaining balance is ¥${money(state.balance)} CNY."
}
