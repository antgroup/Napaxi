package demo.smarthome.provider

import android.app.Activity
import android.graphics.Typeface
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.util.TypedValue
import android.view.Gravity
import android.view.ViewGroup
import android.widget.FrameLayout
import android.widget.LinearLayout
import android.widget.TextView
import agent.provider.sdk.ActionError
import agent.provider.sdk.ActionProposal
import agent.provider.sdk.ActionResult
import agent.provider.sdk.ActionResultStatus
import agent.provider.sdk.AgentProvider
import agent.provider.sdk.AgentProviderSecurity
import agent.provider.sdk.ConfirmationPolicy
import agent.provider.sdk.TrustedHostStore
import org.json.JSONObject
import java.time.Instant

class AgentActionActivity : Activity() {
    private lateinit var sceneView: HomeSceneView
    private lateinit var titleText: TextView
    private lateinit var detailText: TextView
    private var proposal: ActionProposal? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        AppContext.context = applicationContext
        proposal = AgentProvider.parseProposal(intent)
        if (proposal == null) {
            setResult(RESULT_CANCELED)
            finish()
            return
        }

        val validation = AgentProviderSecurity.validateTrustedProposal(
            this,
            proposal!!,
            SmartHomePackage.packageDef,
            trustStore(),
            System.currentTimeMillis(),
        )
        if (!validation.isValid) {
            finishWithResult(
                ActionResultStatus.FAILED,
                error = ActionError(
                    validation.code ?: "invalid_proposal",
                    validation.message ?: "Invalid proposal",
                ),
            )
            return
        }

