import SwiftUI

struct ToolbarView: View {
    @ObservedObject var model: BrowserWindowModel
    @ObservedObject var tab: Tab
    @FocusState private var addressFocused: Bool

    var body: some View {
        HStack(spacing: 4) {
            Button { model.toggleSidebar() } label: { Image(systemName: "sidebar.left") }
                .help("Toggle Sidebar (⌘S)")

            Button { tab.goBack() } label: { Image(systemName: "chevron.left") }
                .disabled(!tab.canGoBack)
                .help("Back (⌘[)")

            Button { tab.goForward() } label: { Image(systemName: "chevron.right") }
                .disabled(!tab.canGoForward)
                .help("Forward (⌘])")

            Button { tab.reloadOrStop() } label: {
                Image(systemName: tab.isLoading ? "xmark" : "arrow.clockwise")
            }
            .help(tab.isLoading ? "Stop" : "Reload (⌘R)")

            Spacer(minLength: 12)

            addressField
                .frame(maxWidth: 680)

            Spacer(minLength: 12)

            if model.isPrivate {
                Label("Private", systemImage: "eye.slash")
                    .font(.system(size: 11, weight: .medium))
                    .padding(.horizontal, 8)
                    .frame(height: 20)
                    .background(Capsule().fill(.quaternary))
                    .help("Private window: history, cookies and site data are not saved")
            }
        }
        .buttonStyle(.borderless)
        .imageScale(.medium)
        .padding(.leading, model.sidebarVisible ? 6 : trafficLightsWidth)
        .padding(.trailing, 10)
        .frame(height: chromeRowHeight)
        .background(WindowDragArea())
        .overlay(alignment: .bottom) {
            ProgressLine(progress: tab.progress, visible: tab.isLoading)
        }
        .onChange(of: model.addressFocusRequest) {
            addressFocused = true
        }
    }

    private var addressField: some View {
        TextField("Search or enter address", text: $tab.addressText)
            .textFieldStyle(.plain)
            .font(.system(size: 12))
            .focused($addressFocused)
            .onSubmit {
                tab.submit(tab.addressText)
                addressFocused = false
                model.focusWebView()
            }
            .onExitCommand {
                tab.resetAddressText()
                addressFocused = false
                model.focusWebView()
            }
            .onChange(of: addressFocused) { _, focused in
                if !focused && !tab.isLoading { tab.resetAddressText() }
            }
            .padding(.horizontal, 10)
            .frame(height: 26)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(.quaternary))
    }
}

/// Thin page-load progress bar along the bottom of the toolbar.
struct ProgressLine: View {
    let progress: Double
    let visible: Bool

    var body: some View {
        GeometryReader { geometry in
            Rectangle()
                .fill(Color.accentColor)
                .frame(width: geometry.size.width * max(0.05, min(progress, 1)))
                .animation(.easeOut(duration: 0.2), value: progress)
        }
        .frame(height: 2)
        .opacity(visible ? 1 : 0)
        .animation(.easeOut(duration: 0.25), value: visible)
        .allowsHitTesting(false)
    }
}
