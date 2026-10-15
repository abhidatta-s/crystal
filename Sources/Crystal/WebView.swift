import SwiftUI
import WebKit

/// Shows the active tab's WKWebView inside a rounded, clipped container.
/// Switching tabs swaps the hosted web view; inactive ones stay alive.
struct WebView: NSViewRepresentable {
    let webView: WKWebView

    func makeNSView(context: Context) -> NSView {
        let container = NSView()
        container.wantsLayer = true
        container.layer?.cornerRadius = 8
        container.layer?.cornerCurve = .continuous
        container.layer?.masksToBounds = true
        embed(webView, in: container)
        return container
    }

    func updateNSView(_ container: NSView, context: Context) {
        guard container.subviews.first !== webView else { return }
        let hadFocus = container.window?.firstResponder is WKWebView
        container.subviews.forEach { $0.removeFromSuperview() }
        embed(webView, in: container)
        if hadFocus { container.window?.makeFirstResponder(webView) }
    }

    private func embed(_ webView: WKWebView, in container: NSView) {
        webView.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(webView)
        NSLayoutConstraint.activate([
            webView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            webView.topAnchor.constraint(equalTo: container.topAnchor),
            webView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
    }
}