        SmartHomeAgentRuntime.recordNapaxiProposal(
            this,
            proposal!!.actionId,
            proposal!!.argumentsJson,
        )
        if (shouldAutoExecute(proposal!!)) {
            executeProposalQuietly(proposal!!)
            return
        }
        setContentView(buildUi(proposal!!))
    }

    private fun buildUi(proposal: ActionProposal): FrameLayout {
        val root = FrameLayout(this).apply {
            setBackgroundColor(Palette.background)
        }
        sceneView = HomeSceneView(this).apply {
            state = VirtualHomeStore.load(this@AgentActionActivity)
        }
        root.addView(
            sceneView,
            FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.MATCH_PARENT,
            ),
        )

        val panel = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(20), dp(18), dp(20), dp(18))
            cardBackground()
        }
        titleText = label(actionTitle(proposal), 20f, Palette.title).apply {
            typeface = Typeface.create(Typeface.DEFAULT, Typeface.BOLD)
        }
        detailText = label(
            proposalDetails(proposal),
            13f,
            Palette.subtitle,
        )
        panel.addView(titleText)
        panel.addView(detailText, LinearLayout.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT,
            ViewGroup.LayoutParams.WRAP_CONTENT,
        ).apply { topMargin = dp(8) })

        val row = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER
        }
        row.addView(pill("取消").apply {
            setOnClickListener {
                finishWithResult(
                    ActionResultStatus.CANCELED,
                    error = ActionError("user_canceled", "Action was canceled by the provider user."),
                )
            }
            layoutParams = LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f).apply {
                rightMargin = dp(6)
            }
        })
        row.addView(pill("确认").apply {
            setOnClickListener { executeProposal() }
            layoutParams = LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f).apply {
                leftMargin = dp(6)
            }
        })
        panel.addView(row, LinearLayout.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT,
            ViewGroup.LayoutParams.WRAP_CONTENT,
        ).apply { topMargin = dp(16) })

        root.addView(
            panel,
            FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.WRAP_CONTENT,
                Gravity.BOTTOM,
            ).apply {
                leftMargin = dp(12)
                rightMargin = dp(12)
                bottomMargin = dp(12)
            },
        )
        return root
    }

    private fun executeProposal() {
        val activeProposal = proposal ?: return
        titleText.text = "执行中"
        detailText.text = "家居助手正在执行 ${activeProposal.actionId}…"
        val next = executeAction(activeProposal).getOrElse { error ->
            finishWithResult(
                ActionResultStatus.FAILED,
                error = ActionError("execution_failed", error.message ?: error::class.java.simpleName),
            )
            return
        }
        sceneView.state = next
        Handler(Looper.getMainLooper()).postDelayed({
            AgentProviderSecurity.markProposalConsumed(trustStore(), activeProposal)
            SmartHomeAgentRuntime.recordNapaxiResult(this, ActionResultStatus.SUCCEEDED)
            finishWithResult(ActionResultStatus.SUCCEEDED)
        }, 1100L)
    }

    private fun executeProposalQuietly(activeProposal: ActionProposal) {
        Thread {
            executeAction(activeProposal).fold(
                onSuccess = {
                    AgentProviderSecurity.markProposalConsumed(trustStore(), activeProposal)
                    SmartHomeAgentRuntime.recordNapaxiResult(this, ActionResultStatus.SUCCEEDED)
                    runOnUiThread { finishWithResult(ActionResultStatus.SUCCEEDED) }
                },
                onFailure = { error ->
                    runOnUiThread {
                        finishWithResult(
                            ActionResultStatus.FAILED,
                            error = ActionError(
                                "execution_failed",
                                error.message ?: error::class.java.simpleName,
                            ),
                        )
                    }
                },
            )
        }.start()
    }

    private fun executeAction(activeProposal: ActionProposal): Result<VirtualHomeState> =
        runCatching {
            SmartHomeActionRunner.applyAction(
                this,
                activeProposal.actionId,
                activeProposal.argumentsJson,
                source = "home_agent",
            )
        }

    private fun finishWithResult(status: String, error: ActionError? = null) {
        val activeProposal = proposal
        val result = ActionResult(
            requestId = activeProposal?.requestId ?: "",
            status = status,
            resultJson = VirtualHomeStore.load(this).toResultJson(),
            error = error,
            providerTraceId = "smart-home-${System.currentTimeMillis()}",
            completedAt = Instant.now().toString(),
        )
        setResult(Activity.RESULT_OK, AgentProvider.buildResultIntent(result))
        finish()
    }

    private fun proposalDetails(proposal: ActionProposal): String =
        """
        动作：${proposal.actionId}
        参数：${proposalArgumentsSummary(proposal)}
        风险：${proposal.risk}
        请求：${proposal.requestId.take(8)}
        """.trimIndent()

    private fun actionTitle(proposal: ActionProposal): String =
        when (proposal.actionId) {
            SmartHomePackage.ACTION_LIGHT_MATRIX_DRAW -> "外部 Agent 请求绘制点阵灯"
            else -> "外部 Agent 请求控制灯光"
        }

    private fun proposalArgumentsSummary(proposal: ActionProposal): String {
        if (proposal.actionId != SmartHomePackage.ACTION_LIGHT_MATRIX_DRAW) {
            return proposal.argumentsJson
        }
        val args = runCatching { JSONObject(proposal.argumentsJson) }.getOrNull()
            ?: return proposal.argumentsJson.take(240)
        val pixels = args.optJSONArray("pixels")
        val preview = if (pixels == null) {
            "无 pixels"
        } else {
            val colors = mutableListOf<String>()
            val count = minOf(8, pixels.length())
            for (index in 0 until count) colors += pixels.optString(index)
            "${pixels.length()} 个像素，前 $count 个：${colors.joinToString()}"
        }
        return "20 x 5 Yeelight 点阵，$preview"
    }

    private fun trustStore(): TrustedHostStore =
        TrustedHostStore(this, SmartHomePackage.PROVIDER_ID)

    private fun shouldAutoExecute(proposal: ActionProposal): Boolean {
        if (intent.getBooleanExtra(EXTRA_AUTO_EXECUTE, false)) return true
        if (proposal.confirmationPolicy == ConfirmationPolicy.NONE) return true
        val declaredAction = SmartHomePackage.packageDef.actions.firstOrNull {
            it.actionId == proposal.actionId && it.toolName == proposal.toolName
        }
        return declaredAction?.confirmationPolicy == ConfirmationPolicy.NONE
    }

    private fun dp(value: Int): Int =
        TypedValue.applyDimension(
            TypedValue.COMPLEX_UNIT_DIP,
            value.toFloat(),
            resources.displayMetrics,
        ).toInt()

    private companion object {
        const val EXTRA_AUTO_EXECUTE = "napaxi_auto_execute"
    }
}
