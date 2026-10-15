import AppKit
import SwiftUI

/// Untinted frosted glass that blurs whatever is behind the window and
/// follows the system light/dark appearance automatically.
struct GlassBackground: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .underWindowBackground

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
    }
}

/// Reaches the hosting NSWindow: transparent titlebar, edge-to-edge content,
/// and traffic lights centred in our taller top row.
struct WindowConfigurator: NSViewRepresentable {
    let onWindow: @MainActor (NSWindow) -> Void

    func makeNSView(context: Context) -> WindowConfiguringView {
        let view = WindowConfiguringView()
        view.onWindow = onWindow
        return view
    }

    func updateNSView(_ nsView: WindowConfiguringView, context: Context) {}
}

final class WindowConfiguringView: NSView {
    var onWindow: (@MainActor (NSWindow) -> Void)?

    private static let relayoutNotifications: [Notification.Name] = [
        NSWindow.didResizeNotification,
        NSWindow.didEndLiveResizeNotification,
        NSWindow.didExitFullScreenNotification,
        NSWindow.didBecomeKeyNotification,
        NSWindow.didResignKeyNotification,
    ]

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        super.viewWillMove(toWindow: newWindow)
        if let window {
            NotificationCenter.default.removeObserver(self, name: nil, object: window)
        }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard let window else { return }
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.titlebarSeparatorStyle = .none
        window.styleMask.insert(.fullSizeContentView)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.isMovableByWindowBackground = false // drag areas are explicit
        onWindow?(window)

        for name in Self.relayoutNotifications {
            NotificationCenter.default.addObserver(
                self, selector: #selector(windowLayoutChanged(_:)), name: name, object: window)
        }
        positionTrafficLights()
        // AppKit lays out the titlebar after the first pass; repeat once then.
        Task { @MainActor [weak self] in self?.positionTrafficLights() }
    }

    @objc private func windowLayoutChanged(_ notification: Notification) {
        positionTrafficLights()
    }

    /// Grows the titlebar container to our row height and centres the three
    /// buttons vertically in it. Horizontal positions are left to AppKit.
    private func positionTrafficLights() {
        guard let window, !window.styleMask.contains(.fullScreen),
              let close = window.standardWindowButton(.closeButton),
              let titlebar = close.superview,
              let container = titlebar.superview else { return }

        var frame = container.frame
        if frame.height != chromeRowHeight {
            frame.size.height = chromeRowHeight
            frame.origin.y = window.frame.height - chromeRowHeight
            container.frame = frame
        }
        let barHeight = titlebar.bounds.height
        for kind in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            guard let button = window.standardWindowButton(kind) else { continue }
            let y = ((barHeight - button.frame.height) / 2).rounded()
            if button.frame.origin.y != y {
                button.setFrameOrigin(NSPoint(x: button.frame.origin.x, y: y))
            }
        }
    }
}

/// Transparent strip that drags the window and handles title-bar double-click
/// (zoom or minimise, per System Settings). Put it behind empty chrome space.
struct WindowDragArea: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { WindowDragView() }
    func updateNSView(_ nsView: NSView, context: Context) {}
}

final class WindowDragView: NSView {
    override var mouseDownCanMoveWindow: Bool { true }

    override func mouseDown(with event: NSEvent) {
        guard let window else { return }
        if event.clickCount == 2 {
            switch UserDefaults.standard.string(forKey: "AppleActionOnDoubleClick") {
            case "Minimize": window.miniaturize(nil)
            case "None": break
            default: window.zoom(nil)
            }
        } else {
            window.performDrag(with: event)
        }
    }
}
