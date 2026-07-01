package demo.smarthome.provider

import android.content.Context
import android.os.Looper
import android.util.Base64
import org.json.JSONArray
import org.json.JSONObject
import java.io.BufferedReader
import java.io.InputStreamReader
import java.io.OutputStreamWriter
import java.net.InetSocketAddress
import java.net.Socket
import java.net.SocketTimeoutException
import java.util.concurrent.atomic.AtomicInteger
import java.util.concurrent.CountDownLatch
import java.util.concurrent.atomic.AtomicReference

data class YeelightLanConfig(
    val enabled: Boolean,
    val host: String,
    val port: Int = 55443,
    val room: String = "living_room",
    val device: String = "floor_lamp",
) {
    val isReady: Boolean
        get() = enabled && host.isNotBlank() && port in 1..65535
}

object SmartHomeActionRunner {
    fun applyAction(
        context: Context,
        actionId: String,
        argsJson: String,
        source: String,
    ): VirtualHomeState {
        when (actionId) {
            SmartHomePackage.ACTION_LIGHT_SET -> YeelightLanClient.applyLightIfMapped(context, argsJson)
            SmartHomePackage.ACTION_LIGHT_MATRIX_DRAW -> {
                val result = YeelightLanClient.drawMatrixFromArgs(context, argsJson)
                return VirtualHomeStore.recordAgentNote(
                    context,
                    "Yeelight Cube",
                    "已执行 20 x 5 点阵图案：${result.optInt("pixels", YeelightLanClient.MATRIX_PIXEL_COUNT)} 点。",
                )
            }
        }
        return VirtualHomeStore.applyAction(context, actionId, argsJson, source)
    }
}

object YeelightLanClient {
    private const val PREFS = "yeelight_lan"
    private const val KEY_ENABLED = "enabled"
    private const val KEY_HOST = "host"
    private const val KEY_PORT = "port"
    private const val KEY_ROOM = "room"
    private const val KEY_DEVICE = "device"
    private const val DEFAULT_HOST = "192.168.43.238"
    private val nextCommandId = AtomicInteger(100)

    fun loadConfig(context: Context): YeelightLanConfig {
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        return YeelightLanConfig(
            // Off by default so the demo stays fully virtual until a user opts in
            // to controlling a real lamp via the Yeelight LAN dialog.
            enabled = prefs.getBoolean(KEY_ENABLED, false),
            host = prefs.getString(KEY_HOST, DEFAULT_HOST).orEmpty(),
            port = prefs.getInt(KEY_PORT, 55443),
            room = prefs.getString(KEY_ROOM, "living_room").orEmpty(),
            device = prefs.getString(KEY_DEVICE, "floor_lamp").orEmpty(),
        )
    }

    fun saveConfig(context: Context, config: YeelightLanConfig) {
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .edit()
            .putBoolean(KEY_ENABLED, config.enabled)
            .putString(KEY_HOST, config.host.trim())
            .putInt(KEY_PORT, config.port)
            .putString(KEY_ROOM, config.room.trim())
            .putString(KEY_DEVICE, config.device.trim())
            .apply()
    }

    fun summary(context: Context): String {
        val config = loadConfig(context)
        return if (config.isReady) {
            "${config.host}:${config.port} -> ${config.room}/${config.device}"
        } else {
            "未绑定"
        }
    }

    fun applyLightIfMapped(context: Context, argsJson: String) {
        if (Looper.myLooper() == Looper.getMainLooper()) {
            // Best-effort sync to the real lamp: run off the main thread (fire and
            // forget) so an unreachable lamp's socket timeout can neither block nor
            // crash the UI. The virtual home state is updated by the caller regardless.
            Thread { applyLightIfMapped(context, argsJson) }.start()
            return
        }
        val config = loadConfig(context)
        if (!config.isReady) return
        val args = JSONObject(argsJson)
        val room = args.optString("room")
        val device = args.optString("device")
        if (room != config.room || device != config.device) return

        // The lamp may be offline. Treat real-device control as best-effort and
        // never propagate a network error to the caller — in this demo the virtual
        // home state is the source of truth, not the physical lamp.
        runCatching {
            val power = when {
                args.has("on") -> args.getBoolean("on")
                args.has("brightness") -> args.optInt("brightness") > 0
                else -> true
            }
            setPower(config, power)
            if (power && args.has("brightness")) {
                setBrightness(config, args.optInt("brightness").coerceIn(1, 100))
            }
            if (power && args.has("rgb")) {
                setRgb(config, args.optInt("rgb"))
            }
        }
    }

    fun testConnection(context: Context): JSONObject {
        val config = loadConfig(context)
        check(config.isReady) { "Yeelight LAN is not configured" }
        val response = sendCommand(
            config,
            "get_prop",
            JSONArray().put("power").put("bright").put("rgb"),
        )
        return response ?: JSONObject().put("status", "connected_without_response")
    }

