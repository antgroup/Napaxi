import AgentProvider
import UIKit

final class MainViewController: UIViewController {
    private let trustStore = TrustedHostStore(namespace: WalletPackage.providerId)

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Virtual Wallet"
        view.backgroundColor = UIColor(red: 0.96, green: 0.97, blue: 0.98, alpha: 1)
        render()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        render()
    }

    func refreshWalletState() {
        render()
    }

    func handleProviderURL(_ url: URL) {
        NSLog("VirtualWalletProvider: handling URL %@", url.absoluteString)
        if url.host == "agent", url.path == "/install" {
            handleInstall(url)
            return
        }
        if url.host == "agent", url.path == "/action" {
            handleAction(url)
        }
    }

    private func render() {
        let state = WalletStore.load()
        let scroll = UIScrollView()
        scroll.alwaysBounceVertical = true

        let root = UIStackView()
        root.axis = .vertical
        root.spacing = 16
        root.layoutMargins = UIEdgeInsets(top: 28, left: 20, bottom: 30, right: 20)
        root.isLayoutMarginsRelativeArrangement = true
        scroll.addSubview(root)
        view = scroll
        scroll.backgroundColor = UIColor(red: 0.96, green: 0.97, blue: 0.98, alpha: 1)
        root.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor),
            root.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor),
            root.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor),
            root.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor),
            root.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor),
        ])

        root.addArrangedSubview(header())
        root.addArrangedSubview(summaryCard(state))
        root.addArrangedSubview(settingsCard(state))
        root.addArrangedSubview(recordsCard(state))
    }

    private func header() -> UIView {
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 10
        stack.addArrangedSubview(label("Virtual Wallet", size: 30, weight: .bold, color: .ink))
        stack.addArrangedSubview(label("Provider Agent demo", size: 14, weight: .regular, color: .muted))
        stack.addArrangedSubview(button("Add to Agent Host", style: .primary) { [weak self] in
            self?.openHostInstall()
        })
        stack.addArrangedSubview(button("Ask Agent to review today") { [weak self] in
            self?.openHostTrigger()
        })
        return stack
    }

    private func summaryCard(_ state: WalletState) -> UIView {
        let stack = card()
        stack.addArrangedSubview(label("Balance", size: 13, weight: .regular, color: .muted))
        stack.addArrangedSubview(label("¥\(money(state.balance))", size: 36, weight: .bold, color: .ink))

        let row = UIStackView()
        row.axis = .horizontal
        row.distribution = .fillEqually
        row.spacing = 12
        row.addArrangedSubview(metric("Today", "¥\(money(state.todaySpending))"))
        row.addArrangedSubview(metric("Records", "\(state.records.count)"))
        stack.addArrangedSubview(row)
        return stack
    }

    private func settingsCard(_ state: WalletState) -> UIView {
        let stack = card()
        stack.addArrangedSubview(label("Quiet small payments", size: 17, weight: .semibold, color: .ink))

        let row = UIStackView()
        row.axis = .horizontal
        row.alignment = .center
        row.spacing = 10
        let toggle = UISwitch()
        toggle.isOn = state.quietPayEnabled
        toggle.addAction(UIAction { [weak self] _ in
            WalletStore.updateQuietPay(enabled: toggle.isOn, limit: WalletStore.load().quietPayLimit)
            self?.render()
        }, for: .valueChanged)
        row.addArrangedSubview(toggle)
        row.addArrangedSubview(label(
            state.quietPayEnabled ? "Enabled under ¥\(money(state.quietPayLimit))" : "Disabled",
            size: 15,
            weight: .regular,
            color: .body
        ))
        stack.addArrangedSubview(row)

        let limitRow = UIStackView()
        limitRow.axis = .horizontal
        limitRow.distribution = .fillEqually
        limitRow.spacing = 10
        limitRow.addArrangedSubview(button("-10") { [weak self] in
            WalletStore.updateQuietPay(enabled: state.quietPayEnabled, limit: state.quietPayLimit - 10)
            self?.render()
        })
        limitRow.addArrangedSubview(label("Limit ¥\(money(state.quietPayLimit))", size: 15, weight: .semibold, color: .ink, alignment: .center))
        limitRow.addArrangedSubview(button("+10") { [weak self] in
            WalletStore.updateQuietPay(enabled: state.quietPayEnabled, limit: state.quietPayLimit + 10)
            self?.render()
        })
        stack.addArrangedSubview(limitRow)

        let tools = UIStackView()
        tools.axis = .horizontal
        tools.distribution = .fillEqually
        tools.spacing = 10
        tools.addArrangedSubview(button("Clear records") { [weak self] in
            WalletStore.clearRecords()
            self?.render()
        })
        tools.addArrangedSubview(button("Reset") { [weak self] in
            WalletStore.reset()
            self?.render()
        })
        stack.addArrangedSubview(tools)
        return stack
    }

    private func recordsCard(_ state: WalletState) -> UIView {
        let stack = card()
        stack.addArrangedSubview(label("Payment records", size: 17, weight: .semibold, color: .ink))
        if state.records.isEmpty {
            stack.addArrangedSubview(label("No payments yet.", size: 14, weight: .regular, color: .muted))
        } else {
            state.records.prefix(20).forEach { stack.addArrangedSubview(recordRow($0)) }
        }
        return stack
    }

    private func openHostInstall() {
        guard var components = URLComponents(string: WalletPackage.hostInstallURL) else { return }
        components.queryItems = [
            URLQueryItem(name: "install_url", value: WalletPackage.installURL),
            URLQueryItem(name: "action_url", value: WalletPackage.actionURL),
            URLQueryItem(name: "universal_link_domain", value: "wallet-provider.local"),
            URLQueryItem(name: "ios_bundle_id", value: Bundle.main.bundleIdentifier ?? "demo.wallet.provider"),
            URLQueryItem(name: "label", value: "Virtual Wallet Agent"),
        ]
        guard let url = components.url else { return }
        UIApplication.shared.open(url)
    }

    private func openHostTrigger() {
        guard let binding = trustStore.loadLatestBinding(),
              let hostURL = URL(string: WalletPackage.hostTriggerURL) else { return }
        let now = Date()
        let requestId = UUID().uuidString
        let trigger = AgentProvider.signTriggerRequest(AgentTriggerRequest(
            requestId: requestId,
            providerId: WalletPackage.providerId,
            agentId: WalletPackage.agentId,
            message: "提醒我查看今日支出，并总结最近的虚拟消费记录",
            source: "virtual_wallet",
            eventType: "review_spending_requested",
            payload: [
                "event_id": .string(requestId),
                "view": .string("today_spending"),
            ],
            createdAt: ISO8601DateFormatter().string(from: now),
            expiresAt: ISO8601DateFormatter().string(from: now.addingTimeInterval(5 * 60)),
            nonce: UUID().uuidString,
            idempotencyKey: requestId
        ), binding: binding)
        guard let url = try? AgentProvider.buildHostTriggerURL(request: trigger, hostURL: hostURL) else {
            return
        }
        UIApplication.shared.open(url)
    }

    private func handleInstall(_ url: URL) {
        guard let request = AgentProvider.parseInstallRequest(url: url) else {
            NSLog("VirtualWalletProvider: failed to parse install request")
            return
        }
        trustStore.saveBinding(TrustedHostBinding(
            hostBundleId: request.hostBundleId,
            hostTeamId: request.hostTeamId,
            hostCallbackScheme: request.hostCallbackScheme,
            hostInstanceId: request.hostInstanceId,
            hostSharedSecret: request.hostSharedSecret,
            installedAt: ISO8601DateFormatter().string(from: Date()),
            protocolVersion: request.protocolVersion
        ))
        guard let callback = try? AgentProvider.buildInstallCallbackURL(
            packageDef: WalletPackage.packageDef,
            request: request
        ) else {
            NSLog("VirtualWalletProvider: failed to build install callback URL")
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            UIApplication.shared.open(callback) { success in
                NSLog("VirtualWalletProvider: install callback opened=%@", success ? "true" : "false")
            }
        }
    }

    private func handleAction(_ url: URL) {
        guard let proposal = AgentProvider.parseProposal(url: url),
              let callbackURL = callbackURL(from: url) else {
            return
        }

        let trust = AgentProvider.validateTrustedProposal(
            proposal: proposal,
            packageDef: WalletPackage.packageDef,
            store: trustStore
        )
        if !canContinue(with: trust) {
            finish(proposal: proposal, status: "failed", result: WalletStore.result(
                state: WalletStore.load(),
                message: trust.message ?? "Invalid proposal.",
                status: "failed"
            ), error: trust.code, callbackURL: callbackURL)
            return
        }

        switch proposal.actionId {
        case WalletPackage.actionPay:
            handlePay(proposal, trust: trust, callbackURL: callbackURL)
        case WalletPackage.actionListRecords:
            handleRecords(proposal, trust: trust, callbackURL: callbackURL)
        case WalletPackage.actionConfigureQuietPay:
            showConfigureConfirmation(proposal, trust: trust, callbackURL: callbackURL)
        default:
            finish(proposal: proposal, status: "failed", result: WalletStore.result(
                state: WalletStore.load(),
                message: "Unsupported action: \(proposal.actionId)",
                status: "failed"
            ), error: "unsupported_action", callbackURL: callbackURL)
        }
    }

    private func handlePay(_ proposal: ActionProposal, trust: TrustedProposalValidationResult, callbackURL: URL) {
        let draft = WalletStore.parsePaymentDraft(proposal.arguments)
        guard draft.isValid else {
            finish(proposal: proposal, status: "failed", result: WalletStore.result(
                state: WalletStore.load(),
                message: "Payment requires a merchant and positive amount.",
                status: "failed"
            ), error: "invalid_payment", callbackURL: callbackURL)
            return
        }
        let state = WalletStore.load()
        let quietPay = trust.isTrusted && state.quietPayEnabled && draft.amount <= state.quietPayLimit
        if quietPay {
            let (next, record) = WalletStore.addPayment(
                draft: draft,
                requestId: proposal.requestId,
                confirmedByUser: false,
                quietPay: true
            )
            markConsumedIfTrusted(proposal, trust)
            refreshWalletState()
            finish(proposal: proposal, status: "succeeded", result: WalletStore.result(
                state: next,
                message: paymentMessage(draft, next, "with quiet pay"),
                record: record,
                quietPayApplied: true
            ), callbackURL: callbackURL)
            return
        }
        showPaymentConfirmation(proposal, draft: draft, state: state, trust: trust, callbackURL: callbackURL)
    }

    private func handleRecords(_ proposal: ActionProposal, trust: TrustedProposalValidationResult, callbackURL: URL) {
        let limit = min(max(Int(WalletStore.number("limit", in: proposal.arguments, defaultValue: 10)), 1), 20)
        let state = WalletStore.load()
        markConsumedIfTrusted(proposal, trust)
        finish(proposal: proposal, status: "succeeded", result: WalletStore.result(
            state: state,
            message: "Returned \(min(limit, state.records.count)) payment records.",
            records: Array(state.records.prefix(limit))
        ), callbackURL: callbackURL)
    }

    private func showPaymentConfirmation(
        _ proposal: ActionProposal,
        draft: PaymentDraft,
        state: WalletState,
        trust: TrustedProposalValidationResult,
        callbackURL: URL
    ) {
        let controller = ConfirmationViewController(
            titleText: "Confirm payment",
            subtitle: "Virtual Wallet Provider",
            rows: [
                ("Merchant", draft.merchant),
                ("Amount", "¥\(money(draft.amount)) \(draft.currency)"),
                ("Note", draft.note.isEmpty ? "-" : draft.note),
                ("Quiet pay", state.quietPayEnabled ? "Enabled under ¥\(money(state.quietPayLimit))" : "Disabled"),
                ("Source", trust.isTrusted ? "Trusted host" : "Untrusted, confirmation required"),
            ],
            confirmText: "Pay",
            onCancel: { [weak self] in
                self?.finish(proposal: proposal, status: "canceled", result: WalletStore.result(
                    state: WalletStore.load(),
                    message: "Payment canceled by provider user.",
                    status: "canceled"
                ), error: "user_canceled", callbackURL: callbackURL)
            },
            onConfirm: { [weak self] in
                let (next, record) = WalletStore.addPayment(
                    draft: draft,
                    requestId: proposal.requestId,
                    confirmedByUser: true,
                    quietPay: false
                )
                self?.markConsumedIfTrusted(proposal, trust)
                self?.refreshWalletState()
                self?.finish(proposal: proposal, status: "succeeded", result: WalletStore.result(
                    state: next,
                    message: self?.paymentMessage(draft, next, "after provider confirmation") ?? "",
                    record: record
                ), callbackURL: callbackURL)
            }
        )
        navigationController?.present(controller, animated: true)
    }

    private func showConfigureConfirmation(
        _ proposal: ActionProposal,
        trust: TrustedProposalValidationResult,
        callbackURL: URL
    ) {
        let state = WalletStore.load()
        let enabled = proposal.arguments["enabled"].flatMap { value -> Bool? in
            if case .bool(let bool) = value { return bool }
            return nil
        } ?? state.quietPayEnabled
        let limit = WalletStore.number("limit", in: proposal.arguments, defaultValue: state.quietPayLimit)

        let controller = ConfirmationViewController(
            titleText: "Update quiet pay",
            subtitle: "Virtual Wallet Provider",
            rows: [
                ("New status", enabled ? "Enabled" : "Disabled"),
                ("New limit", "¥\(money(limit))"),
                ("Current limit", "¥\(money(state.quietPayLimit))"),
                ("Source", trust.isTrusted ? "Trusted host" : "Untrusted, confirmation required"),
            ],
            confirmText: "Update",
            onCancel: { [weak self] in
                self?.finish(proposal: proposal, status: "canceled", result: WalletStore.result(
                    state: WalletStore.load(),
                    message: "Quiet pay update canceled.",
                    status: "canceled"
                ), error: "user_canceled", callbackURL: callbackURL)
            },
            onConfirm: { [weak self] in
                let next = WalletStore.updateQuietPay(enabled: enabled, limit: limit)
                self?.markConsumedIfTrusted(proposal, trust)
                self?.refreshWalletState()
                self?.finish(proposal: proposal, status: "succeeded", result: WalletStore.result(
                    state: next,
                    message: "Quiet pay \(next.quietPayEnabled ? "enabled" : "disabled") under ¥\(money(next.quietPayLimit))."
                ), callbackURL: callbackURL)
            }
        )
        navigationController?.present(controller, animated: true)
    }

    private func finish(
        proposal: ActionProposal,
        status: String,
        result: [String: JSONValue],
        error: String? = nil,
        callbackURL: URL
    ) {
        let actionResult = ActionResult(
            requestId: proposal.requestId,
            status: status,
            result: result,
            error: error,
            providerTraceId: "wallet-\(Int(Date().timeIntervalSince1970 * 1000))",
            completedAt: ISO8601DateFormatter().string(from: Date())
        )
        guard let url = try? AgentProvider.buildResultCallbackURL(result: actionResult, callbackURL: callbackURL) else {
            return
        }
        dismiss(animated: false) {
            UIApplication.shared.open(url)
        }
    }

    private func callbackURL(from url: URL) -> URL? {
        guard let value = URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?
            .first(where: { $0.name == "callback_url" })?
            .value else {
            return nil
        }
        return URL(string: value)
    }

    private func canContinue(with result: TrustedProposalValidationResult) -> Bool {
        result.isValid || result.status == TrustedProposalStatus.untrusted
    }

    private func markConsumedIfTrusted(_ proposal: ActionProposal, _ trust: TrustedProposalValidationResult) {
        if trust.isTrusted {
            AgentProvider.markProposalConsumed(store: trustStore, proposal: proposal)
        }
    }

    private func paymentMessage(_ draft: PaymentDraft, _ state: WalletState, _ suffix: String) -> String {
        "Paid ¥\(money(draft.amount)) \(draft.currency) to \(draft.merchant) \(suffix). Remaining balance is ¥\(money(state.balance)) CNY."
    }

    private func card() -> UIStackView {
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 14
        stack.layoutMargins = UIEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
        stack.isLayoutMarginsRelativeArrangement = true
        stack.backgroundColor = .white
        stack.layer.cornerRadius = 10
        stack.layer.borderColor = UIColor(red: 0.88, green: 0.91, blue: 0.95, alpha: 1).cgColor
        stack.layer.borderWidth = 1
        return stack
    }

    private func metric(_ title: String, _ value: String) -> UIView {
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 5
        stack.addArrangedSubview(label(title, size: 12, weight: .regular, color: .muted))
        stack.addArrangedSubview(label(value, size: 20, weight: .semibold, color: .ink))
        return stack
    }

    private func recordRow(_ record: PaymentRecord) -> UIView {
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 7
        stack.layoutMargins = UIEdgeInsets(top: 14, left: 14, bottom: 14, right: 14)
        stack.isLayoutMarginsRelativeArrangement = true
        stack.backgroundColor = UIColor(red: 0.97, green: 0.98, blue: 0.99, alpha: 1)
        stack.layer.cornerRadius = 8

        let top = UIStackView()
        top.axis = .horizontal
        top.alignment = .center
        top.addArrangedSubview(label(record.merchant, size: 15, weight: .semibold, color: .ink))
        top.addArrangedSubview(UIView())
        top.addArrangedSubview(label("-¥\(money(record.amount))", size: 15, weight: .semibold, color: .danger))
        stack.addArrangedSubview(top)

        let mode = record.quietPay ? "quiet pay" : "confirmed"
        let detail = record.note.isEmpty ? mode : "\(mode) · \(record.note)"
        stack.addArrangedSubview(label(detail, size: 12, weight: .regular, color: .muted))
        return stack
    }

    private func button(_ text: String, style: ButtonStyle = .secondary, action: @escaping () -> Void) -> UIButton {
        let button = UIButton(type: .system)
        button.setTitle(text, for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: 15, weight: .semibold)
        button.layer.cornerRadius = 8
        var configuration = UIButton.Configuration.plain()
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 12, leading: 14, bottom: 12, trailing: 14)
        button.configuration = configuration
        if style == .primary {
            button.backgroundColor = UIColor(red: 0.05, green: 0.29, blue: 0.63, alpha: 1)
            button.tintColor = .white
        } else {
            button.backgroundColor = UIColor(red: 0.91, green: 0.94, blue: 0.98, alpha: 1)
            button.tintColor = UIColor(red: 0.05, green: 0.22, blue: 0.43, alpha: 1)
        }
        button.addAction(UIAction { _ in action() }, for: .touchUpInside)
        return button
    }

    private func label(
        _ text: String,
        size: CGFloat,
        weight: UIFont.Weight,
        color: UIColor,
        alignment: NSTextAlignment = .natural
    ) -> UILabel {
        let label = UILabel()
        label.text = text
        label.font = .systemFont(ofSize: size, weight: weight)
        label.textColor = color
        label.numberOfLines = 0
        label.textAlignment = alignment
        return label
    }
}

private enum ButtonStyle {
    case primary
    case secondary
}

private extension UIColor {
    static let ink = UIColor(red: 0.09, green: 0.13, blue: 0.20, alpha: 1)
    static let body = UIColor(red: 0.30, green: 0.36, blue: 0.45, alpha: 1)
    static let muted = UIColor(red: 0.44, green: 0.50, blue: 0.60, alpha: 1)
    static let danger = UIColor(red: 0.72, green: 0.21, blue: 0.21, alpha: 1)
}
