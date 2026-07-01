import UIKit

final class ConfirmationViewController: UIViewController {
    private let titleText: String
    private let subtitle: String
    private let rows: [(String, String)]
    private let confirmText: String
    private let onCancel: () -> Void
    private let onConfirm: () -> Void

    init(
        titleText: String,
        subtitle: String,
        rows: [(String, String)],
        confirmText: String,
        onCancel: @escaping () -> Void,
        onConfirm: @escaping () -> Void
    ) {
        self.titleText = titleText
        self.subtitle = subtitle
        self.rows = rows
        self.confirmText = confirmText
        self.onCancel = onCancel
        self.onConfirm = onConfirm
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .fullScreen
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor(red: 0.96, green: 0.97, blue: 0.98, alpha: 1)

        let root = UIStackView()
        root.axis = .vertical
        root.spacing = 18
        root.layoutMargins = UIEdgeInsets(top: 54, left: 22, bottom: 28, right: 22)
        root.isLayoutMarginsRelativeArrangement = true
        view.addSubview(root)
        root.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
            root.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
            root.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            root.bottomAnchor.constraint(lessThanOrEqualTo: view.safeAreaLayoutGuide.bottomAnchor),
        ])

        root.addArrangedSubview(label(titleText, size: 28, weight: .bold, color: .ink))
        root.addArrangedSubview(label(subtitle, size: 14, weight: .regular, color: .muted))

        let card = UIStackView()
        card.axis = .vertical
        card.spacing = 16
        card.layoutMargins = UIEdgeInsets(top: 22, left: 20, bottom: 22, right: 20)
        card.isLayoutMarginsRelativeArrangement = true
        card.backgroundColor = .white
        card.layer.cornerRadius = 10
        card.layer.borderWidth = 1
        card.layer.borderColor = UIColor(red: 0.88, green: 0.91, blue: 0.95, alpha: 1).cgColor
        rows.forEach { card.addArrangedSubview(detailRow($0.0, $0.1)) }
        root.addArrangedSubview(card)

        let actions = UIStackView()
        actions.axis = .horizontal
        actions.distribution = .fillEqually
        actions.spacing = 10
        actions.addArrangedSubview(button("Cancel", primary: false) { [weak self] in
            self?.onCancel()
        })
        actions.addArrangedSubview(button(confirmText, primary: true) { [weak self] in
            self?.onConfirm()
        })
        root.addArrangedSubview(actions)
    }

    private func detailRow(_ title: String, _ value: String) -> UIView {
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 6
        stack.addArrangedSubview(label(title, size: 12, weight: .regular, color: .muted))
        stack.addArrangedSubview(label(value, size: 18, weight: .semibold, color: .ink))
        return stack
    }

    private func button(_ text: String, primary: Bool, action: @escaping () -> Void) -> UIButton {
        let button = UIButton(type: .system)
        button.setTitle(text, for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: 16, weight: .semibold)
        button.layer.cornerRadius = 8
        var configuration = UIButton.Configuration.plain()
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 14, leading: 18, bottom: 14, trailing: 18)
        button.configuration = configuration
        if primary {
            button.backgroundColor = UIColor(red: 0.05, green: 0.29, blue: 0.63, alpha: 1)
            button.tintColor = .white
        } else {
            button.backgroundColor = UIColor(red: 0.90, green: 0.93, blue: 0.97, alpha: 1)
            button.tintColor = UIColor(red: 0.05, green: 0.22, blue: 0.43, alpha: 1)
        }
        button.addAction(UIAction { _ in action() }, for: .touchUpInside)
        return button
    }

    private func label(
        _ text: String,
        size: CGFloat,
        weight: UIFont.Weight,
        color: UIColor
    ) -> UILabel {
        let label = UILabel()
        label.text = text
        label.font = .systemFont(ofSize: size, weight: weight)
        label.textColor = color
        label.numberOfLines = 0
        return label
    }
}

private extension UIColor {
    static let ink = UIColor(red: 0.09, green: 0.13, blue: 0.20, alpha: 1)
    static let muted = UIColor(red: 0.44, green: 0.50, blue: 0.60, alpha: 1)
}
