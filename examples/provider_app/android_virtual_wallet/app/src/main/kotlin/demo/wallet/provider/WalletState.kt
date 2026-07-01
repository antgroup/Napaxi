package demo.wallet.provider

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.util.Locale
import java.util.UUID
import kotlin.math.max

data class PaymentRecord(
    val recordId: String,
    val merchant: String,
    val amount: Double,
    val currency: String,
    val note: String,
    val createdAt: String,
    val confirmedByUser: Boolean,
    val quietPay: Boolean,
    val requestId: String,
) {
    fun toJsonObject(): JSONObject =
        JSONObject()
            .put("record_id", recordId)
            .put("merchant", merchant)
            .put("amount", amount)
            .put("amount_display", "¥${money(amount)} $currency")
            .put("currency", currency)
            .put("note", note)
            .put("created_at", createdAt)
            .put("confirmed_by_user", confirmedByUser)
            .put("quiet_pay", quietPay)
            .put("request_id", requestId)

    companion object {
        fun fromJsonObject(obj: JSONObject): PaymentRecord =
            PaymentRecord(
                recordId = obj.optString("record_id"),
                merchant = obj.optString("merchant", "Unknown merchant"),
                amount = obj.optDouble("amount", 0.0),
                currency = obj.optString("currency", "CNY"),
                note = obj.optString("note", ""),
                createdAt = obj.optString("created_at"),
                confirmedByUser = obj.optBoolean("confirmed_by_user", false),
                quietPay = obj.optBoolean("quiet_pay", false),
                requestId = obj.optString("request_id"),
            )
    }
}

data class WalletState(
    val balance: Double = 1888.00,
    val quietPayEnabled: Boolean = false,
    val quietPayLimit: Double = 30.00,
    val records: List<PaymentRecord> = emptyList(),
) {
    val todaySpending: Double
        get() {
            val today = LocalDate.now()
            return records.filter {
                runCatching {
                    Instant.parse(it.createdAt).atZone(ZoneId.systemDefault()).toLocalDate() == today
                }.getOrDefault(false)
            }.sumOf { it.amount }
        }
}

data class PaymentDraft(
    val merchant: String,
    val amount: Double,
    val currency: String,
    val note: String,
) {
    val isValid: Boolean
        get() = merchant.isNotBlank() && amount > 0.0
}

object WalletStore {
    private const val PREFS = "virtual_wallet_provider"
    private const val DEFAULT_BALANCE = 1888.00
    private const val DEFAULT_QUIET_LIMIT = 30.00

    fun load(context: Context): WalletState {
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val recordsJson = prefs.getString("records", "[]") ?: "[]"
        return WalletState(
            balance = prefs.getFloat("balance", DEFAULT_BALANCE.toFloat()).toDouble(),
            quietPayEnabled = prefs.getBoolean("quiet_pay_enabled", false),
            quietPayLimit = prefs.getFloat("quiet_pay_limit", DEFAULT_QUIET_LIMIT.toFloat()).toDouble(),
            records = parseRecords(recordsJson),
        )
    }

    fun reset(context: Context): WalletState {
        val next = WalletState()
        save(context, next)
        return next
    }

    fun clearRecords(context: Context): WalletState {
        val current = load(context)
        val next = current.copy(records = emptyList())
        save(context, next)
        return next
    }

    fun updateQuietPay(context: Context, enabled: Boolean, limit: Double): WalletState {
        val current = load(context)
        val next = current.copy(
            quietPayEnabled = enabled,
            quietPayLimit = max(0.0, limit),
        )
        save(context, next)
        return next
    }

    fun addPayment(
        context: Context,
        draft: PaymentDraft,
        requestId: String,
        confirmedByUser: Boolean,
        quietPay: Boolean,
    ): Pair<WalletState, PaymentRecord> {
        val current = load(context)
        val record = PaymentRecord(
            recordId = UUID.randomUUID().toString(),
            merchant = draft.merchant.ifBlank { "Unknown merchant" },
            amount = draft.amount,
            currency = draft.currency.ifBlank { "CNY" },
            note = draft.note,
            createdAt = Instant.now().toString(),
            confirmedByUser = confirmedByUser,
            quietPay = quietPay,
            requestId = requestId,
        )
        val next = current.copy(
            balance = current.balance - draft.amount,
            records = listOf(record) + current.records,
        )
        save(context, next)
        return next to record
    }

    fun parsePaymentDraft(argsJson: String): PaymentDraft {
        val args = runCatching { JSONObject(argsJson) }.getOrElse { JSONObject() }
        return PaymentDraft(
            merchant = args.optString("merchant", "Unknown merchant"),
            amount = args.optDouble("amount", 0.0),
            currency = args.optString("currency", "CNY"),
            note = args.optString("note", ""),
        )
    }

    fun resultJson(
        state: WalletState,
        message: String,
        status: String = "ok",
        record: PaymentRecord? = null,
        records: List<PaymentRecord> = emptyList(),
        quietPayApplied: Boolean = false,
    ): String {
        val obj = JSONObject()
            .put("status", status)
            .put("balance", roundMoney(state.balance))
            .put("balance_display", "¥${money(state.balance)} CNY")
            .put("remaining_balance_text", "Remaining balance is ¥${money(state.balance)} CNY.")
            .put("quiet_pay_applied", quietPayApplied)
            .put("message", message)
            .put("quiet_pay_enabled", state.quietPayEnabled)
            .put("quiet_pay_limit", roundMoney(state.quietPayLimit))
            .put("quiet_pay_limit_display", "¥${money(state.quietPayLimit)} CNY")
        record?.let { obj.put("record", it.toJsonObject()) }
        if (records.isNotEmpty()) {
            obj.put("records", JSONArray(records.map { it.toJsonObject() }))
        }
        return obj.toString()
    }

    private fun save(context: Context, state: WalletState) {
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .edit()
            .putFloat("balance", state.balance.toFloat())
            .putBoolean("quiet_pay_enabled", state.quietPayEnabled)
            .putFloat("quiet_pay_limit", state.quietPayLimit.toFloat())
            .putString("records", JSONArray(state.records.map { it.toJsonObject() }).toString())
            .apply()
    }

    private fun parseRecords(json: String): List<PaymentRecord> {
        val array = runCatching { JSONArray(json) }.getOrElse { JSONArray() }
        return List(array.length()) { index ->
            PaymentRecord.fromJsonObject(array.getJSONObject(index))
        }
    }
}

fun money(value: Double): String = String.format(Locale.US, "%.2f", value)

fun roundMoney(value: Double): Double = money(value).toDouble()
