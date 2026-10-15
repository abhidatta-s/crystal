import AppKit
import SwiftUI
import WebKit

/// State for one browser window: its tabs, the active tab, and the website
/// data store they share (persistent, or in-memory for private windows).
@MainActor
final class BrowserWindowModel: ObservableObject {
    nonisolated static let homeURL = URL(string: "https://duckduckgo.com")!
    nonisolated static let maxClosedTabs = 25

    let isPrivate: Bool
    let faviconSession: URLSession
    var faviconCache: [String: NSImage] = [:]

    @Published private(set) var tabs: [Tab] = []
    @Published private(set) var activeTabID: Tab.ID?
    @Published private(set) var sidebarVisible = true
    /// Bumped to ask the toolbar to focus the address field.
    @Published private(set) var addressFocusRequest = 0

    private let dataStore: WKWebsiteDataStore
    private weak var window: NSWindow?
    private var closedTabs: [(url: URL, index: Int)] = []
    /// Where the last background tab from a given opener went, so a run of
    /// Cmd-clicks keeps page order (like Safari and Chrome).
    private var lastInsertion: (openerID: Tab.ID, index: Int)?

    private static let registry = NSMapTable<NSWindow, BrowserWindowModel>.weakToWeakObjects()

    /// The model of the key window, if it is a browser window.
    static var active: BrowserWindowModel? {
        guard let window = NSApp.keyWindow else { return nil }
        return registry.object(forKey: window)
    }

    init(isPrivate: Bool) {
        self.isPrivate = isPrivate
        dataStore = isPrivate ? .nonPersistent() : .default()
        faviconSession = isPrivate ? URLSession(configuration: .ephemeral) : .shared
        newTab(focusAddress: false)
    }

    var activeTab: Tab? {
        tabs.first { $0.id == activeTabID } ?? tabs.first
    }

    func attach(to window: NSWindow) {
        guard self.window !== window else { return }
        self.window = window
        Self.registry.setObject(self, forKey: window)
        // Private windows must not come back after a relaunch.
        window.isRestorable = !isPrivate
    }

    // MARK: Tabs

    func newTab(url: URL = BrowserWindowModel.homeURL, focusAddress: Bool = true) {
        let tab = Tab(configuration: makeConfiguration(), owner: self)
        tabs.append(tab)
        select(tab.id)
        tab.load(url)
        if focusAddress { focusAddressBar() }
    }

    /// Adds a tab whose web view WebKit will drive (popups / target=_blank).
    @discardableResult
    func openTab(configuration: WKWebViewConfiguration, from opener: Tab, select shouldSelect: Bool) -> Tab {
        let tab = Tab(configuration: configuration, owner: self)
        insert(tab, after: opener)
        if shouldSelect { select(tab.id) }
        return tab
    }

    /// Opens a request in a new tab next to its opener (Cmd-click, middle-click).
    func openTab(request: URLRequest, from opener: Tab, select shouldSelect: Bool) {
        let tab = openTab(configuration: makeConfiguration(), from: opener, select: shouldSelect)
        tab.webView.load(request)
    }

    func select(_ id: Tab.ID) {
        activeTabID = id
        lastInsertion = nil
    }

    func selectNextTab() { cycle(by: 1) }
    func selectPreviousTab() { cycle(by: -1) }

    /// Cmd-1…8 pick that tab; Cmd-9 picks the last one.
    func selectTab(number: Int) {
        guard !tabs.isEmpty else { return }
        let index = number == 9 ? tabs.count - 1 : number - 1
        guard tabs.indices.contains(index) else { return }
        select(tabs[index].id)
    }

    func closeActiveTab() {
        if let id = activeTab?.id { closeTab(id) }
    }

    func closeTab(_ id: Tab.ID) {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        let wasActive = activeTab?.id == id
        let tab = tabs.remove(at: index)
        if let url = tab.url {
            closedTabs.append((url, index))
            if closedTabs.count > Self.maxClosedTabs { closedTabs.removeFirst() }
        }
        tab.tearDown()
        lastInsertion = nil

        if tabs.isEmpty {
            activeTabID = nil
            window?.close()
            return
        }
        if wasActive {
            activeTabID = tabs[min(index, tabs.count - 1)].id
        }
    }

    func reopenClosedTab() {
        guard let closed = closedTabs.popLast() else { return }
        let tab = Tab(configuration: makeConfiguration(), owner: self)
        tabs.insert(tab, at: min(closed.index, tabs.count))
        select(tab.id)
        tab.load(closed.url)
    }

    // MARK: Chrome

    func toggleSidebar() {
        withAnimation(.easeInOut(duration: 0.2)) { sidebarVisible.toggle() }
    }

    func focusAddressBar() {
        addressFocusRequest += 1
    }

    func focusWebView() {
        guard let tab = activeTab else { return }
        window?.makeFirstResponder(tab.webView)
    }

    // MARK: Keyboard

    /// Ctrl-Tab / Ctrl-Shift-Tab. Returns true when the event was used.
    static func handleTabCyclingKey(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard event.keyCode == 48, // Tab
              flags.contains(.control),
              !flags.contains(.command), !flags.contains(.option),
              let model = active else { return false }
        if flags.contains(.shift) {
            model.selectPreviousTab()
        } else {
            model.selectNextTab()
        }
        return true
    }

    // MARK: Private

    private func makeConfiguration() -> WKWebViewConfiguration {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = dataStore
        // Without a Safari-style suffix some sites serve degraded pages to WKWebView.
        configuration.applicationNameForUserAgent = "Version/17.0 Safari/605.1.15"
        return configuration
    }

    private func insert(_ tab: Tab, after opener: Tab) {
        guard let openerIndex = tabs.firstIndex(where: { $0 === opener }) else {
            tabs.append(tab)
            return
        }
        var index = openerIndex + 1
        if let last = lastInsertion, last.openerID == opener.id, last.index < tabs.count {
            index = last.index + 1
        }
        index = min(index, tabs.count)
        tabs.insert(tab, at: index)
        lastInsertion = (opener.id, index)
    }

    private func cycle(by step: Int) {
        guard tabs.count > 1, let current = activeTab,
              let index = tabs.firstIndex(where: { $0 === current }) else { return }
        let next = (index + step + tabs.count) % tabs.count
        select(tabs[next].id)
    }
}
