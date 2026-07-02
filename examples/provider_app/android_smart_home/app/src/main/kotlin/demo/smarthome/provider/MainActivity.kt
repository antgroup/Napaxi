package demo.smarthome.provider

import android.app.Activity
import android.app.AlertDialog
import android.content.Intent
import android.graphics.Rect
import android.graphics.Typeface
import android.os.Bundle
import android.provider.Settings
import android.text.InputType
import android.util.TypedValue
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.view.WindowManager
import android.widget.EditText
import android.widget.FrameLayout
import android.widget.HorizontalScrollView
import android.widget.CheckBox
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.TextView
import agent.provider.sdk.AgentProvider
import agent.provider.sdk.AgentProviderContract
import agent.provider.sdk.AgentProviderSecurity
import agent.provider.sdk.AgentTriggerRequest
import agent.provider.sdk.AgentTriggerSubmitResult
import agent.provider.sdk.TrustedHostBinding
import agent.provider.sdk.TrustedHostStore
import org.json.JSONObject
import java.time.Instant
import java.time.temporal.ChronoUnit
import java.util.UUID

class MainActivity : Activity() {
    private lateinit var rootView: FrameLayout
    private lateinit var sceneView: HomeSceneView
    private lateinit var assistantHost: FrameLayout
    private lateinit var statusText: TextView
    private lateinit var resultText: TextView
    private lateinit var agentPromptField: EditText
    private var assistantExpanded = false
    private var keyboardBottomInset = 0
    private var latestAgentResponse: HomeAgentResponse? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        AppContext.context = applicationContext
        window.setSoftInputMode(WindowManager.LayoutParams.SOFT_INPUT_ADJUST_RESIZE)
        setContentView(buildUi())
    }

    override fun onResume() {
        super.onResume()
        sceneView.state = VirtualHomeStore.load(this)
        renderAssistantPanel()
    }

    private fun buildUi(): FrameLayout {
        val root = FrameLayout(this).apply {
            setBackgroundColor(Palette.background)
        }
        rootView = root
        sceneView = HomeSceneView(this).apply {
            state = VirtualHomeStore.load(this@MainActivity)
            onDeviceTap = { roomId, deviceId -> handleDeviceTap(roomId, deviceId) }
            onLightBrightnessChange = { roomId, deviceId, brightness ->
                handleBrightness(roomId, deviceId, brightness)
            }
            onMenuTap = { showLogDialog() }
        }
        root.addView(
            sceneView,
            FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.MATCH_PARENT,
            ),
        )

        assistantHost = FrameLayout(this)
        installKeyboardObserver(root)
        renderAssistantPanel()
        return root
    }

    private fun renderAssistantPanel() {
        assistantHost.removeAllViews()
        (assistantHost.parent as? ViewGroup)?.removeView(assistantHost)
        val params = assistantLayoutParams()
        (sceneView.parent as ViewGroup).addView(assistantHost, params)
        assistantHost.addView(
            if (assistantExpanded) buildExpandedAssistantPanel()
            else buildCollapsedAssistantPanel(),
        )
    }

    private fun installKeyboardObserver(root: View) {
        root.viewTreeObserver.addOnGlobalLayoutListener {
            val visible = Rect()
            root.getWindowVisibleDisplayFrame(visible)
            val rootHeight = root.rootView.height
            if (rootHeight <= 0) return@addOnGlobalLayoutListener
            val hiddenHeight = (rootHeight - visible.bottom).coerceAtLeast(0)
            val nextInset = if (hiddenHeight > rootHeight * 0.15f) hiddenHeight else 0
            if (nextInset != keyboardBottomInset) {
                keyboardBottomInset = nextInset
                updateAssistantPosition()
            }
        }
    }

    private fun updateAssistantPosition() {
        if (!::assistantHost.isInitialized || assistantHost.parent == null) return
        assistantHost.layoutParams = assistantLayoutParams()
        assistantHost.requestLayout()
    }

    private fun assistantLayoutParams(): FrameLayout.LayoutParams =
        FrameLayout.LayoutParams(
            if (assistantExpanded) ViewGroup.LayoutParams.MATCH_PARENT
            else ViewGroup.LayoutParams.WRAP_CONTENT,
            ViewGroup.LayoutParams.WRAP_CONTENT,
            Gravity.BOTTOM or Gravity.END,
        ).apply {
            val side = if (assistantExpanded) dp(12) else dp(16)
            leftMargin = side
            rightMargin = side
            bottomMargin = keyboardBottomInset + if (assistantExpanded) dp(10) else dp(18)
        }

    private fun buildCollapsedAssistantPanel(): TextView =
        pill("助手").apply {
            textSize = 14f
            typeface = Typeface.create(Typeface.DEFAULT, Typeface.BOLD)
            minWidth = dp(72)
            setPadding(dp(16), dp(11), dp(16), dp(11))
            setOnClickListener {
                assistantExpanded = true
                renderAssistantPanel()
            }
        }

    private fun buildExpandedAssistantPanel(): LinearLayout {
        val panel = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(14), dp(12), dp(14), dp(12))
            cardBackground()
        }
        val header = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
        }
        statusText = label(connectionTitle(), 14f, Palette.title).apply {
            typeface = Typeface.create(Typeface.DEFAULT, Typeface.BOLD)
            layoutParams = LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f)
        }
        header.addView(statusText)
        header.addView(pill("×").apply {
            typeface = Typeface.create(Typeface.DEFAULT, Typeface.BOLD)
            textSize = 16f
            minWidth = dp(38)
            setPadding(dp(10), dp(6), dp(10), dp(6))
            setOnClickListener {
                assistantExpanded = false
                renderAssistantPanel()
            }
        })
        panel.addView(header)
        resultText = label(latestAgentResponse?.message ?: expandedSubtitle(), 13f, Palette.subtitle)
        panel.addView(resultText, LinearLayout.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT,
            ViewGroup.LayoutParams.WRAP_CONTENT,
        ).apply { topMargin = dp(6) })
        agentPromptField = EditText(this).apply {
            setSingleLine(false)
            minLines = 1
            maxLines = 2
            inputType = InputType.TYPE_CLASS_TEXT or InputType.TYPE_TEXT_FLAG_MULTI_LINE
            hint = "说一句家居请求，例如：打开客厅落地灯"
            textSize = 14f
            setTextColor(Palette.title)
            setHintTextColor(Palette.subtitle)
            setPadding(dp(14), dp(10), dp(14), dp(10))
            background = rounded(Palette.pillBg, Palette.pillStroke, dp(14).toFloat())
        }
        panel.addView(agentPromptField, LinearLayout.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT,
            ViewGroup.LayoutParams.WRAP_CONTENT,
        ).apply { topMargin = dp(10) })

        val actionRow = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            setPadding(0, 0, dp(2), 0)
        }
        actionRow.addView(compactActionPill("运行") { runHomeAgent() })
        actionRow.addView(compactActionPill("门口") { runPresenceEvent() })
        actionRow.addView(compactActionPill("围栏") { showAIniceBridgeDialog() })
        latestAgentResponse?.proposedAction?.let {
            actionRow.addView(compactActionPill("执行建议") { executeSuggestion() })
        }
        // The hand-off button appears only when the local agent itself decided to
        // collaborate (via the request_napaxi_collaboration tool), instead of a
        // keyword-triggered button that was always present.
        if (latestAgentResponse?.type == HomeAgentOutcomeType.COLLABORATION_OFFER) {
            actionRow.addView(compactActionPill("交给 Napaxi") { requestNapaxiCollaboration() })
        }
        actionRow.addView(compactActionPill("灯") { showYeelightConfigDialog() })
        actionRow.addView(compactActionPill("点阵") { openYeelightMatrix() })
        actionRow.addView(compactActionPill("模型") { showModelConfigDialog() })
        actionRow.addView(compactActionPill(if (isNapaxiConnected()) "刷新" else "连接") {
            openHostInstall()
        })
        val actionScroller = HorizontalScrollView(this).apply {
            isHorizontalScrollBarEnabled = false
            addView(actionRow)
        }
        panel.addView(actionScroller, LinearLayout.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT,
            ViewGroup.LayoutParams.WRAP_CONTENT,
        ).apply { topMargin = dp(10) })
        return panel
    }

    private fun compactActionPill(text: String, block: () -> Unit): TextView =
        pill(text).apply {
            setOnClickListener { block() }
            textSize = 12f
            setPadding(dp(12), dp(8), dp(12), dp(8))
            layoutParams = LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.WRAP_CONTENT,
                ViewGroup.LayoutParams.WRAP_CONTENT,
            ).apply {
                rightMargin = dp(8)
            }
        }

    private fun runHomeAgent() {
        val message = agentPromptField.text?.toString()?.trim().orEmpty()
        agentPromptField.setText("")
        setAssistantStatus("家居助手正在调用本地 Napaxi SDK...")
        SmartHomeAgentRuntime.handleUserMessage(this, message) { response ->
            setAgentResponse(response)
        }
    }

    private fun runPresenceEvent() {
        setAgentResponse(SmartHomeAgentRuntime.handlePresenceDetected(this))
    }

    private fun executeSuggestion() {
        val response = latestAgentResponse ?: return
        setAgentResponse(SmartHomeAgentRuntime.executeProposedAction(this, response))
    }

    private fun requestNapaxiCollaboration() {
        val response = latestAgentResponse ?: SmartHomeAgentRuntime.emptyMessageResponse(this)
        val binding = trustStore().loadLatestBinding()
        if (binding == null) {
            setAssistantStatus("请先连接 Napaxi，再请求外部 Agent 协作。")
            openHostInstall()
            return
        }
        sendAgentTrigger(response, binding)
    }

    private fun showAIniceBridgeDialog() {
        val message = AIniceEventBridge.statusSummary(this)
        AlertDialog.Builder(this)
            .setTitle("电子围栏")
            .setMessage(
                "$message\n\n授权后，应用只处理米家通知里的电子围栏/AInice/到家离家关键词，并把事件推给 Napaxi。",
            )
            .setNegativeButton("关闭", null)
            .setNeutralButton("测试推送") { _, _ -> testAIniceBridge() }
            .setPositiveButton("去授权") { _, _ -> openNotificationAccessSettings() }
            .show()
    }

    private fun openNotificationAccessSettings() {
        runCatching {
            startActivity(Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS))
        }.onFailure {
            setAssistantStatus("无法打开通知监听设置，请在系统设置里为 Smart Home Agent 开启通知使用权。")
        }
    }

    private fun testAIniceBridge() {
        val event = AIniceEventBridge.sampleEvent()
        val binding = SmartHomeTriggerBridge.latestBinding(this)
        if (binding == null) {
            setAssistantStatus("请先连接 Napaxi，再测试电子围栏推送。")
            openHostInstall()
            return
        }
        val trigger = SmartHomeTriggerBridge.buildRequest(
            message = event.message,
            eventType = event.eventType,
            payloadJson = event.payloadJson,
            source = "mijia_ainice_notification_test",
        )
        setAssistantStatus("正在测试电子围栏事件推送...")
        runOffMain({ AgentProvider.submitBackgroundTrigger(this, trigger, binding) }) { outcome ->
            val result = outcome.getOrNull()
            when (result?.status) {
                AgentTriggerSubmitResult.ACCEPTED,
                AgentTriggerSubmitResult.QUEUED -> {
                    AIniceEventBridge.saveResult(this, "测试事件已推送到 Napaxi。")
                    setAssistantStatus("测试事件已推送到 Napaxi。")
                }
                AgentTriggerSubmitResult.UNSUPPORTED,
                AgentTriggerSubmitResult.HOST_UNAVAILABLE -> openForegroundTrigger(trigger, binding)
                else -> {
                    val error = result?.error?.message
                        ?: outcome.exceptionOrNull()?.message
                        ?: "Napaxi 拒绝了电子围栏测试事件。"
                    AIniceEventBridge.saveResult(this, error)
                    setAssistantStatus(error)
                }
            }
        }
    }

    private fun showModelConfigDialog() {
        val current = SmartHomeAgentRuntime.loadSdkConfig(this)
        val container = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(20), dp(10), dp(20), dp(4))
        }
        val providerField = configField("provider", current.provider.ifBlank { "openai_compatible" })
        val baseUrlField = configField("base url，可留空", current.baseUrl)
        val modelField = configField("model", current.model)
        val apiKeyField = configField("api key", current.apiKey).apply {
            inputType = InputType.TYPE_CLASS_TEXT or InputType.TYPE_TEXT_VARIATION_PASSWORD
        }
        container.addView(providerField)
        container.addView(baseUrlField)
        container.addView(modelField)
        container.addView(apiKeyField)
        AlertDialog.Builder(this)
            .setTitle("本地 Napaxi SDK")
            .setView(container)
            .setNegativeButton("取消", null)
            .setPositiveButton("保存") { _, _ ->
                SmartHomeAgentRuntime.saveSdkConfig(
                    this,
                    HomeAgentSdkConfig(
                        provider = providerField.text?.toString().orEmpty(),
                        baseUrl = baseUrlField.text?.toString().orEmpty(),
                        model = modelField.text?.toString().orEmpty(),
                        apiKey = apiKeyField.text?.toString().orEmpty(),
                    ),
                )
                setAssistantStatus("已保存本地 Napaxi SDK 配置：${SmartHomeAgentRuntime.sdkSummary(this)}")
            }
            .show()
    }

    private fun showYeelightConfigDialog() {
        val current = YeelightLanClient.loadConfig(this)
        val container = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(20), dp(10), dp(20), dp(4))
        }
        val enabledCheck = CheckBox(this).apply {
            text = "启用 Yeelight LAN"
            isChecked = current.enabled
            textSize = 14f
            setTextColor(Palette.title)
        }
        val hostField = configField("IP", current.host)
        val portField = configField("port", current.port.toString()).apply {
            inputType = InputType.TYPE_CLASS_NUMBER
        }
        val roomField = configField("room", current.room)
        val deviceField = configField("device", current.device)
        container.addView(enabledCheck)
        container.addView(hostField)
        container.addView(portField)
        container.addView(roomField)
        container.addView(deviceField)
        AlertDialog.Builder(this)
            .setTitle("Yeelight LAN")
            .setView(container)
            .setNegativeButton("取消", null)
            .setNeutralButton("测试") { _, _ ->
                saveYeelightConfig(
                    enabledCheck.isChecked,
                    hostField.text?.toString().orEmpty(),
                    portField.text?.toString().orEmpty(),
                    roomField.text?.toString().orEmpty(),
                    deviceField.text?.toString().orEmpty(),
                )
                testYeelightConnection()
            }
            .setPositiveButton("保存") { _, _ ->
                saveYeelightConfig(
                    enabledCheck.isChecked,
                    hostField.text?.toString().orEmpty(),
                    portField.text?.toString().orEmpty(),
                    roomField.text?.toString().orEmpty(),
                    deviceField.text?.toString().orEmpty(),
                )
                setAssistantStatus("已保存 Yeelight：${YeelightLanClient.summary(this)}")
            }
            .show()
    }

    private fun saveYeelightConfig(
        enabled: Boolean,
        host: String,
        port: String,
        room: String,
        device: String,
    ) {
        YeelightLanClient.saveConfig(
            this,
            YeelightLanConfig(
                enabled = enabled,
                host = host,
                port = port.toIntOrNull() ?: 55443,
                room = room.ifBlank { "living_room" },
                device = device.ifBlank { "floor_lamp" },
            ),
        )
    }

    private fun testYeelightConnection() {
        setAssistantStatus("正在测试 Yeelight LAN：${YeelightLanClient.summary(this)}")
        runOffMain({ YeelightLanClient.testConnection(this) }) { outcome ->
            outcome.fold(
                onSuccess = { result -> setAssistantStatus("Yeelight 已连接：$result") },
                onFailure = { error ->
                    setAssistantStatus("Yeelight 连接失败：${error.message ?: "未知错误"}")
                },
            )
        }
    }

    private fun openYeelightMatrix() {
        startActivity(Intent(this, YeelightMatrixActivity::class.java))
    }

    private fun configField(hintText: String, value: String): EditText =
        EditText(this).apply {
            hint = hintText
            setText(value)
            setSingleLine(true)
            textSize = 14f
            setTextColor(Palette.title)
            setHintTextColor(Palette.subtitle)
            setPadding(dp(12), dp(8), dp(12), dp(8))
            background = rounded(Palette.pillBg, Palette.pillStroke, dp(12).toFloat())
            layoutParams = LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.WRAP_CONTENT,
            ).apply { topMargin = dp(10) }
        }

    private fun setAgentResponse(response: HomeAgentResponse) {
        latestAgentResponse = response
        sceneView.state = response.state
        assistantExpanded = true
        renderAssistantPanel()
    }

    private fun setAssistantStatus(message: String) {
        latestAgentResponse = HomeAgentResponse(
            type = HomeAgentOutcomeType.STATUS,
            message = message,
            state = VirtualHomeStore.load(this),
        )
        assistantExpanded = true
        renderAssistantPanel()
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
            setAssistantStatus("未找到 Napaxi demo。请先打开或安装 Napaxi demo。")
            return
        }
        setAssistantStatus(
            if (isNapaxiConnected()) {
                "正在刷新 Napaxi demo 里的 Smart Home Agent 工具列表..."
            } else {
                "正在连接 Napaxi demo..."
            },
        )
        startActivity(installIntent.setPackage(host.activityInfo.packageName))
    }

    private fun sendAgentTrigger(
        response: HomeAgentResponse,
        binding: TrustedHostBinding,
    ) {
        val trigger = agentTriggerRequest(
            message = response.napaxiMessage,
            eventType = response.eventType,
            payloadJson = response.payloadJson,
        )
        setAssistantStatus("正在把家居助手上下文交给 Napaxi Agent...")
        runOffMain({ AgentProvider.submitBackgroundTrigger(this, trigger, binding) }) { outcome ->
            val result = outcome.getOrNull()
            when (result?.status) {
                AgentTriggerSubmitResult.ACCEPTED,
                AgentTriggerSubmitResult.QUEUED -> {
                    setAssistantStatus("Napaxi Agent 已收到家居助手上下文。")
                }
                AgentTriggerSubmitResult.UNSUPPORTED,
                AgentTriggerSubmitResult.HOST_UNAVAILABLE -> openForegroundTrigger(trigger, binding)
                else -> {
                    setAssistantStatus(
                        result?.error?.message
                            ?: outcome.exceptionOrNull()?.message
                            ?: "Napaxi 拒绝了协作请求。",
                    )
                }
            }
        }
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
            setAssistantStatus("已打开 Napaxi demo 继续协作。")
        } catch (_: Exception) {
            setAssistantStatus("没有 Napaxi demo 处理这次协作请求。")
        }
    }

    private fun agentTriggerRequest(
        message: String,
        eventType: String,
        payloadJson: String,
    ): AgentTriggerRequest {
        val now = Instant.now()
        val requestId = UUID.randomUUID().toString()
        return AgentTriggerRequest(
            requestId = requestId,
            providerId = SmartHomePackage.PROVIDER_ID,
            agentId = SmartHomePackage.AGENT_ID,
            message = message,
            source = "virtual_smart_home",
            eventType = eventType,
            payloadJson = payloadJson,
            createdAt = now.toString(),
            expiresAt = now.plus(5, ChronoUnit.MINUTES).toString(),
            nonce = UUID.randomUUID().toString(),
            idempotencyKey = requestId,
        )
    }

    private fun connectionTitle(): String =
        if (SmartHomeAgentRuntime.isSdkConfigured(this)) {
            "家居助手 · ${SmartHomeAgentRuntime.sdkSummary(this)}"
        } else {
            "家居助手 · 本地 Napaxi SDK 未配置"
        }

    private fun expandedSubtitle(): String =
        if (isNapaxiConnected()) {
            "先由本地 Napaxi SDK 处理；需要时再请求 Napaxi 协作。"
        } else {
            "配置模型后，本地 Napaxi SDK 可直接调用灯光工具。"
        }

    private fun isNapaxiConnected(): Boolean =
        trustStore().loadLatestBinding() != null

    private fun handleDeviceTap(roomId: String, deviceId: String) {
        val current = VirtualHomeStore.load(this)
        val device = current.room(roomId)?.device(deviceId) ?: return
        val next = when (device.kind) {
            DeviceKind.LIGHT -> SmartHomeActionRunner.applyAction(
                this,
                SmartHomePackage.ACTION_LIGHT_SET,
                JSONObject()
                    .put("room", roomId)
                    .put("device", deviceId)
                    .put("on", !device.on)
                    .apply {
                        if (!device.on && device.brightness == 0) put("brightness", 60)
                    }
                    .toString(),
                source = "manual",
            )
            DeviceKind.COVER -> VirtualHomeStore.applyAction(
                this,
                SmartHomePackage.ACTION_COVER_SET,
                JSONObject()
                    .put("room", roomId)
                    .put("device", deviceId)
                    .put("position", if (device.position > 0) 0 else 100)
                    .toString(),
                source = "manual",
            )
            DeviceKind.MEDIA -> VirtualHomeStore.applyAction(
                this,
                SmartHomePackage.ACTION_MEDIA_TOGGLE,
                JSONObject()
                    .put("room", roomId)
                    .put("device", deviceId)
                    .put("on", !device.on)
                    .toString(),
                source = "manual",
            )
            DeviceKind.APPLIANCE -> VirtualHomeStore.applyAction(
                this,
                SmartHomePackage.ACTION_APPLIANCE_TOGGLE,
                JSONObject()
                    .put("room", roomId)
                    .put("device", deviceId)
                    .put("on", !device.on)
                    .toString(),
                source = "manual",
            )
            DeviceKind.CLIMATE -> VirtualHomeStore.applyAction(
                this,
                SmartHomePackage.ACTION_CLIMATE_SET,
                JSONObject()
                    .put("room", roomId)
                    .put("device", deviceId)
                    .put("mode", if (device.on) "off" else "cool")
                    .put("target_temp", device.targetTempC ?: 24)
                    .toString(),
                source = "manual",
            )
            DeviceKind.SENSOR -> return
        }
        sceneView.state = next
    }

    private fun handleBrightness(roomId: String, deviceId: String, brightness: Int) {
        val next = SmartHomeActionRunner.applyAction(
            this,
            SmartHomePackage.ACTION_LIGHT_SET,
            JSONObject()
                .put("room", roomId)
                .put("device", deviceId)
                .put("brightness", brightness)
                .put("on", brightness > 0)
                .toString(),
            source = "manual",
        )
        sceneView.state = next
    }

    private fun showLogDialog() {
        val current = VirtualHomeStore.load(this)
        val container = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(20), dp(16), dp(20), dp(16))
        }
        if (current.log.isEmpty()) {
            container.addView(label("暂无日志", 14f, Palette.subtitle))
        } else {
            val scroll = ScrollView(this).apply {
                layoutParams = LinearLayout.LayoutParams(
                    LinearLayout.LayoutParams.MATCH_PARENT,
                    dp(360),
                )
            }
            val list = LinearLayout(this).apply {
                orientation = LinearLayout.VERTICAL
            }
            current.log.forEach { entry ->
                list.addView(label(entry.format(), 13f, Palette.title).apply {
                    setPadding(0, dp(6), 0, dp(6))
                })
                list.addView(android.view.View(this@MainActivity).apply {
                    setBackgroundColor(Palette.divider)
                    layoutParams = LinearLayout.LayoutParams(
                        LinearLayout.LayoutParams.MATCH_PARENT,
                        1,
                    )
                })
            }
            scroll.addView(list)
            container.addView(scroll)
        }
        AlertDialog.Builder(this)
            .setTitle("操作日志")
            .setView(container)
            .setNegativeButton("关闭", null)
            .setPositiveButton("清空") { _, _ ->
                VirtualHomeStore.clearLog(this)
                sceneView.state = VirtualHomeStore.load(this)
            }
            .show()
            .also { dialog ->
                dialog.findViewById<TextView>(android.R.id.title)?.typeface =
                    Typeface.create(Typeface.DEFAULT, Typeface.BOLD)
            }
    }

    private fun trustStore(): TrustedHostStore =
        TrustedHostStore(this, SmartHomePackage.PROVIDER_ID)

    private fun dp(value: Int): Int =
        TypedValue.applyDimension(
            TypedValue.COMPLEX_UNIT_DIP,
            value.toFloat(),
            resources.displayMetrics,
        ).toInt()
}
