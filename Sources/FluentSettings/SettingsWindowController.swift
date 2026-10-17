import AppKit
import WebKit

/// The window: a transparent title bar over the pages, which draw their own
/// header below it, magpie-style.
final class SettingsWindowController: NSWindowController, WKNavigationDelegate, WKUIDelegate {
    private let bridge = Bridge()

    convenience init() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 780, height: 620),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                              backing: .buffered, defer: false)
        window.title = "Fluent"
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.minSize = NSSize(width: 640, height: 480)
        window.center()
        window.setFrameAutosaveName("FluentSettings")
        self.init(window: window)

        let configuration = WKWebViewConfiguration()
        configuration.userContentController.addScriptMessageHandler(bridge, contentWorld: .page, name: "fluent")
        let web = WKWebView(frame: window.contentLayoutRect, configuration: configuration)
        web.setValue(false, forKey: "drawsBackground")  // no white flash before the dark theme paints
        web.navigationDelegate = self
        web.uiDelegate = self
        window.contentView = web
        bridge.window = window

        let pages = Bundle.main.resourceURL!.appendingPathComponent("Settings")
        web.loadFileURL(pages.appendingPathComponent("index.html"), allowingReadAccessTo: pages)
    }

    /// The pages stay put; any other link opens in the browser.
    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = action.request.url, !url.isFileURL else { return decisionHandler(.allow) }
        NSWorkspace.shared.open(url)
        decisionHandler(.cancel)
    }

    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
        let alert = NSAlert()
        alert.messageText = message
        alert.beginSheetModal(for: window!) { _ in completionHandler() }
    }
}
