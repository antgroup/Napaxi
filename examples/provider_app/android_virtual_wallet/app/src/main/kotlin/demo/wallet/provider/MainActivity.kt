package demo.wallet.provider

import android.app.Activity
import android.content.Intent
import android.graphics.Color
import android.os.Bundle
import android.view.Gravity
import android.view.ViewGroup
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.Switch
import android.widget.TextView
import android.widget.Toast
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
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        render()
    }

    override fun onResume() {
        super.onResume()
        render()
    }

    private fun render() {
        val state = WalletStore.load(this)
        val scroll = ScrollView(this).apply {
            setBackgroundColor(Color.rgb(245, 247, 250))
        }
        val root = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(28, 36, 28, 36)
        }
        scroll.addView(root)

        root.addView(label("Virtual Wallet", 28f, Color.rgb(23, 32, 46), bold = true))
        root.addView(label("Provider Agent demo", 14f, Color.rgb(101, 113, 132)))
        root.addGap(22)
        root.addView(summaryCard(state))
        root.addGap(16)
        root.addView(agentTriggerCard())
        root.addGap(16)
        root.addView(settingsCard(state))
        root.addGap(16)
        root.addView(recordsCard(state))

        setContentView(scroll)
    }

    private fun summaryCard(state: WalletState): LinearLayout =
        LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(24, 24, 24, 24)
            cardBackground()
            addView(label("Balance", 13f, Color.rgb(111, 123, 142)))
            addGap(8)
            addView(label("¥${money(state.balance)}", 34f, Color.rgb(20, 31, 48), bold = true))
            addGap(18)
            val row = LinearLayout(context).apply {
                orientation = LinearLayout.HORIZONTAL
            }
            row.addView(metric("Today", "¥${money(state.todaySpending)}"), weightParams(1f))
            row.addView(metric("Records", state.records.size.toString()), weightParams(1f))
            addView(row)
        }

    private fun settingsCard(state: WalletState): LinearLayout =
        LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(24, 22, 24, 22)
            cardBackground()
            addView(label("Quiet small payments", 17f, Color.rgb(31, 42, 58), bold = true))
            addGap(14)
            val row = LinearLayout(context).apply {
                orientation = LinearLayout.HORIZONTAL
                gravity = Gravity.CENTER_VERTICAL
            }
            val switch = Switch(context).apply {
                isChecked = state.quietPayEnabled
                setOnCheckedChangeListener { _, checked ->
                    WalletStore.updateQuietPay(context, checked, WalletStore.load(context).quietPayLimit)
                    render()
                }
            }
            row.addView(switch)
            row.addView(label(
                if (state.quietPayEnabled) "Enabled under ¥${money(state.quietPayLimit)}" else "Disabled",
                15f,
                Color.rgb(78, 91, 111),
            ))
            addView(row)
            addGap(16)
            val limitRow = LinearLayout(context).apply {
                orientation = LinearLayout.HORIZONTAL
                gravity = Gravity.CENTER_VERTICAL
            }
            limitRow.addView(actionButton("-10") {
                WalletStore.updateQuietPay(this@MainActivity, state.quietPayEnabled, state.quietPayLimit - 10.0)
                render()
            }, weightParams(1f))
            limitRow.addView(label("Limit ¥${money(state.quietPayLimit)}", 15f, Color.rgb(31, 42, 58), bold = true).apply {
                gravity = Gravity.CENTER
            }, weightParams(2f))
            limitRow.addView(actionButton("+10") {
                WalletStore.updateQuietPay(this@MainActivity, state.quietPayEnabled, state.quietPayLimit + 10.0)
                render()
            }, weightParams(1f))
            addView(limitRow)
            addGap(16)
            val tools = LinearLayout(context).apply {
                orientation = LinearLayout.HORIZONTAL
            }
            tools.addView(actionButton("Clear records") {
                WalletStore.clearRecords(this@MainActivity)
                render()
            }, weightParams(1f))
            tools.addView(actionButton("Reset") {
                WalletStore.reset(this@MainActivity)
                render()
            }, weightParams(1f))
            addView(tools)
        }

    private fun agentTriggerCard(): LinearLayout =
        LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(24, 22, 24, 22)
            cardBackground()
            addView(label("App to Agent", 17f, Color.rgb(31, 42, 58), bold = true))
            addGap(12)
            addView(LinearLayout(context).apply {
                orientation = LinearLayout.HORIZONTAL
                addView(actionButton("Ask Agent to review today") {
                    triggerAgentReview()
                })
            })
        }

    private fun triggerAgentReview() {
        val binding = TrustedHostStore(this, WalletPackage.PROVIDER_ID).loadLatestBinding()
        if (binding == null) {
            openHostInstall()
            return
        }
        val now = Instant.now()
        val requestId = UUID.randomUUID().toString()
        val trigger = AgentTriggerRequest(
            requestId = requestId,
            providerId = WalletPackage.PROVIDER_ID,
            agentId = WalletPackage.AGENT_ID,
            message = "提醒我查看今日支出，并总结最近的虚拟消费记录",
            source = "virtual_wallet",
            eventType = "review_spending_requested",
            payloadJson = """{"event_id":"$requestId","view":"today_spending"}""",
            createdAt = now.toString(),
            expiresAt = now.plus(5, ChronoUnit.MINUTES).toString(),
            nonce = UUID.randomUUID().toString(),
            idempotencyKey = requestId,
        )
        Thread {
            val result = AgentProvider.submitBackgroundTrigger(this, trigger, binding)
            runOnUiThread {
                when (result.status) {
                    AgentTriggerSubmitResult.ACCEPTED,
                    AgentTriggerSubmitResult.QUEUED -> {
                        Toast.makeText(this, "Sent to Agent Host", Toast.LENGTH_SHORT).show()
                    }
                    AgentTriggerSubmitResult.UNSUPPORTED,
                    AgentTriggerSubmitResult.HOST_UNAVAILABLE -> openForegroundTrigger(trigger, binding)
                    else -> Toast.makeText(
                        this,
                        result.error?.message ?: "Agent Host rejected this trigger.",
                        Toast.LENGTH_LONG,
                    ).show()
                }
            }
        }.start()
    }

    private fun openForegroundTrigger(
        trigger: AgentTriggerRequest,
        binding: TrustedHostBinding,
    ) {
        val signed = AgentProviderSecurity.signTriggerRequest(trigger, binding)
        startActivity(
            AgentProvider.buildHostTriggerIntent(signed, binding.hostPackageName)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
        )
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
            Toast.makeText(
                this,
                "Open the Agent Host and install Virtual Wallet Agent first.",
                Toast.LENGTH_LONG,
            ).show()
            return
        }
        startActivity(installIntent.setPackage(host.activityInfo.packageName))
    }

    private fun recordsCard(state: WalletState): LinearLayout =
        LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(24, 22, 24, 22)
            cardBackground()
            addView(label("Payment records", 17f, Color.rgb(31, 42, 58), bold = true))
            addGap(14)
            if (state.records.isEmpty()) {
                addView(label("No payments yet.", 14f, Color.rgb(111, 123, 142)))
            } else {
                state.records.take(20).forEachIndexed { index, record ->
                    if (index > 0) addGap(12)
                    addView(recordRow(record))
                }
            }
        }

    private fun metric(title: String, value: String): LinearLayout =
        LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            addView(label(title, 12f, Color.rgb(111, 123, 142)))
            addGap(5)
            addView(label(value, 20f, Color.rgb(31, 42, 58), bold = true))
        }

    private fun recordRow(record: PaymentRecord): LinearLayout =
        LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(16, 14, 16, 14)
            background = rounded(Color.rgb(248, 250, 252), Color.rgb(232, 238, 246), 16f)
            val top = LinearLayout(context).apply {
                orientation = LinearLayout.HORIZONTAL
                gravity = Gravity.CENTER_VERTICAL
            }
            top.addView(label(record.merchant, 15f, Color.rgb(31, 42, 58), bold = true), weightParams(1f))
            top.addView(label("-¥${money(record.amount)}", 15f, Color.rgb(188, 64, 64), bold = true))
            addView(top)
            addGap(7)
            val mode = if (record.quietPay) "quiet pay" else "confirmed"
            val note = if (record.note.isBlank()) mode else "$mode · ${record.note}"
            addView(label(note, 12f, Color.rgb(111, 123, 142)))
        }

    private fun actionButton(text: String, block: () -> Unit): TextView =
        buttonLabel(text).apply {
            setOnClickListener { block() }
            layoutParams = LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f).apply {
                leftMargin = 5
                rightMargin = 5
            }
        }

    private fun weightParams(weight: Float): LinearLayout.LayoutParams =
        LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, weight).apply {
            leftMargin = 4
            rightMargin = 4
        }
}
