import UIKit
import WebKit
import CastCore

enum WebViewFactory {
    /// The browser web view: detector injected in every frame, Safari-like user agent, inline playback.
    @MainActor
    static func make(coordinator: WebViewCoordinator) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []
        configuration.websiteDataStore = .default()
        configuration.applicationNameForUserAgent = safariSuffix()

        let controller = configuration.userContentController
        if let url = Bundle.main.url(forResource: "detector", withExtension: "js"),
           let source = try? String(contentsOf: url, encoding: .utf8) {
            controller.addUserScript(WKUserScript(source: source, injectionTime: .atDocumentStart,
                                                  forMainFrameOnly: false, in: .page))
        } else {
            castLog("browser", "detector.js introuvable dans l'appli")
        }
        controller.add(WeakScriptHandler(target: coordinator), contentWorld: .page, name: "castDetector")

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = coordinator
        webView.uiDelegate = coordinator
        webView.allowsBackForwardNavigationGestures = true
        webView.allowsLinkPreview = false
        if #available(iOS 16.4, *) {
            webView.isInspectable = true
        }
        return webView
    }

    /// "Version/<iOS> Mobile/15E148 Safari/604.1" so sites treat us like Safari.
    @MainActor
    static func safariSuffix() -> String {
        let parts = UIDevice.current.systemVersion.split(separator: ".")
        let major = parts.first.map(String.init) ?? "17"
        let minor = parts.count > 1 ? String(parts[1]) : "0"
        return "Version/\(major).\(minor) Mobile/15E148 Safari/604.1"
    }
}

/// Breaks the retain cycle between WKUserContentController and the coordinator.
@MainActor
final class WeakScriptHandler: NSObject, WKScriptMessageHandler {
    weak var target: WKScriptMessageHandler?

    init(target: WKScriptMessageHandler) {
        self.target = target
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        target?.userContentController(userContentController, didReceive: message)
    }
}
