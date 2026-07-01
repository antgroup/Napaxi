package demo.smartdesk.provider

import android.content.Context
import android.graphics.Color
import org.json.JSONObject
import java.time.Instant

data class VirtualDeskState(
    val scene: String = "standby",
    val lightOn: Boolean = true,
    val brightness: Int = 42,
    val color: Int = Color.rgb(64, 170, 255),
    val plugOn: Boolean = false,
    val lastProposal: String = "Waiting for Agent",
    val lastResult: String = "No result yet",
    val sensorPulse: Int = 0,
) {
    val colorHex: String
        get() = "#%06X".format(0xFFFFFF and color)

    fun toResultJson(): String =
        JSONObject()
            .put("scene", scene)
            .put("light_on", lightOn)
            .put("brightness", brightness)
            .put("color", colorHex)
            .put("plug_on", plugOn)
            .put("timestamp", Instant.now().toString())
            .toString()
}

object VirtualDeskStore {
    private const val PREFS = "virtual_smart_desk"

    fun load(context: Context): VirtualDeskState {
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        return VirtualDeskState(
            scene = prefs.getString("scene", "standby") ?: "standby",
            lightOn = prefs.getBoolean("light_on", true),
            brightness = prefs.getInt("brightness", 42),
            color = prefs.getInt("color", Color.rgb(64, 170, 255)),
            plugOn = prefs.getBoolean("plug_on", false),
            lastProposal = prefs.getString("last_proposal", "Waiting for Agent")
                ?: "Waiting for Agent",
            lastResult = prefs.getString("last_result", "No result yet") ?: "No result yet",
            sensorPulse = prefs.getInt("sensor_pulse", 0),
        )
    }

    fun save(context: Context, state: VirtualDeskState) {
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .edit()
            .putString("scene", state.scene)
            .putBoolean("light_on", state.lightOn)
            .putInt("brightness", state.brightness)
            .putInt("color", state.color)
            .putBoolean("plug_on", state.plugOn)
            .putString("last_proposal", state.lastProposal)
            .putString("last_result", state.lastResult)
            .putInt("sensor_pulse", state.sensorPulse)
            .apply()
    }

    fun applyAction(context: Context, actionId: String, argsJson: String): VirtualDeskState {
        val current = load(context)
        val args = runCatching { JSONObject(argsJson) }.getOrElse { JSONObject() }
        val next = when (actionId) {
            SmartDeskPackage.ACTION_FOCUS -> current.copy(
                scene = "focus",
                lightOn = true,
                brightness = 92,
                color = Color.rgb(78, 170, 255),
                plugOn = true,
                lastResult = "Focus scene active",
            )
            SmartDeskPackage.ACTION_RELAX -> current.copy(
                scene = "relax",
                lightOn = true,
                brightness = 58,
                color = Color.rgb(255, 145, 86),
                plugOn = true,
                lastResult = "Relax scene active",
            )
            SmartDeskPackage.ACTION_OFF -> current.copy(
                scene = "off",
                lightOn = false,
                brightness = 0,
                color = Color.rgb(38, 44, 60),
                plugOn = false,
                lastResult = "Desk powered down",
            )
            SmartDeskPackage.ACTION_SET_COLOR -> current.copy(
                scene = "custom",
                lightOn = true,
                color = parseColor(args.optString("color"), current.color),
                lastResult = "Light color updated",
            )
            SmartDeskPackage.ACTION_SET_BRIGHTNESS -> current.copy(
                scene = "custom",
                lightOn = args.optInt("brightness", current.brightness) > 0,
                brightness = args.optInt("brightness", current.brightness).coerceIn(0, 100),
                lastResult = "Brightness updated",
            )
            SmartDeskPackage.ACTION_PLUG_ON -> current.copy(
                plugOn = true,
                lastResult = "Plug is online",
            )
            SmartDeskPackage.ACTION_PLUG_OFF -> current.copy(
                plugOn = false,
                lastResult = "Plug is offline",
            )
            SmartDeskPackage.ACTION_STATUS -> current.copy(lastResult = "Status returned")
            else -> current.copy(lastResult = "Unsupported action: $actionId")
        }
        save(context, next)
        return next
    }

    fun recordProposal(context: Context, actionId: String): VirtualDeskState {
        val next = load(context).copy(lastProposal = actionId, lastResult = "Waiting for confirmation")
        save(context, next)
        return next
    }

    fun recordSensor(context: Context): VirtualDeskState {
        val current = load(context)
        val next = current.copy(
            sensorPulse = current.sensorPulse + 1,
            lastProposal = "virtual_sensor.button.single",
            lastResult = "Sensor event sent to Agent",
        )
        save(context, next)
        return next
    }

    private fun parseColor(value: String, fallback: Int): Int =
        runCatching { Color.parseColor(value) }.getOrDefault(fallback)
}
