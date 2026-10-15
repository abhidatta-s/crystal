import SwiftUI

/// Height of the top row. The traffic lights are re-centred in it (see Glass.swift).
let chromeRowHeight: CGFloat = 38
/// Room the traffic lights need when the sidebar is collapsed.
let trafficLightsWidth: CGFloat = 80

struct ContentView: View {
    @StateObject private var model: BrowserWindowModel

    init(isPrivate: Bool) {
        _model = StateObject(wrappedValue: BrowserWindowModel(isPrivate: isPrivate))
    }

    var body: some View {
        HStack(spacing: 0) {
            if model.sidebarVisible {
                SidebarView(model: model)
                    .frame(width: 220)
                    .transition(.move(edge: .leading))
            }
            VStack(spacing: 0) {
                if let tab = model.activeTab {
                    ToolbarView(model: model, tab: tab)
                    WebView(webView: tab.webView)
                        .padding(.leading, model.sidebarVisible ? 0 : 6)
                        .padding([.trailing, .bottom], 6)
                } else {
                    Spacer()
                }
            }
        }
        .ignoresSafeArea(.container, edges: .top)
        .background(GlassBackground().ignoresSafeArea())
        .background(WindowConfigurator { window in model.attach(to: window) })
    }
}
