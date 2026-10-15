import AppKit
import Combine
import WebKit

/// One tab: owns its WKWebView and mirrors the state the UI needs.
@MainActor
final class Tab: ObservableObject, Identifiable {
    nonisolated let id = UUID()
    let webView: WKWebView
    weak var owner: BrowserWindowModel?

    @Published var addressText = ""
    @Published private(set) var title: String?
    @Published private(set) var url: URL?
    @Published private(set) var favicon: NSImage?
    @Published private(set) var canGoBack = false
    @Published private(set) var canGoForward = false
    @Published private(set) var isLoading = false
    @Published private(set) var progress: Double = 0

    /// True for a tab WebKit just created for a popup, so its first
    /// navigation is not mistaken for a Cmd-click.
    var isOpeningPopup = false

    private let delegate: TabWebDelegate
    private var cancellables: Set<AnyCancellable> = []

    init(configuration: WKWebViewConfiguration, owner: BrowserWindowModel) {
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.allowsBackForwardNavigationGestures = true
        self.webView = webView
        self.owner = owner
        delegate = TabWebDelegate()

        delegate.tab = self
        webView.navigationDelegate = delegate
        webView.uiDelegate = delegate

        webView.publisher(for: \.title).assign(to: &$title)
        webView.publisher(for: \.canGoBack).assign(to: &$canGoBack)
        webView.publisher(for: \.canGoForward).assign(to: &$canGoForward)
        webView.publisher(for: \.isLoading).assign(to: &$isLoading)
        webView.publisher(for: \.estimatedProgress).assign(to: &$progress)
        webView.publisher(for: \.url)
            .sink { [weak self] url in self?.urlDidChange(url) }
            .store(in: &cancellables)
    }

    var displayTitle: String {
        if let title, !title.isEmpty { return title }
        return url?.host ?? "New Tab"
    }

    // MARK: Navigation

    func load(_ url: URL) {
        webView.load(URLRequest(url: url))
    }

    func submit(_ input: String) {
        guard let url = AddressBar.url(for: input) else { return }
        addressText = url.absoluteString
        load(url)
    }

    func goBack() { webView.goBack() }
    func goForward() { webView.goForward() }
    func reload() { webView.reload() }

    func reloadOrStop() {
        if webView.isLoading { webView.stopLoading() } else { webView.reload() }
    }

    /// Puts the current URL back in the address field (Esc, or leaving it).
    func resetAddressText() {
        addressText = url?.absoluteString ?? ""
    }

    func tearDown() {
        webView.stopLoading()
        webView.navigationDelegate = nil
        webView.uiDelegate = nil
        cancellables.removeAll()
    }

    // MARK: Favicon

    private static let faviconScript = """
    (function () {
      var l = document.querySelector("link[rel~='icon'][sizes='32x32'], link[rel~='icon'], link[rel='apple-touch-icon']");
      return l ? l.href : "";
    })();
    """

    /// Called when a page finishes loading.
    func refreshFavicon() {
        guard let pageURL = webView.url, let host = pageURL.host,
              let scheme = pageURL.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
            favicon = nil
            return
        }
        if let cached = owner?.faviconCache[host] {
            favicon = cached
            return
        }
        webView.evaluateJavaScript(Self.faviconScript) { [weak self] result, _ in
            guard let self else { return }
            let declared = (result as? String).flatMap { URL(string: $0) }
            let fallback = URL(string: "/favicon.ico", relativeTo: pageURL)?.absoluteURL
            guard let iconURL = declared.flatMap(Self.usableIconURL) ?? fallback else { return }
            self.fetchFavicon(from: iconURL, host: host)
        }
    }

    nonisolated private static func usableIconURL(_ url: URL) -> URL? {
        ["http", "https", "data"].contains(url.scheme?.lowercased() ?? "") ? url : nil
    }

    private func fetchFavicon(from iconURL: URL, host: String) {
        guard let session = owner?.faviconSession else { return }
        Task { [weak self] in
            guard let response = try? await session.data(from: iconURL) else { return }
            let data = response.0
            guard data.count < 1_000_000,
                  let image = NSImage(data: data),
                  let self, self.webView.url?.host == host else { return }
            self.favicon = image
            self.owner?.faviconCache[host] = image
        }
    }

    // MARK: Private

    private func urlDidChange(_ newURL: URL?) {
        if newURL?.host != url?.host { favicon = nil }
        url = newURL
        addressText = newURL?.absoluteString ?? ""
    }
}

/// WebKit delegate for one tab: new-tab policy for popups, Cmd-click and
/// middle-click, plus favicon refresh and crash recovery.
@MainActor
final class TabWebDelegate: NSObject, WKNavigationDelegate, WKUIDelegate {
    weak var tab: Tab?

    // target=_blank and window.open(). Link clicks open in the background
    // (Shift brings them forward); script-opened windows open in front.
    func webView(_ webView: WKWebView,
                 createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction,
                 windowFeatures: WKWindowFeatures) -> WKWebView? {
        guard let tab, let owner = tab.owner else { return nil }
        let isLinkClick = navigationAction.navigationType == .linkActivated
        let foreground = !isLinkClick || navigationAction.modifierFlags.contains(.shift)
        let newTab = owner.openTab(configuration: configuration, from: tab, select: foreground)
        newTab.isOpeningPopup = true
        return newTab.webView
    }

    func webView(_ webView: WKWebView,
                 decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
        guard let tab, let owner = tab.owner else { return .allow }
        if tab.isOpeningPopup {
            tab.isOpeningPopup = false
            return .allow
        }
        let flags = navigationAction.modifierFlags
        let wantsNewTab = navigationAction.navigationType == .linkActivated
            && (flags.contains(.command) || navigationAction.buttonNumber == 2)
        guard wantsNewTab else { return .allow }
        owner.openTab(request: navigationAction.request, from: tab, select: flags.contains(.shift))
        return .cancel
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        tab?.refreshFavicon()
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        webView.reload()
    }
}

/// Turns address-bar input into a URL: explicit http(s)/about URLs, bare
/// hostnames ("example.com", "localhost:3000"), otherwise a DuckDuckGo search.
enum AddressBar {
    static func url(for input: String) -> URL? {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }

        if let url = URL(string: text), let scheme = url.scheme?.lowercased(),
           ["http", "https", "about"].contains(scheme) {
            return url
        }

        let looksLikeHost = !text.contains(" ")
            && (text.contains(".") || text.hasPrefix("localhost"))
        if looksLikeHost, let url = URL(string: "https://" + text), url.host != nil {
            return url
        }

        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "&+=#?")
        let query = text.addingPercentEncoding(withAllowedCharacters: allowed) ?? text
        return URL(string: "https://duckduckgo.com/?q=" + query)
    }
}
