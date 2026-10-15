import SwiftUI

/// Vertical tab list.
struct SidebarView: View {
    @ObservedObject var model: BrowserWindowModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Traffic-light row; empty space here drags the window.
            WindowDragArea()
                .frame(height: chromeRowHeight)

            ScrollView(.vertical) {
                VStack(spacing: 2) {
                    ForEach(model.tabs) { tab in
                        TabRow(
                            tab: tab,
                            isActive: tab.id == model.activeTab?.id,
                            onSelect: { model.select(tab.id) },
                            onClose: { model.closeTab(tab.id) }
                        )
                    }

                    Button { model.newTab() } label: {
                        Label("New Tab", systemImage: "plus")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 8)
                            .frame(maxWidth: .infinity, minHeight: 30, alignment: .leading)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("New Tab (⌘T)")
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 8)
            }
            .scrollIndicators(.never)
        }
    }
}

struct TabRow: View {
    @ObservedObject var tab: Tab
    let isActive: Bool
    let onSelect: () -> Void
    let onClose: () -> Void

    @State private var hovering = false

    var body: some View {
        HStack(spacing: 8) {
            favicon
                .frame(width: 16, height: 16)

            Text(tab.displayTitle)
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer(minLength: 0)

            if hovering {
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                        .frame(width: 16, height: 16)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .help("Close Tab (⌘W)")
            }
        }
        .font(.system(size: 12))
        .padding(.horizontal, 8)
        .frame(height: 30)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Color.primary.opacity(isActive ? 0.12 : (hovering ? 0.06 : 0)))
        )
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
        .onHover { hovering = $0 }
        .help(tab.displayTitle)
    }

    @ViewBuilder private var favicon: some View {
        if let image = tab.favicon {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
        } else {
            Image(systemName: "globe")
                .foregroundStyle(.secondary)
        }
    }
}
