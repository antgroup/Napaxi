import UIKit

final class MainViewController: UIViewController {
    private let statusLabel = UILabel()

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Napaxi iOS Release"
        view.backgroundColor = .systemBackground

        statusLabel.numberOfLines = 0
        statusLabel.textAlignment = .center
        statusLabel.font = .preferredFont(forTextStyle: .body)
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(statusLabel)

        NSLayoutConstraint.activate([
            statusLabel.leadingAnchor.constraint(equalTo: view.layoutMarginsGuide.leadingAnchor),
            statusLabel.trailingAnchor.constraint(equalTo: view.layoutMarginsGuide.trailingAnchor),
            statusLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            statusLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor),
        ])

        statusLabel.text = makeReleaseSummary()
    }

    private func makeReleaseSummary() -> String {
        let bundle = Bundle.main
        let bundleIdentifier = bundle.bundleIdentifier ?? "unknown"
        let shortVersion = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
        let buildVersion = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown"

        return [
            "Napaxi iOS release app is installed.",
            "Bundle ID: \(bundleIdentifier)",
            "Version: \(shortVersion) (\(buildVersion))",
            "This build is signed and installed from a release IPA.",
        ].joined(separator: "\n")
    }
}
