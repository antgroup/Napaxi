package demo.smartdesk.provider

import android.app.Activity
import android.content.Intent
import android.graphics.Color
import android.os.Bundle
import android.view.Gravity
import android.view.ViewGroup
import android.widget.FrameLayout
import android.widget.LinearLayout
import android.widget.TextView
import agent.provider.sdk.AgentProvider
import agent.provider.sdk.AgentProviderContract
import agent.provider.sdk.AgentProviderSecurity
import agent.provider.sdk.AgentTriggerRequest
import agent.provider.sdk.AgentTriggerSubmitResult
import agent.provider.sdk.TrustedHostBinding
import agent.provider.sdk.TrustedHostStore
import java.time.Instant
import java.time.temporal.ChronoUnit
import java.util.UUID

class MainActivity : Activity() {
    private lateinit var sceneView: DeskSceneView
    private lateinit var statusText: TextView
    private lateinit var resultText: TextView

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        AppContext.context = applicationContext
        setContentView(buildUi())
    }

    override fun onResume() {
        super.onResume()
        renderState(VirtualDeskStore.load(this))
    }

    private fun buildUi(): FrameLayout {
        val root = FrameLayout(this).apply {
            setBackgroundColor(Color.rgb(245, 247, 250))
        }
        sceneView = DeskSceneView(this).apply {
            state = VirtualDeskStore.load(this@MainActivity)
        }
        root.addView(
            sceneView,
            FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.MATCH_PARENT,
            ),
        )

        val top = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(32, 38, 32, 0)
        }
        top.addView(label("Smart Desk", 26f, Color.rgb(25, 35, 50)))
        top.addView(label("Provider Agent demo", 14f, Color.rgb(104, 116, 134)))
        root.addView(
            top,
            FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.WRAP_CONTENT,
                Gravity.TOP,
            ),
        )

        val bottom = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(26, 24, 26, 24)
            panelBackground()
        }
        statusText = label("", 15f, Color.rgb(31, 42, 58))
        resultText = label("", 13f, Color.rgb(104, 116, 134))
        bottom.addView(statusText)
        bottom.addView(resultText, LinearLayout.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT,
            ViewGroup.LayoutParams.WRAP_CONTENT,
        ).apply { topMargin = 10 })

        val row = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER
        }
        row.addView(actionPill("Desk Button") { triggerSensor() })
        row.addView(actionPill("Focus") {
            renderState(VirtualDeskStore.applyAction(this, SmartDeskPackage.ACTION_FOCUS, "{}"))
        })
        row.addView(actionPill("Reset") {
            VirtualDeskStore.save(this, VirtualDeskState())
            renderState(VirtualDeskStore.load(this))
        })
        bottom.addView(row, LinearLayout.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT,
            ViewGroup.LayoutParams.WRAP_CONTENT,
        ).apply { topMargin = 22 })

        root.addView(
            bottom,
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

    private fun actionPill(text: String, block: () -> Unit): TextView =
        pill(text).apply {
            setOnClickListener { block() }
            layoutParams = LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f).apply {
                leftMargin = 6
                rightMargin = 6
            }
        }

    private fun triggerSensor() {
        val next = VirtualDeskStore.recordSensor(this)
        renderState(next)
        val binding = TrustedHostStore(this, SmartDeskPackage.PROVIDER_ID).loadLatestBinding()
        if (binding == null) {
            openHostInstall()
            return
        }
        val now = Instant.now()
        val requestId = UUID.randomUUID().toString()
        val trigger = AgentTriggerRequest(
            requestId = requestId,
            providerId = SmartDeskPackage.PROVIDER_ID,
            agentId = SmartDeskPackage.AGENT_ID,
            message = "桌面按钮被按下，请进入专注模式",
            source = "virtual_smart_desk",
            eventType = "desk_button_pressed",
            payloadJson = """{"button":"desk","event_id":"$requestId"}""",
            createdAt = now.toString(),
            expiresAt = now.plus(5, ChronoUnit.MINUTES).toString(),
            nonce = UUID.randomUUID().toString(),
            idempotencyKey = requestId,
        )
        resultText.text = "Sending desk event to Agent Host..."
        Thread {
            val result = AgentProvider.submitBackgroundTrigger(this, trigger, binding)
            runOnUiThread {
                when (result.status) {
                    AgentTriggerSubmitResult.ACCEPTED,
                    AgentTriggerSubmitResult.QUEUED -> {
                        resultText.text = "Desk event sent to Agent Host without switching apps."
                    }
                    AgentTriggerSubmitResult.UNSUPPORTED,
                    AgentTriggerSubmitResult.HOST_UNAVAILABLE -> openForegroundTrigger(trigger, binding)
                    else -> {
                        resultText.text = result.error?.message ?: "Agent Host rejected this desk event."
                    }
                }
            }
        }.start()
    }

    private fun openForegroundTrigger(
        trigger: AgentTriggerRequest,
        binding: TrustedHostBinding,
    ) {
        val signed = AgentProviderSecurity.signTriggerRequest(trigger, binding)
        val intent = AgentProvider.buildHostTriggerIntent(signed, binding.hostPackageName)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        try {
            startActivity(intent)
        } catch (_: Exception) {
            resultText.text = "Button event recorded. No Agent host handled TRIGGER_AGENT yet."
        }
    }

    private fun openHostInstall() {
        val installIntent = Intent(AgentProviderContract.ACTION_HOST_INSTALL_PROVIDER_AGENT).apply {
            addCategory(Intent.CATEGORY_DEFAULT)
            putExtra("providerPackageName", packageName)
            putExtra("installActivityName", AgentInstallActivity::class.java.name)
            putExtra("activityName", AgentActionActivity::class.java.name)
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        val host = packageManager.queryIntentActivities(installIntent, 0).firstOrNull()
        if (host == null) {
            resultText.text = "Open the Agent Host and install Smart Desk Agent first."
            return
        }
        startActivity(installIntent.setPackage(host.activityInfo.packageName))
    }

    private fun renderState(state: VirtualDeskState) {
        sceneView.state = state
        statusText.text = "Scene ${state.scene} · Light ${if (state.lightOn) "on" else "off"} · ${state.brightness}% · Plug ${if (state.plugOn) "on" else "off"}"
        resultText.text = "Last proposal: ${state.lastProposal}\nLast result: ${state.lastResult}"
    }
}
