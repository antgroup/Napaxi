import AgentProvider
import Foundation

struct PaymentRecord: Codable, Equatable {
    var recordId: String
    var merchant: String
    var amount: Double
    var currency: String
    var note: String
    var createdAt: String
    var confirmedByUser: Bool
    var quietPay: Bool
    var requestId: String

    var jsonValue: JSONValue {
        .object([
            "record_id": .string(recordId),
            "merchant": .string(merchant),
            "amount": .number(roundMoney(amount)),
            "amount_display": .string("¥\(money(amount)) \(currency)"),
            "currency": .string(currency),
            "note": .string(note),
            "created_at": .string(createdAt),
            "confirmed_by_user": .bool(confirmedByUser),
            "quiet_pay": .bool(quietPay),
            "request_id": .string(requestId),
        ])
    }
}

struct WalletState: Codable, Equatable {
    var balance: Double = 1888.00
    var quietPayEnabled: Bool = false
    var quietPayLimit: Double = 30.00
    var records: [PaymentRecord] = []

    var todaySpending: Double {
        let calendar = Calendar.current
        let formatter = ISO8601DateFormatter()
        return records.reduce(0) { total, record in
            guard let date = formatter.date(from: record.createdAt),
                  calendar.isDateInToday(date) else {
                return total
            }
            return total + record.amount
        }
    }
}

struct PaymentDraft {
    var merchant: String
    var amount: Double
    var currency: String
    var note: String

    var isValid: Bool {
        !merchant.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && amount > 0
    }
}

enum WalletStore {
    private static let key = "virtual_wallet_provider_state"

    static func load() -> WalletState {
        guard let data = UserDefaults.standard.data(forKey: key),
              let state = try? JSONDecoder().decode(WalletState.self, from: data) else {
            return WalletState()
        }
        return state
    }

    @discardableResult
    static func reset() -> WalletState {
        let state = WalletState()
        save(state)
        return state
    }

    @discardableResult
    static func clearRecords() -> WalletState {
        var state = load()
        state.records = []
        save(state)
        return state
    }

    @discardableResult
    static func updateQuietPay(enabled: Bool, limit: Double) -> WalletState {
        var state = load()
        state.quietPayEnabled = enabled
        state.quietPayLimit = max(0, limit)
        save(state)
        return state
    }

    static func addPayment(
        draft: PaymentDraft,
        requestId: String,
        confirmedByUser: Bool,
        quietPay: Bool
    ) -> (WalletState, PaymentRecord) {
        var state = load()
        let record = PaymentRecord(
            recordId: UUID().uuidString,
            merchant: draft.merchant.isEmpty ? "Unknown merchant" : draft.merchant,
            amount: draft.amount,
            currency: draft.currency.isEmpty ? "CNY" : draft.currency,
            note: draft.note,
            createdAt: ISO8601DateFormatter().string(from: Date()),
            confirmedByUser: confirmedByUser,
            quietPay: quietPay,
            requestId: requestId
        )
        state.balance -= draft.amount
        state.records.insert(record, at: 0)
        save(state)
        return (state, record)
    }

    static func parsePaymentDraft(_ arguments: [String: JSONValue]) -> PaymentDraft {
        PaymentDraft(
            merchant: string("merchant", in: arguments, defaultValue: "Unknown merchant"),
            amount: number("amount", in: arguments),
            currency: string("currency", in: arguments, defaultValue: "CNY"),
            note: string("note", in: arguments)
        )
    }

    static func result(
        state: WalletState,
        message: String,
        status: String = "ok",
        record: PaymentRecord? = nil,
        records: [PaymentRecord] = [],
        quietPayApplied: Bool = false
    ) -> [String: JSONValue] {
        var value: [String: JSONValue] = [
            "status": .string(status),
            "balance": .number(roundMoney(state.balance)),
            "balance_display": .string("¥\(money(state.balance)) CNY"),
            "remaining_balance_text": .string("Remaining balance is ¥\(money(state.balance)) CNY."),
            "quiet_pay_applied": .bool(quietPayApplied),
            "message": .string(message),
            "quiet_pay_enabled": .bool(state.quietPayEnabled),
            "quiet_pay_limit": .number(roundMoney(state.quietPayLimit)),
            "quiet_pay_limit_display": .string("¥\(money(state.quietPayLimit)) CNY"),
        ]
        if let record {
            value["record"] = record.jsonValue
        }
        if !records.isEmpty {
            value["records"] = .array(records.map(\.jsonValue))
        }
        return value
    }

    static func string(_ key: String, in object: [String: JSONValue], defaultValue: String = "") -> String {
        guard case .string(let value)? = object[key] else { return defaultValue }
        return value
    }

    static func number(_ key: String, in object: [String: JSONValue], defaultValue: Double = 0) -> Double {
        guard let value = object[key] else { return defaultValue }
        switch value {
        case .number(let number):
            return number
        case .string(let string):
            return Double(string) ?? defaultValue
        default:
            return defaultValue
        }
    }

    static func bool(_ key: String, in object: [String: JSONValue], defaultValue: Bool = false) -> Bool {
        guard case .bool(let value)? = object[key] else { return defaultValue }
        return value
    }

    private static func save(_ state: WalletState) {
        guard let data = try? JSONEncoder().encode(state) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}

func money(_ value: Double) -> String {
    String(format: "%.2f", value)
}

func roundMoney(_ value: Double) -> Double {
    Double(money(value)) ?? value
}
