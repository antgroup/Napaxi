import UIKit

final class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?
    private var pendingProviderURLs: [URL] = []

    func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        guard let windowScene = scene as? UIWindowScene else { return }
        let window = UIWindow(windowScene: windowScene)
        let controller = MainViewController()
        window.rootViewController = UINavigationController(rootViewController: controller)
        self.window = window
        window.makeKeyAndVisible()

        for context in connectionOptions.urlContexts {
            enqueueProviderURL(context.url)
        }
    }

    func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
        for context in URLContexts {
            enqueueProviderURL(context.url)
        }
    }

    func sceneDidBecomeActive(_ scene: UIScene) {
        rootController?.refreshWalletState()
        flushPendingProviderURLs()
    }

    private func enqueueProviderURL(_ url: URL) {
        NSLog("VirtualWalletProvider: enqueue URL %@", url.absoluteString)
        pendingProviderURLs.append(url)
        DispatchQueue.main.async { [weak self] in
            self?.flushPendingProviderURLs()
        }
    }

    private func flushPendingProviderURLs() {
        guard let controller = rootController, !pendingProviderURLs.isEmpty else {
            return
        }
        let urls = pendingProviderURLs
        pendingProviderURLs.removeAll()
        for url in urls {
            controller.handleProviderURL(url)
        }
    }

    private var rootController: MainViewController? {
        (window?.rootViewController as? UINavigationController)?.viewControllers.first as? MainViewController
    }
}
