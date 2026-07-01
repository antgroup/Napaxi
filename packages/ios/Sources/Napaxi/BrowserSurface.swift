import Foundation

#if canImport(SwiftUI) && canImport(WebKit)
import SwiftUI
@preconcurrency import WebKit

public struct NapaxiBrowserSurface<Placeholder: View>: View {
    @ObservedObject private var controller: NapaxiWebKitBrowserController
    private let placeholder: Placeholder
    private let hasPlaceholder: Bool

    public init(
        controller: NapaxiWebKitBrowserController,
        @ViewBuilder placeholder: () -> Placeholder
    ) {
        self.controller = controller
        self.placeholder = placeholder()
        self.hasPlaceholder = true
    }

    public var body: some View {
        Group {
            if !controller.hasPage && hasPlaceholder {
                placeholder
            } else {
                NapaxiBrowserWebView(controller: controller)
            }
        }
    }
}

public extension NapaxiBrowserSurface where Placeholder == EmptyView {
    init(controller: NapaxiWebKitBrowserController) {
        self.controller = controller
        self.placeholder = EmptyView()
        self.hasPlaceholder = false
    }
}


public extension NapaxiWebKitBrowserController {
    func buildWidget() -> NapaxiBrowserSurface<EmptyView> {
        NapaxiBrowserSurface(controller: self)
    }
}

#if os(iOS)
private struct NapaxiBrowserWebView: UIViewRepresentable {
    let controller: NapaxiWebKitBrowserController

    func makeUIView(context: Context) -> WKWebView {
        controller.buildWebView()
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}
}
#elseif os(macOS)
private struct NapaxiBrowserWebView: NSViewRepresentable {
    let controller: NapaxiWebKitBrowserController

    func makeNSView(context: Context) -> WKWebView {
        controller.buildWebView()
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {}
}
#endif
#endif
