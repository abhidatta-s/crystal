import AppKit
import SwiftUI

/// Menu bar commands. Each one acts on the browser window that is key.
struct BrowserCommands: Commands {
    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            NewItemButtons()
        }

        // Replaces the system "Close" so Cmd-W closes a tab, not the window.
        CommandGroup(replacing: .saveItem) {
            Button("Close Tab") {
                if let model = BrowserWindowModel.active {
                    model.closeActiveTab()
                } else {
                    NSApp.keyWindow?.performClose(nil)
                }
            }
            .keyboardShortcut("w")

            Button("Close Window") { NSApp.keyWindow?.performClose(nil) }
                .keyboardShortcut("w", modifiers: [.command, .shift])
        }

        CommandGroup(replacing: .sidebar) {
            Button("Toggle Sidebar") { BrowserWindowModel.active?.toggleSidebar() }
                .keyboardShortcut("s")
            Button("Reload Page") { BrowserWindowModel.active?.activeTab?.reload() }
                .keyboardShortcut("r")
            Divider()
        }

        CommandMenu("History") {
            Button("Back") { BrowserWindowModel.active?.activeTab?.goBack() }
                .keyboardShortcut("[")
            Button("Forward") { BrowserWindowModel.active?.activeTab?.goForward() }
                .keyboardShortcut("]")
            Divider()
            Button("Reopen Closed Tab") { BrowserWindowModel.active?.reopenClosedTab() }
                .keyboardShortcut("t", modifiers: [.command, .shift])
        }

        CommandMenu("Tab") {
            // Ctrl-Tab is actually handled by AppDelegate's key monitor;
            // these entries show the shortcut and work from the menu.
            Button("Select Next Tab") { BrowserWindowModel.active?.selectNextTab() }
                .keyboardShortcut(.tab, modifiers: .control)
            Button("Select Previous Tab") { BrowserWindowModel.active?.selectPreviousTab() }
                .keyboardShortcut(.tab, modifiers: [.control, .shift])
            Divider()
            ForEach(1..<10) { number in
                Button(number == 9 ? "Select Last Tab" : "Select Tab \(number)") {
                    BrowserWindowModel.active?.selectTab(number: number)
                }
                .keyboardShortcut(KeyEquivalent(Character(String(number))), modifiers: .command)
            }
        }
    }
}

/// A view so it can use openWindow (new windows when none is open).
private struct NewItemButtons: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("New Tab") {
            if let model = BrowserWindowModel.active {
                model.newTab()
            } else {
                openWindow(id: WindowID.main)
            }
        }
        .keyboardShortcut("t")

        Button("New Window") { openWindow(id: WindowID.main) }
            .keyboardShortcut("n")

        Button("New Private Window") { openWindow(id: WindowID.private) }
            .keyboardShortcut("n", modifiers: [.command, .shift])

        Divider()

        Button("Open Location…") {
            if let model = BrowserWindowModel.active {
                model.focusAddressBar()
            } else {
                openWindow(id: WindowID.main)
            }
        }
        .keyboardShortcut("l")
    }
}