    fun drawPreset(context: Context, preset: String): JSONObject {
        val colors = when (preset) {
            "checker" -> List(MATRIX_PIXEL_COUNT) { index ->
                if (index % 2 == 0) 0x00FF00 else 0x0000FF
            }
            "off" -> List(MATRIX_PIXEL_COUNT) { 0x000000 }
            else -> List(MATRIX_PIXEL_COUNT) { 0xFF0000 }
        }
        return drawMatrix100(context, colors)
    }

    fun drawMatrix100(context: Context, colors: List<Int>): JSONObject {
        if (Looper.myLooper() == Looper.getMainLooper()) {
            return runOffMainResult { drawMatrix100(context, colors) }
        }
        val config = loadConfig(context)
        check(config.isReady) { "Yeelight LAN is not configured" }
        check(colors.size == MATRIX_PIXEL_COUNT) {
            "Yeelight Cube matrix requires exactly $MATRIX_PIXEL_COUNT RGB pixels"
        }
        sendCommand(
            config,
            "activate_fx_mode",
            JSONArray().put(JSONObject().put("mode", "direct")),
        )
        sendCommand(
            config,
            "update_leds",
            JSONArray().put(colors.joinToString(separator = "") { rgb -> encodeRgb(rgb) }),
            readResponse = false,
        )
        return JSONObject()
            .put("status", "ok")
            .put("pixels", colors.size)
            .put("layout", "20x5")
    }

    fun drawMatrixFromArgs(context: Context, argsJson: String): JSONObject {
        val args = JSONObject(argsJson)
        val pixels = args.optJSONArray("pixels") ?: error("pixels is required")
        val colors = mutableListOf<Int>()
        for (index in 0 until pixels.length()) {
            colors += parseColor(pixels.getString(index))
        }
        return drawMatrix100(context, colors)
    }

    fun drawMatrix25(context: Context, colors: List<Int>): JSONObject {
        check(colors.size == 25) { "Yeelight legacy matrix requires exactly 25 RGB pixels" }
        return drawMatrix100(context, colors + List(MATRIX_PIXEL_COUNT - 25) { 0x000000 })
    }

    private fun setPower(config: YeelightLanConfig, on: Boolean) {
        sendCommand(
            config,
            "set_power",
            JSONArray()
                .put(if (on) "on" else "off")
                .put("smooth")
                .put(500),
        )
    }

    private fun setBrightness(config: YeelightLanConfig, brightness: Int) {
        sendCommand(
            config,
            "set_bright",
            JSONArray()
                .put(brightness.coerceIn(1, 100))
                .put("smooth")
                .put(500),
        )
    }

    private fun setRgb(config: YeelightLanConfig, rgb: Int) {
        sendCommand(
            config,
            "set_rgb",
            JSONArray()
                .put(rgb and 0xFFFFFF)
                .put("smooth")
                .put(500),
        )
    }

    private fun sendCommand(
        config: YeelightLanConfig,
        method: String,
        params: JSONArray,
        readResponse: Boolean = true,
    ): JSONObject? {
        val id = nextCommandId.incrementAndGet()
        val command = JSONObject()
            .put("id", id)
            .put("method", method)
            .put("params", params)
            .toString() + "\r\n"
        Socket().use { socket ->
            socket.connect(InetSocketAddress(config.host, config.port), 1200)
            socket.soTimeout = 1600
            val writer = OutputStreamWriter(socket.getOutputStream())
            writer.write(command)
            writer.flush()
            if (!readResponse) return null
            return try {
                val line = BufferedReader(InputStreamReader(socket.getInputStream())).readLine()
                if (line.isNullOrBlank()) null else JSONObject(line)
            } catch (_: SocketTimeoutException) {
                null
            }
        }
    }

    private fun encodeRgb(rgb: Int): String {
        val bytes = byteArrayOf(
            ((rgb shr 16) and 0xFF).toByte(),
            ((rgb shr 8) and 0xFF).toByte(),
            (rgb and 0xFF).toByte(),
        )
        return Base64.encodeToString(bytes, Base64.NO_WRAP)
    }

    private fun parseColor(value: String): Int {
        val hex = value.trim().removePrefix("#")
        check(hex.length == 6) { "Color must be #RRGGBB: $value" }
        return hex.toInt(16) and 0xFFFFFF
    }

    private const val MATRIX_COLUMNS = 20
    private const val MATRIX_ROWS = 5
    const val MATRIX_PIXEL_COUNT = MATRIX_COLUMNS * MATRIX_ROWS

    private fun runOffMain(block: () -> Unit) {
        val done = CountDownLatch(1)
        val failure = AtomicReference<Throwable?>()
        Thread {
            runCatching { block() }
                .onFailure { failure.set(it) }
            done.countDown()
        }.start()
        done.await()
        failure.get()?.let { throw it }
    }

    private fun <T> runOffMainResult(block: () -> T): T {
        val done = CountDownLatch(1)
        val failure = AtomicReference<Throwable?>()
        val result = AtomicReference<T?>()
        Thread {
            runCatching { block() }
                .onSuccess { result.set(it) }
                .onFailure { failure.set(it) }
            done.countDown()
        }.start()
        done.await()
        failure.get()?.let { throw it }
        @Suppress("UNCHECKED_CAST")
        return result.get() as T
    }
}
