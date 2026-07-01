package demo.smartdesk.provider

import android.app.Activity
import android.graphics.Color
import android.os.Bundle
import android.os.Handler
import android.os.Looper
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
import java.time.Instant

class AgentActionActivity : Activity() {
    private lateinit var sceneView: DeskSceneView
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

        val validation = AgentProvider.validateProposal(
            proposal!!,
            SmartDeskPackage.packageDef,
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

        VirtualDeskStore.recordProposal(this, proposal!!.actionId)
        setContentView(buildUi(proposal!!))
        if (intent.getBooleanExtra(EXTRA_AUTO_EXECUTE, false)) {
            Handler(Looper.getMainLooper()).post { executeProposal() }
        }
    }

    private fun buildUi(proposal: ActionProposal): FrameLayout {
        val root = FrameLayout(this).apply {
            setBackgroundColor(Color.rgb(245, 247, 250))
        }
        sceneView = DeskSceneView(this).apply {
            state = VirtualDeskStore.load(this@AgentActionActivity)
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
            setPadding(32, 30, 32, 30)
            panelBackground()
        }
        titleText = label("Confirm Action", 24f, Color.rgb(25, 35, 50))
        detailText = label(
            proposalDetails(proposal),
            14f,
            Color.rgb(91, 104, 123),
        )
        panel.addView(titleText)
        panel.addView(detailText, LinearLayout.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT,
            ViewGroup.LayoutParams.WRAP_CONTENT,
        ).apply { topMargin = 14 })

        val row = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER
        }
        row.addView(pill("Cancel").apply {
            setOnClickListener {
                finishWithResult(
                    ActionResultStatus.CANCELED,
                    error = ActionError("user_canceled", "Action was canceled by the provider user."),
                )
            }
            layoutParams = LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f).apply {
                rightMargin = 8
            }
        })
        row.addView(pill("Confirm").apply {
            setOnClickListener { executeProposal() }
            layoutParams = LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f).apply {
                leftMargin = 8
            }
        })
        panel.addView(row, LinearLayout.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT,
            ViewGroup.LayoutParams.WRAP_CONTENT,
        ).apply { topMargin = 24 })

        root.addView(
            panel,
            FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.WRAP_CONTENT,
                Gravity.BOTTOM,
            ).apply {
                leftMargin = 28
                rightMargin = 28
                bottomMargin = 28
            },
        )
        return root
    }

    private fun executeProposal() {
        val activeProposal = proposal ?: return
        titleText.text = "Running"
        detailText.text = "Applying ${activeProposal.actionId} to the virtual desk..."
        val next = VirtualDeskStore.applyAction(
            this,
            activeProposal.actionId,
            activeProposal.argumentsJson,
        )
        sceneView.state = next
        Handler(Looper.getMainLooper()).postDelayed({
            finishWithResult(ActionResultStatus.SUCCEEDED)
        }, 1100L)
    }

    private fun finishWithResult(status: String, error: ActionError? = null) {
        val activeProposal = proposal
        val result = ActionResult(
            requestId = activeProposal?.requestId ?: "",
            status = status,
            resultJson = VirtualDeskStore.load(this).toResultJson(),
            error = error,
            providerTraceId = "smart-desk-${System.currentTimeMillis()}",
            completedAt = Instant.now().toString(),
        )
        setResult(Activity.RESULT_OK, AgentProvider.buildResultIntent(result))
        finish()
    }

    private fun proposalDetails(proposal: ActionProposal): String =
        """
        Action: ${proposal.actionId}
        Risk: ${proposal.risk}
        Request: ${proposal.requestId.take(8)}
        """.trimIndent()

    private companion object {
        const val EXTRA_AUTO_EXECUTE = "napaxi_auto_execute"
    }
}
