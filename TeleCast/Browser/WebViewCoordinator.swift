import WebKit
import CastCore

/// Navigation/UI delegate of the browser: applies the navigation guard (ads, popups,
/// redirects) and forwards detector messages to the model.
@MainActor
final class WebViewCoordinator: NSObject, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler {
    weak var model: BrowserModel?
    var guardrail: NavigationGuard

    init(adMatcher: AdHostMatcher, blockRedirects: Bool) {
        guardrail = NavigationGuard(blockRedirects: blockRedirects, adMatcher: adMatcher)
        super.init()
    }

    func noteUserIntent() {
        guardrail.noteUserIntent(at: Date())
    }

    static func kind(_ type: WKNavigationType) -> NavigationKind {
        switch type {
        case .linkActivated: return .linkActivated
        case .formSubmitted: return .formSubmitted
        case .backForward: return .backForward
        case .reload: return .reload
        case .formResubmitted: return .formResubmitted
        case .other: return .other
        @unknown default: return .other
        }
    }

    // MARK: WKScriptMessageHandler

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let decoded = DetectorMessage.decode(from: message.body) else { return }
        model?.handleDetector(decoded, frame: message.frameInfo)
    }

    // MARK: WKNavigationDelegate

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = navigationAction.request.url else {
            decisionHandler(.allow)
            return
        }
        if navigationAction.shouldPerformDownload {
            decisionHandler(.cancel)
            return
        }
        let isMainFrame = navigationAction.targetFrame?.isMainFrame ?? true
        let decision = guardrail.decide(url: url, isMainFrame: isMainFrame, kind: Self.kind(navigationAction.navigationType),
                                        currentURL: webView.url, now: Date())
        switch decision {
        case .allow:
            decisionHandler(.allow)
        case .block(let reason):
            decisionHandler(.cancel)
            model?.didBlock(reason, url: url)
        }
    }

    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        model?.pageDidCommit()
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        model?.pageDidFinish()
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        model?.pageDidFail(error)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        model?.pageDidFail(error)
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        castLog("browser", "Le moteur web s'est arrêté, rechargement")
        webView.reload()
    }

    // MARK: WKUIDelegate

    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        let url = navigationAction.request.url
        switch guardrail.decidePopup(url: url, kind: Self.kind(navigationAction.navigationType)) {
        case .openInPlace:
            if let url { webView.load(URLRequest(url: url)) }
        case .block:
            model?.didBlockPopup(url)
        }
        return nil
    }

    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
        completionHandler()
    }

    func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void) {
        completionHandler(false)
    }

    func webView(_ webView: WKWebView, runJavaScriptTextInputPanelWithPrompt prompt: String, defaultText: String?,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (String?) -> Void) {
        completionHandler(nil)
    }
}
