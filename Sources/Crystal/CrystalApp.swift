import AppKit
import SwiftUI

@main
struct CrystalApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // Titles are hidden in the chrome but name the windows in the Window
        // menu and Mission Control. "About/Quit Crystal" come from CFBundleName.
        WindowGroup("Crystal", id: WindowID.main) {
            ContentView(isPrivate: false)
                .frame(minWidth: 640, minHeight: 400)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1200, height: 800)
        .commands { BrowserCommands() }

        WindowGroup("Crystal — Private", id: WindowID.private) {
            ContentView(isPrivate: true)
                .frame(minWidth: 640, minHeight: 400)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1200, height: 800)
    }
}

enum WindowID {
    static let main = "main"
    static let `private` = "private"
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var keyMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Ctrl-Tab never reaches the menu reliably (web views and text fields
        // eat Tab), so catch it before normal event dispatch.
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let handled = MainActor.assumeIsolated {
                BrowserWindowModel.handleTabCyclingKey(event)
            }
            return handled ? nil : event
        }
    }
}
